import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/sev.dart';
import '../core/store.dart';

const estadosProcesando = ['Procesando', 'Analizando', 'Iniciando'];

/// Estado principal de la app: equivale al objeto `state` del index.html del MVP.
class AppState extends ChangeNotifier {
  AppState(this.store, {http.Client? client})
      : api = Api(store.getString(Store.kApi) ?? Config.apiPorDefecto(), client: client) {
    themeMode = store.getString(Store.kTheme) == 'light' ? ThemeMode.light : ThemeMode.dark;
    textScale = store.getDouble(Store.kFont) ?? 1.0;
    docActivo = store.getString(Store.kDoc);
    agenteActual = store.getString(Store.kAgente) ?? 'general';
    _ruta = {
      for (final e in store.getJson<Map>(Store.kRuta, {}).entries)
        if (e.value is Map) '${e.key}': Map<String, dynamic>.from(e.value as Map)
    };
    informeItems = [
      for (final i in store.getJson<List>(Store.kInforme, const [])) if (i is Map) Map<String, dynamic>.from(i)
    ];
  }

  final Store store;
  final Api api;

  // ---------------------------------------------------------------- preferencias
  late ThemeMode themeMode;
  late double textScale;

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    store.setString(Store.kTheme, themeMode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  void setTextScale(double v) {
    textScale = (v.clamp(0.8, 1.4) * 100).round() / 100;
    store.setDouble(Store.kFont, textScale);
    notifyListeners();
  }

  String get apiUrl => api.baseUrl;

  /// Cambia la dirección del servidor y recarga todo. Devuelve null si responde, o el error.
  Future<String?> setApi(String url) async {
    var u = url.trim();
    if (u.isEmpty) u = Config.apiPorDefecto();
    if (!u.startsWith('http')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    api.baseUrl = u;
    await store.setString(Store.kApi, u);
    final err = await probarConexion();
    await recargarTodo();
    return err;
  }

  Future<String?> probarConexion() async {
    try {
      await api.getJson('/api/agentes', timeout: const Duration(seconds: 6));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ---------------------------------------------------------------- avisos y navegación
  final _toasts = StreamController<({String msg, bool err})>.broadcast();
  Stream<({String msg, bool err})> get toasts => _toasts.stream;
  void toast(String m, {bool err = false}) => _toasts.add((msg: m, err: err));

  final _nav = StreamController<String>.broadcast();
  Stream<String> get navRequests => _nav.stream;

  /// Pestañas principales del menú inferior.
  static const tabs = ['inicio', 'analisis', 'memoria', 'gestion', 'mas'];
  int tab = 0;

  /// La vista de análisis reúne los hallazgos y el chat de IA.
  int analisisPestana = 0;

  void seleccionarAnalisis(int indice) {
    analisisPestana = indice.clamp(0, 1).toInt();
    notifyListeners();
  }

  /// Mantiene compatibles los accesos usados por las pantallas existentes.
  void go(String id) {
    if (id == 'docs' || id == 'documentos') {
      _nav.add('documentos');
      return;
    }
    if (id == 'chat' || id == 'resultados') {
      tab = tabs.indexOf('analisis');
      analisisPestana = id == 'chat' ? 1 : 0;
      notifyListeners();
      return;
    }
    final i = tabs.indexOf(id);
    if (i >= 0) {
      tab = i;
      notifyListeners();
    } else {
      _nav.add(id);
    }
  }

  // ---------------------------------------------------------------- agentes
  final List<Agente> agentes = agentesIniciales();
  int get totalAgentes => agentes.length;
  Agente? agente(String key) {
    for (final a in agentes) {
      if (a.key == key) return a;
    }
    return null;
  }

  String nombreAgente(String key) => key == 'general' ? 'Asistente general' : (agente(key)?.name ?? key);
  String badgeAgente(String key) =>
      key == 'general' ? 'GEN' : (agente(key)?.badge ?? key.substring(0, min(3, key.length)).toUpperCase());
  int ordenAgente(String key) {
    final i = agentes.indexWhere((a) => a.key == key);
    return i < 0 ? 99 : i;
  }

  Future<void> cargarAgentes() async {
    try {
      final d = await api.getJson('/api/agentes');
      final lista = [for (final a in (d['agentes'] as List? ?? const [])) if (a is Map && a['tipo'] != 'general') a];
      for (final a in lista) {
        var local = agente('${a['clave']}');
        if (local != null) {
          local.ola = (a['ola'] as num?)?.toInt() ?? local.ola;
          local.tipo = '${a['tipo']}';
        } else {
          final nombre = '${a['nombre'] ?? a['clave']}'
              .replaceFirst(RegExp(r'^Agente\s+'), '')
              .replaceFirst(RegExp(r'\s*\(.*\)\s*$'), '');
          final clave = '${a['clave']}';
          local = Agente(clave, nombre, clave.substring(0, min(3, clave.length)).toUpperCase(), '${a['tipo']}',
              (a['ola'] as num?)?.toInt() ?? 0, '${a['descripcion'] ?? ''}');
          agentes.add(local);
        }
        local.preguntaDirectorio = '${a['pregunta_directorio'] ?? ''}';
        local.guia = [for (final q in (a['preguntas_guia'] as List? ?? const [])) if (q is Map) Map<String, dynamic>.from(q)];
      }
      agentes.sort((x, y) => x.ola.compareTo(y.ola));
    } catch (_) {}
  }

  // ---------------------------------------------------------------- documentos
  bool backendOk = true;
  bool iniciado = false;
  List<Map<String, dynamic>> documentos = [];
  String? docActivo;
  Map<String, Map<String, dynamic>>? analisis; // {agente: resultado} del documento activo
  bool cargandoAnalisis = false;
  Timer? _watch;

  Map<String, dynamic>? get docActivoMap {
    for (final d in documentos) {
      if (d['id'] == docActivo) return d;
    }
    return null;
  }

  Future<void> init() async {
    await cargarAgentes();
    if (docActivo != null) _cargarChat(docActivo!);
    await cargarDocumentos(silencioso: true);
    if (docActivo != null && analisis == null && backendOk) await cargarAnalisis(docActivo!);
    iniciado = true;
    notifyListeners();
  }

  Future<void> recargarTodo() async {
    await cargarAgentes();
    await cargarDocumentos();
    if (backendOk && docActivo != null) await cargarAnalisis(docActivo!);
    notifyListeners();
  }

  Future<void> cargarDocumentos({bool silencioso = false}) async {
    try {
      final d = await api.getJson('/api/documentos');
      if (d['ok'] == false) throw ApiError('${d['error'] ?? 'el backend no pudo listar los documentos'}');
      backendOk = true;
      documentos = [for (final x in (d['documentos'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
      final ids = documentos.map((x) => x['id']).toSet();
      final antes = informeItems.length;
      informeItems.removeWhere((i) => !ids.contains(i['document_id']));
      if (informeItems.length != antes) _guardarInforme();
      if (docActivo == null || !ids.contains(docActivo)) {
        docActivo = documentos.isEmpty ? null : '${documentos.first['id']}';
        store.setString(Store.kDoc, docActivo);
        mensajes = [];
        sugerencias = [];
        analisis = null;
        if (docActivo != null) {
          _cargarChat(docActivo!);
          await cargarAnalisis(docActivo!);
        }
      }
    } catch (_) {
      backendOk = false;
    }
    _vigilar();
    if (!silencioso) notifyListeners();
  }

  /// Mientras haya documentos procesándose, relee la lista cada 4 s (como vigilarDocumentos()).
  void _vigilar() {
    if (_watch != null) return;
    if (!documentos.any((d) => estadosProcesando.contains(d['estado']))) return;
    final desde = DateTime.now();
    _watch = Timer.periodic(const Duration(seconds: 4), (t) async {
      if (subiendo) return;
      final antes = docActivoMap;
      final enProceso = antes != null && estadosProcesando.contains(antes['estado']);
      final firma = jsonEncode(documentos);
      await cargarDocumentos(silencioso: true);
      final ahora = docActivoMap;
      var cambio = firma != jsonEncode(documentos);
      if (enProceso && ahora != null && !estadosProcesando.contains(ahora['estado'])) {
        await cargarAnalisis(docActivo!);
        toast(ahora['estado'] == 'Error' ? 'El documento terminó con error' : 'Documento listo', err: ahora['estado'] == 'Error');
        cambio = true;
      }
      if (cambio) notifyListeners();
      final sigue = documentos.any((d) => estadosProcesando.contains(d['estado']));
      if (!sigue || DateTime.now().difference(desde).inMinutes > 40) {
        t.cancel();
        _watch = null;
      }
    });
  }

  Future<void> cargarAnalisis(String documentId) async {
    cargandoAnalisis = true;
    notifyListeners();
    try {
      final d = await api.getJson('/api/analisis-completos/${Uri.encodeComponent(documentId)}');
      if (documentId != docActivo) return;
      final a = d['analisis'];
      _rutaServidor.removeWhere((k, _) => k.startsWith('$documentId::'));
      analisis = (d['ok'] == true && a is Map && a.isNotEmpty)
          ? {for (final e in a.entries) if (e.value is Map) '${e.key}': Map<String, dynamic>.from(e.value as Map)}
          : null;
    } catch (_) {
      if (documentId == docActivo) analisis = null;
    } finally {
      cargandoAnalisis = false;
      notifyListeners();
    }
  }

  Future<bool> cambiarDocumento(String id) async {
    if (consultando) {
      toast('Espera a que termine la respuesta en curso', err: true);
      return false;
    }
    if (id == docActivo) return true;
    _guardarChat();
    docActivo = id;
    store.setString(Store.kDoc, id);
    sugerencias = [];
    analisis = null;
    borrador = '';
    prepPreguntas = [];
    prepSenales = [];
    _cargarChat(id);
    notifyListeners();
    await cargarAnalisis(id);
    return true;
  }

  // ---------------------------------------------------------------- subida
  bool subiendo = false;
  String subiendoNombre = '';
  Map<String, dynamic>? progreso;
  Timer? _polling;

  String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> subirArchivo(String nombre, Uint8List bytes) async {
    if (subiendo) {
      toast('Ya hay una subida en curso', err: true);
      return;
    }
    final ext = nombre.toLowerCase().split('.').last;
    if (!['pdf', 'docx', 'doc', 'xlsx', 'xls'].contains(ext)) {
      toast('Solo se aceptan PDF, Word o Excel', err: true);
      return;
    }
    final documentId = _uuid();
    subiendo = true;
    subiendoNombre = nombre;
    progreso = {'estado': 'Iniciando', 'fase': 'iniciando', 'procesados': 0, 'total': 0, 'estimado_seg': 0};
    notifyListeners();

    void terminar() {
      _polling?.cancel();
      _polling = null;
      subiendo = false;
      progreso = null;
    }

    _polling = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        final d = await api.getJson('/api/progreso/$documentId');
        if (d is Map && d['estado'] != null && d['estado'] != 'No encontrado') {
          progreso = Map<String, dynamic>.from(d);
          notifyListeners();
          final est = d['estado'];
          if (est == 'Listo' || est == 'Listo con errores' || est == 'Error') {
            terminar();
            if (est == 'Error') {
              toast('Error procesando el documento', err: true);
              await cargarDocumentos();
            } else {
              toast(est == 'Listo' ? 'Documento listo y analizado' : 'Documento listo, pero con errores: revisa qué agentes faltan',
                  err: est != 'Listo');
              _guardarChat();
              docActivo = documentId;
              store.setString(Store.kDoc, documentId);
              mensajes = [];
              sugerencias = [];
              _sugCache.clear();
              analisis = null;
              borrador = '';
              await cargarDocumentos(silencioso: true);
              await cargarAnalisis(documentId);
            }
            notifyListeners();
          }
        }
      } catch (_) {}
    });

    try {
      final d = await api.upload('/api/subir-informe/', {'document_id': documentId}, 'archivo', nombre, bytes);
      if (d['ok'] != true) {
        terminar();
        toast('Error al procesar: ${d['error'] ?? 'desconocido'}', err: true);
        notifyListeners();
      }
    } catch (e) {
      terminar();
      toast('Error de conexión con el backend', err: true);
      notifyListeners();
    }
  }

  Future<void> eliminarDocumento(String id) async {
    try {
      final d = await api.delete('/api/documentos/${Uri.encodeComponent(id)}');
      if (d['ok'] != true) {
        toast('Error al eliminar', err: true);
        return;
      }
      toast('Documento eliminado');
      informeItems.removeWhere((i) => i['document_id'] == id);
      _guardarInforme();
      final chats = store.getJson<Map>(Store.kChats, {});
      chats.remove(id);
      store.setJson(Store.kChats, chats);
      _sugCache.removeWhere((k, _) => k.startsWith('$id::'));
      if (docActivo == id) {
        docActivo = null;
        analisis = null;
        mensajes = [];
        sugerencias = [];
      }
      await cargarDocumentos();
    } catch (e) {
      toast('Error de conexión', err: true);
    }
  }

  // ---------------------------------------------------------------- chat
  String agenteActual = 'general';
  List<ChatMsg> mensajes = [];
  String borrador = '';
  bool consultando = false;
  List<String> sugerencias = [];
  bool cargandoSugerencias = false;
  final Map<String, List<String>> _sugCache = {};
  int _seq = 0;
  String _uid() => 'id_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';

  void _guardarChat() {
    if (docActivo == null) return;
    final todos = store.getJson<Map>(Store.kChats, {});
    final ultimos = mensajes.length > 40 ? mensajes.sublist(mensajes.length - 40) : mensajes;
    todos[docActivo!] = [for (final m in ultimos) m.toJson()];
    store.setJson(Store.kChats, todos);
  }

  void _cargarChat(String docId) {
    final todos = store.getJson<Map>(Store.kChats, {});
    final lista = todos[docId];
    mensajes = [for (final m in (lista is List ? lista : const [])) if (m is Map) ChatMsg.fromJson(m)];
  }

  void cambiarAgente(String key) {
    if (agenteActual == key) return;
    agenteActual = key;
    store.setString(Store.kAgente, key);
    sugerencias = [];
    notifyListeners();
    if (docActivo != null) {
      cargarSugerencias();
      cargarRuta();
    }
  }

  /// Desde Resultados u otra pantalla: abre el chat con un agente y una pregunta escrita.
  void preguntarEnChat(String agenteKey, String texto) {
    if (agente(agenteKey) != null || agenteKey == 'general') {
      agenteActual = agenteKey;
      store.setString(Store.kAgente, agenteKey);
    }
    borrador = texto;
    sugerencias = [];
    go('chat');
    if (docActivo != null) {
      cargarSugerencias();
      cargarRuta();
    }
  }

  // ---------------------------------------------------------------- ruta de preguntas guía (Frente A)
  /// Progreso por documento y agente: {"doc::agente": {"respondidas": [...], "saltadas": [...], "en_curso": id}}
  Map<String, Map<String, dynamic>> _ruta = {};
  final Map<String, List<Map<String, dynamic>>> _rutaServidor = {};
  bool cargandoRuta = false;

  String get _claveRuta => '$docActivo::$agenteActual';

  /// Preguntas de la ruta del agente actual, en el orden que propone el backend (las que abordan
  /// una señal grave suben). Si el backend no respondió, se usa el orden base del agente.
  List<Map<String, dynamic>> get rutaActual {
    final srv = _rutaServidor[_claveRuta];
    if (srv != null) return srv;
    return [for (final q in agente(agenteActual)?.guia ?? const <Map<String, dynamic>>[]) {...q, 'prioridad': 0}];
  }

  Set<String> _idsRuta(String campo) => {for (final x in (_ruta[_claveRuta]?[campo] as List? ?? const [])) '$x'};
  Set<String> get rutaRespondidas => _idsRuta('respondidas');
  Set<String> get rutaSaltadas => _idsRuta('saltadas');
  String? get rutaEnCurso => _ruta[_claveRuta]?['en_curso'] as String?;

  /// La siguiente pregunta solo aparece cuando la anterior ya tiene respuesta.
  Map<String, dynamic>? get siguienteDeRuta {
    if (rutaEnCurso != null) return null;
    final hechas = {...rutaRespondidas, ...rutaSaltadas};
    for (final q in rutaActual) {
      if (!hechas.contains('${q['id']}')) return q;
    }
    return null;
  }

  Future<void> cargarRuta() async {
    if (docActivo == null || agenteActual == 'general' || cargandoRuta) return;
    final clave = _claveRuta;
    if (_rutaServidor.containsKey(clave)) return;
    cargandoRuta = true;
    try {
      final d = await api.getJson('/api/ruta-preguntas/${Uri.encodeComponent(docActivo!)}/${Uri.encodeComponent(agenteActual)}');
      if (d['ok'] == true && d['preguntas'] is List) {
        _rutaServidor[clave] = [for (final q in d['preguntas'] as List) if (q is Map) Map<String, dynamic>.from(q)];
      }
    } catch (_) {}
    cargandoRuta = false;
    notifyListeners();
  }

  void _marcarRuta(String id, String campo) {
    final r = _ruta.putIfAbsent(_claveRuta, () => {'respondidas': [], 'saltadas': []});
    final lista = [for (final x in (r[campo] as List? ?? const [])) '$x'];
    if (!lista.contains(id)) lista.add(id);
    r[campo] = lista;
    if (r['en_curso'] == id) r.remove('en_curso');
    store.setJson(Store.kRuta, _ruta);
  }

  Future<void> preguntarDeRuta(Map<String, dynamic> q) async {
    final id = '${q['id']}';
    final clave = _claveRuta;
    _ruta.putIfAbsent(clave, () => {'respondidas': [], 'saltadas': []})['en_curso'] = id;
    store.setJson(Store.kRuta, _ruta);
    notifyListeners();
    await enviarPregunta('${q['pregunta']}');
    final r = _ruta[clave];
    if (r != null) {
      final lista = [for (final x in (r['respondidas'] as List? ?? const [])) '$x'];
      if (!lista.contains(id)) lista.add(id);
      r['respondidas'] = lista;
      if (r['en_curso'] == id) r.remove('en_curso');
      store.setJson(Store.kRuta, _ruta);
    }
    notifyListeners();
  }

  void saltarDeRuta(String id) {
    _marcarRuta(id, 'saltadas');
    notifyListeners();
  }

  void reiniciarRuta() {
    _ruta.remove(_claveRuta);
    store.setJson(Store.kRuta, _ruta);
    notifyListeners();
  }

  // ---------------------------------------------------------------- preparar mi reunión (Frente E1)
  List<Map<String, dynamic>> prepPreguntas = [];
  List<Map<String, dynamic>> prepSenales = [];
  bool cargandoPrep = false, generandoPrep = false;
  String? _prepDoc;

  Future<void> cargarPreparacion({bool forzar = false}) async {
    final doc = docActivo;
    if (doc == null || cargandoPrep) return;
    if (!forzar && _prepDoc == doc && prepPreguntas.isNotEmpty) return;
    cargandoPrep = true;
    notifyListeners();
    try {
      final d = await api.getJson('/api/preparar-reunion/${Uri.encodeComponent(doc)}');
      if (doc != docActivo) return;
      if (d['ok'] == true) {
        _prepDoc = doc;
        prepPreguntas = [for (final x in (d['preguntas'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
        prepSenales = [for (final x in (d['senales_clave'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
        _mezclarPrepLocal(doc);
      }
    } catch (_) {
    } finally {
      cargandoPrep = false;
      notifyListeners();
    }
  }

  /// Las respuestas sugeridas se guardan en el teléfono: el servidor gratuito se reinicia y las olvida.
  void _mezclarPrepLocal(String doc) {
    final guardadas = store.getJson<Map>(Store.kPrep, {})[doc];
    if (guardadas is! Map) return;
    for (final it in prepPreguntas) {
      if (it['sugerida'] == null && guardadas[it['id']] is Map) it['sugerida'] = Map<String, dynamic>.from(guardadas[it['id']] as Map);
    }
  }

  Future<void> generarRespuestasSugeridas() async {
    final doc = docActivo;
    if (doc == null || generandoPrep) return;
    generandoPrep = true;
    notifyListeners();
    try {
      final d = await api.postJson('/api/preparar-reunion/${Uri.encodeComponent(doc)}/respuestas', {});
      if (d['ok'] == true && doc == docActivo) {
        prepPreguntas = [for (final x in (d['preguntas'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
        _mezclarPrepLocal(doc);
        final todas = store.getJson<Map>(Store.kPrep, {});
        final propias = Map<String, dynamic>.from((todas[doc] as Map?) ?? {});
        for (final it in prepPreguntas) {
          if (it['sugerida'] is Map) propias['${it['id']}'] = it['sugerida'];
        }
        todas[doc] = propias;
        store.setJson(Store.kPrep, todas);
        toast((d['generadas'] as num? ?? 0) > 0 ? 'Respuestas sugeridas listas' : 'Ya estaban todas las respuestas');
      } else if (d['ok'] != true) {
        toast('No se pudieron generar: ${d['error'] ?? 'error'}', err: true);
      }
    } catch (e) {
      toast('No se pudieron generar las respuestas: $e', err: true);
    } finally {
      generandoPrep = false;
      notifyListeners();
    }
  }

  /// Agrega una pregunta preparada (con su respuesta sugerida) al informe del directorio.
  void prepAlInforme(Map<String, dynamic> it) {
    final id = 'prep_${it['id']}';
    if (informeItems.any((x) => x['msgId'] == id)) {
      toast('Ya está en el informe');
      return;
    }
    final sug = it['sugerida'] as Map?;
    informeItems.add({
      'tipo': 'chat', 'msgId': id, 'document_id': docActivo, 'agente': nombreAgente('${it['agente']}'),
      'agente_key': it['agente'], 'pregunta': it['pregunta'],
      'respuesta': sug?['respuesta'] ?? 'Sin respuesta sugerida todavía.', 'fuentes': const [], 'excluido': false,
      if (sug?['verificacion'] is Map) 'verificacion': sug!['verificacion'],
    });
    _guardarInforme();
    toast('Agregada al informe');
    notifyListeners();
  }

  // ---------------------------------------------------------------- valoraciones (Frente C2)
  static const motivosValoracion = {
    'cifra_incorrecta': 'Cifra incorrecta',
    'no_responde': 'No responde lo que pregunté',
    'muy_larga': 'Demasiado larga',
    'falta_contexto': 'Falta contexto',
  };

  /// Valoración que el gerente dio a cada respuesta (id del mensaje -> 1 o -1), guardada en el teléfono.
  late final Map<String, int> valoraciones = {
    for (final e in store.getJson<Map>(Store.kValoraciones, {}).entries)
      if (e.value is num) '${e.key}': (e.value as num).toInt()
  };

  Future<void> valorar(ChatMsg m, int valor, {String? motivo, String? documentId}) async {
    valoraciones[m.id] = valor;
    store.setJson(Store.kValoraciones, valoraciones);
    notifyListeners();
    try {
      final d = await api.postJson('/api/valoraciones', {
        'document_id': documentId ?? docActivo,
        'agente': m.agenteKey,
        'pregunta': m.pregunta,
        'respuesta': m.texto,
        'valor': valor,
        'motivo': ?motivo,
        'sello': m.sello,
        'mensaje_id': m.id,
      });
      if (d['ok'] == true) {
        toast(valor > 0 ? 'Gracias: la respuesta queda como buen ejemplo' : 'Gracias: se usará para mejorar al agente');
      } else {
        toast('La valoración quedó solo en este teléfono: ${d['error'] ?? ''}', err: true);
      }
    } catch (_) {
      toast('La valoración quedó solo en este teléfono (sin conexión)', err: true);
    }
  }

  // ---------------------------------------------------------------- asistente flotante (Frente E2)
  /// Pantalla que se está viendo (para las sugerencias del asistente).
  String pantalla = 'inicio';
  void setPantalla(String p) => pantalla = p;

  List<ChatMsg> asistenteMsgs = [];
  bool asistenteConsultando = false;

  /// "Preguntar al documento" desde cualquier pantalla: usa el Asistente General con verificación.
  Future<void> preguntarAsistente(String texto) async {
    final pregunta = texto.trim();
    if (pregunta.isEmpty || asistenteConsultando) return;
    if (docActivo == null) {
      toast('Selecciona un documento activo', err: true);
      return;
    }
    asistenteMsgs.add(ChatMsg(id: _uid(), rol: 'me', texto: pregunta));
    final msg = ChatMsg(id: _uid(), rol: 'ai', agente: 'Asistente General', agenteKey: 'general', streaming: true, pregunta: pregunta);
    asistenteMsgs.add(msg);
    asistenteConsultando = true;
    notifyListeners();
    try {
      final d = await api.postForm('/api/consultar/', {'pregunta': pregunta, 'document_id': docActivo!, 'agente': 'general'});
      if (d['ok'] == true) {
        msg.texto = '${d['respuesta'] ?? ''}';
        msg.fuentes = [for (final f in (d['fuentes'] as List? ?? const [])) if (f is Map) Map<String, dynamic>.from(f)];
        if (d['respuesta_original'] != null) msg.textoOriginal = '${d['respuesta_original']}';
        if (d['verificacion'] is Map) msg.verificacion = Map<String, dynamic>.from(d['verificacion'] as Map);
      } else {
        msg.error = true;
        msg.texto = 'No se pudo obtener respuesta: ${d['error'] ?? 'error desconocido'}';
      }
    } catch (e) {
      msg.error = true;
      msg.texto = 'Error de conexión con el backend.';
    }
    msg.streaming = false;
    asistenteConsultando = false;
    notifyListeners();
  }

  /// Copia una respuesta del asistente al chat principal (para seguir conversando o agregarla al informe).
  void asistenteAlChat(ChatMsg m) {
    final pregunta = m.pregunta;
    mensajes.add(ChatMsg(id: _uid(), rol: 'me', texto: pregunta));
    final copia = ChatMsg(id: _uid(), rol: 'ai', texto: m.texto, agente: m.agente, agenteKey: 'general', fuentes: m.fuentes,
        verificacion: m.verificacion, textoOriginal: m.textoOriginal, pregunta: pregunta);
    mensajes.add(copia);
    _agregarChatAlInforme(copia, pregunta);
    _guardarChat();
    toast('Copiada al chat y agregada al informe');
    notifyListeners();
  }

  List<(bool, String)> ayudaMsgs = [];
  bool ayudaBuscando = false;

  /// Ayuda de la app (POST /api/guia/preguntar).
  Future<void> preguntarAyuda(String texto) async {
    final t = texto.trim();
    if (t.isEmpty || ayudaBuscando) return;
    ayudaMsgs.add((true, t));
    ayudaBuscando = true;
    notifyListeners();
    String r;
    try {
      final d = await api.postJson('/api/guia/preguntar', {'pregunta': t, 'pantalla': pantalla});
      r = d['ok'] == true ? '${d['texto']}' : '${d['error'] ?? 'No pude responder.'}';
    } catch (_) {
      r = 'No hay conexión con el servidor.';
    }
    ayudaMsgs.add((false, r));
    ayudaBuscando = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- informe en un toque (Frente E1)
  /// Agrega todos los análisis del documento activo y descarga el PDF con los valores por defecto.
  Future<Uint8List?> informeDirecto() async {
    if (analisis == null || docActivo == null) {
      toast('El documento activo todavía no tiene análisis', err: true);
      return null;
    }
    for (final e in analisis!.entries) {
      if (!analisisEnInforme(e.key)) {
        informeItems.add({'tipo': 'analisis', 'document_id': docActivo, 'agente': nombreAgente(e.key),
          'agente_key': e.key, 'resultado': e.value, 'excluido': false});
      }
    }
    for (final i in informeItems) {
      if (i['document_id'] == docActivo) i['excluido'] = false;
    }
    _guardarInforme();
    notifyListeners();
    return descargarInformePdf();
  }

  Future<void> cargarSugerencias({bool forzar = false}) async {
    if (docActivo == null) return;
    final cacheKey = '$docActivo::$agenteActual';
    if (forzar) _sugCache.remove(cacheKey);
    if (_sugCache.containsKey(cacheKey)) {
      sugerencias = _sugCache[cacheKey]!;
      notifyListeners();
      return;
    }
    if (cargandoSugerencias) return;
    final doc = docActivo!, ag = agenteActual;
    cargandoSugerencias = true;
    notifyListeners();
    try {
      final d = await api.postForm('/api/sugerencias/', {'document_id': doc, 'agente': ag});
      if (d['ok'] == true) {
        final s = [for (final x in (d['sugerencias'] as List? ?? const [])) '$x'];
        _sugCache['$doc::$ag'] = s;
        if (doc == docActivo && ag == agenteActual) sugerencias = s;
      }
    } catch (_) {}
    cargandoSugerencias = false;
    notifyListeners();
  }

  void nuevaConversacion() {
    mensajes = [];
    _guardarChat();
    notifyListeners();
  }

  String _historial() {
    final turnos = <Map<String, String>>[];
    for (var i = 0; i < mensajes.length - 1; i++) {
      final a = mensajes[i], b = mensajes[i + 1];
      if (a.rol == 'me' && b.rol == 'ai' && !b.streaming && !b.error && b.texto.isNotEmpty) {
        turnos.add({'pregunta': a.texto, 'respuesta': b.texto});
      }
    }
    return jsonEncode(turnos.length > 4 ? turnos.sublist(turnos.length - 4) : turnos);
  }

  Future<void> enviarPregunta(String texto) async {
    final pregunta = texto.trim();
    if (pregunta.isEmpty || consultando) return;
    if (docActivo == null) {
      toast('Selecciona un documento activo', err: true);
      return;
    }
    final historial = _historial();
    final docDeLaPregunta = docActivo!;
    mensajes.add(ChatMsg(id: _uid(), rol: 'me', texto: pregunta));
    final msg = ChatMsg(
      id: _uid(),
      rol: 'ai',
      agente: agenteActual == 'general' ? 'Asistente General' : nombreAgente(agenteActual),
      agenteKey: agenteActual,
      streaming: true,
      pregunta: pregunta,
    );
    mensajes.add(msg);
    consultando = true;
    borrador = '';
    notifyListeners();

    final campos = {'pregunta': pregunta, 'document_id': docDeLaPregunta, 'agente': agenteActual, 'historial': historial};
    var acumulado = '', errorServidor = '';
    try {
      await for (final p in api.sse('/api/consultar-stream/', campos)) {
        if (p['error'] != null) errorServidor = '${p['error']}';
        if (p['chunk'] != null) {
          acumulado += '${p['chunk']}';
          msg.texto = acumulado;
          notifyListeners();
        }
        if (p['fuentes'] is List) {
          msg.fuentes = [for (final f in p['fuentes'] as List) if (f is Map) Map<String, dynamic>.from(f)];
        }
        if (p['agente'] != null) msg.agente = '${p['agente']}';
        if (p['verificando'] == true) {
          // La respuesta ya está completa: se puede leer (y seguir preguntando) mientras llega el sello.
          msg.streaming = false;
          msg.verificando = true;
          if (identical(_consultaActiva, msg)) consultando = false;
          notifyListeners();
        }
        if (p['verificacion'] is Map) _aplicarVerificacion(msg, Map<String, dynamic>.from(p['verificacion'] as Map));
      }
      if (acumulado.isEmpty) {
        msg.error = true;
        msg.texto = errorServidor.isNotEmpty
            ? 'No se pudo obtener respuesta: $errorServidor'
            : 'El agente no devolvió texto. Intenta de nuevo.';
      }
    } catch (_) {
      // Respaldo sin streaming, igual que el MVP.
      if (acumulado.isEmpty) {
        try {
          final d = await api.postForm('/api/consultar/', campos);
          if (d['ok'] == true) {
            msg.texto = '${d['respuesta'] ?? ''}';
            msg.fuentes = [for (final f in (d['fuentes'] as List? ?? const [])) if (f is Map) Map<String, dynamic>.from(f)];
            if (d['verificacion'] is Map) _aplicarVerificacion(msg, Map<String, dynamic>.from(d['verificacion'] as Map));
            if (d['respuesta_original'] != null) msg.textoOriginal = '${d['respuesta_original']}';
          } else {
            msg.error = true;
            msg.texto = 'No se pudo obtener respuesta: ${d['error'] ?? 'error desconocido'}';
          }
        } catch (e) {
          if (msg.texto.isEmpty) {
            msg.error = true;
            msg.texto = 'Error de conexión con el backend.';
          }
        }
      }
    }
    msg.streaming = false;
    msg.verificando = false;
    if (identical(_consultaActiva, msg) || _consultaActiva == null) consultando = false;
    if (!msg.error) _agregarChatAlInforme(msg, pregunta, docId: docDeLaPregunta);
    _guardarChatDe(docDeLaPregunta, msg);
    notifyListeners();
  }

  ChatMsg? get _consultaActiva {
    for (var i = mensajes.length - 1; i >= 0; i--) {
      if (mensajes[i].rol == 'ai') return mensajes[i];
    }
    return null;
  }

  void _aplicarVerificacion(ChatMsg msg, Map<String, dynamic> v) {
    msg.verificacion = v;
    msg.verificando = false;
    final corregida = v['respuesta_corregida'];
    if (corregida is String && corregida.trim().isNotEmpty && corregida != msg.texto) {
      msg.textoOriginal = msg.texto;
      msg.texto = corregida;
    }
    // Si la respuesta ya estaba en el informe, se actualiza con el texto y el sello verificados.
    for (final it in informeItems) {
      if (it['tipo'] == 'chat' && it['msgId'] == msg.id) {
        it['respuesta'] = msg.texto;
        it['verificacion'] = _selloParaInforme(v);
      }
    }
    _guardarInforme();
    notifyListeners();
  }

  Map<String, dynamic> _selloParaInforme(Map v) => {'estado': v['estado'], 'etiqueta': v['etiqueta'], 'resumen': v['resumen']};

  /// Guarda el chat del documento donde se hizo la pregunta, aunque el usuario ya haya cambiado de documento.
  void _guardarChatDe(String docId, ChatMsg msg) {
    if (docId == docActivo) {
      _guardarChat();
      return;
    }
    final todos = store.getJson<Map>(Store.kChats, {});
    final lista = [for (final m in (todos[docId] is List ? todos[docId] as List : const [])) if (m is Map) ChatMsg.fromJson(m)];
    final i = lista.indexWhere((m) => m.id == msg.id);
    if (i >= 0) lista[i] = msg;
    todos[docId] = [for (final m in lista) m.toJson()];
    store.setJson(Store.kChats, todos);
  }

  /// Verifica una respuesta antigua (de antes del verificador) — POST /api/verificar/.
  final Set<String> verificandoIds = {};
  Future<void> verificarMensaje(String msgId) async {
    final msg = mensajes.where((m) => m.id == msgId).firstOrNull;
    if (msg == null || docActivo == null || verificandoIds.contains(msgId)) return;
    var pregunta = msg.pregunta;
    if (pregunta.isEmpty) {
      final i = mensajes.indexOf(msg);
      for (var j = i - 1; j >= 0; j--) {
        if (mensajes[j].rol == 'me') {
          pregunta = mensajes[j].texto;
          break;
        }
      }
    }
    verificandoIds.add(msgId);
    msg.verificando = true;
    notifyListeners();
    try {
      final d = await api.postForm('/api/verificar/', {'document_id': docActivo!, 'pregunta': pregunta, 'respuesta': msg.texto});
      if (d['ok'] == true && d['verificacion'] is Map) {
        _aplicarVerificacion(msg, Map<String, dynamic>.from(d['verificacion'] as Map));
      } else {
        toast('No se pudo verificar: ${d['error'] ?? 'error desconocido'}', err: true);
      }
    } catch (e) {
      toast('No se pudo verificar: $e', err: true);
    }
    verificandoIds.remove(msgId);
    msg.verificando = false;
    _guardarChat();
    notifyListeners();
  }

  // ---------------------------------------------------------------- verificación de las señales del análisis
  bool verificandoAnalisis = false;
  String progresoVerificacion = '';

  /// ¿Hay señales altas o críticas que todavía no pasaron por el verificador?
  bool get senalesSinVerificar {
    for (final r in (analisis ?? const {}).values) {
      for (final sg in listaDe(r, 'senales')) {
        final sev = normSev(sg['severidad']);
        if ((sev == 'crítica' || sev == 'alta') && sg['verificacion'] == null) return true;
      }
    }
    return false;
  }

  Future<void> verificarAnalisis() async {
    final doc = docActivo;
    if (doc == null || verificandoAnalisis) return;
    verificandoAnalisis = true;
    progresoVerificacion = 'Iniciando…';
    notifyListeners();
    try {
      final d = await api.postForm('/api/verificar-analisis/${Uri.encodeComponent(doc)}', {});
      if (d['ok'] != true) throw ApiError('${d['error'] ?? 'no se pudo iniciar'}');
      final jobId = '${d['job_id']}';
      for (var i = 0; i < 200; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final e = await api.getJson('/api/verificar-analisis-estado/$jobId');
        progresoVerificacion = 'Ola ${e['procesadas'] ?? 0} de ${e['total'] ?? '?'}';
        notifyListeners();
        if (e['corriendo'] != true) {
          final n = (e['revisadas'] as num?)?.toInt() ?? 0;
          final malas = ((e['contradichas'] as num?)?.toInt() ?? 0) + ((e['no_respaldadas'] as num?)?.toInt() ?? 0);
          toast(n == 0 ? 'No había señales graves que verificar' : '$n señales revisadas · $malas sin respaldo o contradichas',
              err: (e['errores'] as List? ?? const []).isNotEmpty);
          break;
        }
      }
      if (doc == docActivo) await cargarAnalisis(doc);
    } catch (e) {
      toast('No se pudo verificar el análisis: $e', err: true);
    } finally {
      verificandoAnalisis = false;
      progresoVerificacion = '';
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- informe
  List<Map<String, dynamic>> informeItems = [];
  bool generandoPdf = false;

  List<Map<String, dynamic>> get itemsInforme => informeItems.where((i) => i['document_id'] == docActivo).toList();

  void _guardarInforme() => store.setJson(Store.kInforme, informeItems);

  bool chatEnInforme(String msgId) => informeItems.any((i) => i['tipo'] == 'chat' && i['msgId'] == msgId);
  bool analisisEnInforme(String k) =>
      informeItems.any((i) => i['tipo'] == 'analisis' && i['agente_key'] == k && i['document_id'] == docActivo);

  void _agregarChatAlInforme(ChatMsg msg, String pregunta, {String? docId}) {
    if (msg.texto.isEmpty || msg.error || chatEnInforme(msg.id)) return;
    informeItems.add({
      'tipo': 'chat', 'msgId': msg.id, 'document_id': docId ?? docActivo, 'agente': msg.agente, 'agente_key': msg.agenteKey,
      'pregunta': pregunta, 'respuesta': msg.texto, 'fuentes': msg.fuentes, 'excluido': false,
      if (msg.verificacion != null) 'verificacion': _selloParaInforme(msg.verificacion!),
    });
    _guardarInforme();
  }

  void toggleChatEnInforme(String msgId) {
    final i = informeItems.indexWhere((x) => x['tipo'] == 'chat' && x['msgId'] == msgId);
    if (i >= 0) {
      informeItems.removeAt(i);
    } else {
      final idx = mensajes.indexWhere((m) => m.id == msgId);
      if (idx < 0) return;
      var pregunta = '';
      for (var j = idx - 1; j >= 0; j--) {
        if (mensajes[j].rol == 'me') {
          pregunta = mensajes[j].texto;
          break;
        }
      }
      _agregarChatAlInforme(mensajes[idx], pregunta);
    }
    _guardarInforme();
    notifyListeners();
  }

  void toggleAnalisisEnInforme(String k) {
    final i = informeItems.indexWhere((x) => x['tipo'] == 'analisis' && x['agente_key'] == k && x['document_id'] == docActivo);
    if (i >= 0) {
      informeItems.removeAt(i);
    } else if (analisis?[k] != null) {
      informeItems.add({'tipo': 'analisis', 'document_id': docActivo, 'agente': nombreAgente(k), 'agente_key': k,
        'resultado': analisis![k], 'excluido': false});
    }
    _guardarInforme();
    notifyListeners();
  }

  void agregarTodoAlInforme() {
    if (analisis == null || docActivo == null) {
      toast('No hay análisis para agregar', err: true);
      return;
    }
    var n = 0;
    for (final e in analisis!.entries) {
      if (!analisisEnInforme(e.key)) {
        informeItems.add({'tipo': 'analisis', 'document_id': docActivo, 'agente': nombreAgente(e.key),
          'agente_key': e.key, 'resultado': e.value, 'excluido': false});
        n++;
      }
    }
    _guardarInforme();
    toast(n > 0 ? '$n análisis agregados al informe' : 'Ya estaban todos en el informe');
    notifyListeners();
  }

  void toggleExcluir(Map<String, dynamic> item) {
    item['excluido'] = item['excluido'] != true;
    _guardarInforme();
    notifyListeners();
  }

  void setTodosExcluidos(bool v) {
    for (final i in informeItems) {
      if (i['document_id'] == docActivo) i['excluido'] = v;
    }
    _guardarInforme();
    notifyListeners();
  }

  void limpiarInforme() {
    informeItems.removeWhere((i) => i['document_id'] == docActivo);
    _guardarInforme();
    notifyListeners();
  }

  /// POST /api/informe/ — devuelve los bytes del PDF.
  Future<Uint8List?> descargarInformePdf() async {
    final activos = itemsInforme.where((i) => i['excluido'] != true).toList();
    if (activos.isEmpty) {
      toast('No hay ítems seleccionados', err: true);
      return null;
    }
    generandoPdf = true;
    notifyListeners();
    final doc = docActivoMap;
    final payload = {
      'documento': {'nombre': nombreDoc(doc).isEmpty ? 'Documento' : nombreDoc(doc), 'paginas': doc?['total_paginas'] ?? '?'},
      'items': [
        for (final it in activos)
          it['tipo'] == 'chat'
              ? {'tipo': 'chat', 'agente': it['agente'], 'agente_key': it['agente_key'], 'pregunta': it['pregunta'],
                  'respuesta': it['respuesta'], 'fuentes': it['fuentes'], 'verificacion': it['verificacion']}
              : {'tipo': 'analisis', 'agente': it['agente'], 'agente_key': it['agente_key'], 'resultado': it['resultado']}
      ],
    };
    try {
      return await api.download('/api/informe/', form: {'document_id': docActivo ?? '', 'payload': jsonEncode(payload)});
    } catch (e) {
      toast('Error generando el informe: $e', err: true);
      return null;
    } finally {
      generandoPdf = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- resultados (cálculos del index.html)
  Map<String, int> conteoSeveridad(Map<String, Map<String, dynamic>> res) {
    final c = {for (final s in severidades) s: 0};
    for (final r in res.values) {
      for (final s in listaDe(r, 'senales')) {
        c[normSev(s['severidad'])] = c[normSev(s['severidad'])]! + 1;
      }
    }
    return c;
  }

  ({int score, int n, int sinInfo}) scoreGlobal(Map<String, Map<String, dynamic>> res) {
    final conInfo = res.values.where(tieneInfo).toList();
    if (conInfo.isEmpty) return (score: 0, n: 0, sinInfo: res.length);
    final media = (conInfo.fold<int>(0, (a, r) => a + scoreDe(r)) / conInfo.length).round();
    return (score: media, n: conInfo.length, sinInfo: res.length - conInfo.length);
  }

  @override
  void dispose() {
    _watch?.cancel();
    _polling?.cancel();
    _toasts.close();
    _nav.close();
    super.dispose();
  }
}
