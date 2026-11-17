import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/demo_offline.dart';

const _kMarca = 'directa_marca_memoria_v1';
const _coloresMarca = ['#1B2F4B', '#0E5A8A', '#0E7490', '#12AFC6', '#237AA8', '#4664A8'];

Color _hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

/// "Borrador de memoria" en un paso (Frente D): se elige el año y se obtiene el PDF para revisar.
class BorradorMemoria extends StatefulWidget {
  const BorradorMemoria({super.key, required this.caps});
  final Map<String, dynamic> Function() caps;
  @override
  State<BorradorMemoria> createState() => _BorradorMemoriaState();
}

class _BorradorMemoriaState extends State<BorradorMemoria> {
  List<Map<String, dynamic>> anios = [];
  int? anio;
  bool cargando = true, generando = false;
  String? error, logo;
  String color = _coloresMarca.first;
  final _nombre = TextEditingController();
  final _titulo = TextEditingController(text: 'Memoria anual');
  final _destinatario = TextEditingController(text: 'Gerencia General');
  final _firmante = TextEditingController(text: 'Gerente General');
  Map<String, dynamic>? progreso, resultado;
  Timer? _poll;

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    final m = st.store.getJson<Map>(_kMarca, {});
    _nombre.text = '${m['nombre'] ?? ''}';
    _titulo.text = '${m['titulo'] ?? 'Memoria anual'}';
    _destinatario.text = '${m['destinatario'] ?? 'Gerencia General'}';
    _firmante.text = '${m['firmante'] ?? 'Gerente General'}';
    if (_coloresMarca.contains(m['color'])) color = '${m['color']}';
    logo = m['logo'] as String?;
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _nombre.dispose();
    _titulo.dispose();
    _destinatario.dispose();
    _firmante.dispose();
    super.dispose();
  }

  void _guardarMarca() => st.store.setJson(_kMarca, {
    'nombre': _nombre.text.trim(), 'titulo': _titulo.text.trim(),
    'destinatario': _destinatario.text.trim(), 'firmante': _firmante.text.trim(),
    'color': color, if (logo != null) 'logo': logo,
  });

  Future<void> _cargar() async {
    try {
      final r = await st.api.getJson('/api/memoria/anios', timeout: const Duration(seconds: 6));
      anios = [for (final a in (r['anios'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
      if (anios.isEmpty) {
        anio = null;
      } else if (anio == null || !anios.any((a) => (a['anio'] as num?)?.toInt() == anio)) {
        anio = (anios.first['anio'] as num).toInt();
      }
      error = null;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => cargando = false);
  }

  Future<void> _elegirLogo() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg']);
    if (f == null) return;
    final bytes = await f.xFile.readAsBytes();
    if (bytes.length > 1500000) {
      st.toast('El logo debe pesar menos de 1,5 MB', err: true);
      return;
    }
    final tipo = f.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
    setState(() => logo = 'data:image/$tipo;base64,${base64Encode(bytes)}');
    _guardarMarca();
  }

  Future<void> _generar() async {
    if (anio == null || generando) return;
    _guardarMarca();
    setState(() {
      generando = true;
      progreso = {'paso': 'Iniciando…', 'hechos': 0, 'total': 1};
      resultado = null;
      error = null;
    });
    try {
      final propios = st.store.getJson<List>(Store.kIndPropios, const []);
      final r = await st.api.postJson('/api/memoria/borrador', {
        'anio': anio,
        'marca': {'nombre': _nombre.text.trim(), 'titulo': _titulo.text.trim(),
          'destinatario': _destinatario.text.trim(), 'firmante': _firmante.text.trim(),
          'color': color, if (logo != null) 'logo': logo},
        'caps': widget.caps(),
        'propios': propios,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo iniciar');
      final id = '${r['job_id']}';
      final listo = Completer<Map<String, dynamic>>();
      _poll = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
        try {
          final e = Map<String, dynamic>.from(await st.api.getJson('/api/memoria/borrador/$id') as Map);
          if (!mounted) return;
          setState(() => progreso = e);
          if (e['corriendo'] != true && !listo.isCompleted) {
            t.cancel();
            listo.complete(e);
          }
        } catch (err) {
          if (!listo.isCompleted) {
            t.cancel();
            listo.completeError(err);
          }
        }
      });
      final e = await listo.future;
      if (e['listo'] != true) throw Exception(e['error'] ?? 'El borrador no se pudo generar');
      final bytes = await st.api.getBytes('/api/memoria/borrador/$id/pdf');
      resultado = e;
      st.toast(await guardarArchivo('${e['nombre'] ?? 'Memoria_borrador.pdf'}', bytes, 'application/pdf'));
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => generando = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final anioPortada = anio ?? DateTime.now().year;
    final docsAnio = [for (final g in anios) if ((g['anio'] as num?)?.toInt() == anio) ...(g['documentos'] as List? ?? const [])];
    final caps = widget.caps();
    final terminados = caps.values.where((v) => v is Map && ['listo', 'completo', 'hecho'].contains('${v['estado']}'.toLowerCase())).length;
    final totalCaps = caps.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: SecTitle('Datos de la memoria')),
          if (cargando) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          if (!cargando && error != null) IconButton(tooltip: 'Reintentar conexión', onPressed: _cargar, icon: Icon(Icons.refresh, color: c.accentText)),
        ]),
        Text('Completa los datos editoriales. La empresa, el título y el destinatario se muestran en lugares distintos del libro.', style: TextStyle(color: c.text2, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 14),
        TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Empresa u organización', prefixIcon: Icon(Icons.business_outlined)), onChanged: (_) { _guardarMarca(); setState(() {}); }),
        const SizedBox(height: 10),
        TextField(controller: _titulo, decoration: const InputDecoration(labelText: 'Título de portada', prefixIcon: Icon(Icons.title)), onChanged: (_) { _guardarMarca(); setState(() {}); }),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) => Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(width: box.maxWidth > 520 ? (box.maxWidth - 10) / 2 : box.maxWidth, child: DropdownButtonFormField<int>(
            value: anios.isEmpty ? anioPortada : anio,
            decoration: const InputDecoration(labelText: 'Año del informe', prefixIcon: Icon(Icons.calendar_today_outlined)),
            items: (anios.isEmpty ? [anioPortada] : anios.map((x) => (x['anio'] as num).toInt()).toList()).map((a) => DropdownMenuItem(value: a, child: Text('$a'))).toList(),
            onChanged: anios.isEmpty ? null : (v) => setState(() => anio = v),
          )),
          SizedBox(width: box.maxWidth > 520 ? (box.maxWidth - 10) / 2 : box.maxWidth, child: TextField(controller: _destinatario, decoration: const InputDecoration(labelText: 'Preparada para', prefixIcon: Icon(Icons.person_outline)), onChanged: (_) { _guardarMarca(); setState(() {}); })),
        ])),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 16, color: c.text3),
          const SizedBox(width: 7),
          Expanded(child: Text(
            anios.isEmpty
                ? 'El año se habilita cuando hay documentos procesados con un período identificable.'
                : anios.length == 1
                    ? 'Solo hay documentos procesados de ${anios.first['anio']}. Para usar otro año, agrega documentos de ese período.'
                    : 'El año filtra los documentos que se usarán en el PDF. El documento activo de la barra superior no cambia.',
            style: TextStyle(color: c.text3, fontSize: 11.5, height: 1.35),
          )),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _firmante, decoration: const InputDecoration(labelText: 'Nombre o cargo de quien firma', prefixIcon: Icon(Icons.draw_outlined)), onChanged: (_) => _guardarMarca()),
        if (error != null || anios.isEmpty) ...[
          const SizedBox(height: 12),
          Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(error == null ? Icons.info_outline : Icons.cloud_off_outlined, color: c.accentText, size: 19), const SizedBox(width: 8),
            Expanded(child: Text(error == null ? 'Aún no hay documentos procesados con un año identificable. Puedes preparar los datos y revisar la portada; la generación se activa cuando haya documentos.' : 'No hay conexión con el servidor. Tus datos de portada se guardan en este dispositivo y puedes seguir editándolos.', style: TextStyle(color: c.text2, fontSize: 12.5, height: 1.35))),
          ])),
        ],
      ])),
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Portada y estilo editorial'),
        Container(height: 225, width: double.infinity, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: _hex(color), borderRadius: BorderRadius.circular(10)), child: Row(children: [
          Expanded(flex: 5, child: Padding(padding: const EdgeInsets.fromLTRB(18, 18, 12, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (logo != null) Image.memory(base64Decode(logo!.split(',').last), width: 48, height: 28, fit: BoxFit.contain) else const SizedBox(height: 8),
            Text(_nombre.text.trim().isEmpty ? 'NOMBRE DE LA ORGANIZACIÓN' : _nombre.text.trim().toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .6)),
            const SizedBox(height: 20), Container(width: 36, height: 3, color: Brand.accent), const SizedBox(height: 14),
            Text(_titulo.text.trim().isEmpty ? 'Memoria anual' : _titulo.text.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontFamily: 'serif', fontSize: 22, height: 1.12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8), Text('$anioPortada', style: TextStyle(color: c.accentText, fontSize: 16, fontWeight: FontWeight.w600)), const Spacer(),
            Text('Preparada para ${_destinatario.text.trim().isEmpty ? '—' : _destinatario.text.trim()}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ]))),
          Expanded(flex: 4, child: Image.asset('assets/memoria_portada.jpg', fit: BoxFit.cover, height: double.infinity, width: double.infinity)),
        ])),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final h in _coloresMarca) InkWell(onTap: () { setState(() => color = h); _guardarMarca(); }, child: Container(width: 30, height: 30, decoration: BoxDecoration(color: _hex(h), shape: BoxShape.circle, border: Border.all(color: color == h ? c.text : c.border2, width: color == h ? 2.5 : 1)))),
          GgButton(logo == null ? 'Agregar logo' : 'Cambiar logo', icon: Icons.image_outlined, ghost: true, small: true, onTap: _elegirLogo),
          if (logo != null) TextButton(onPressed: () { setState(() => logo = null); _guardarMarca(); }, child: const Text('Quitar logo')),
        ]),
      ])),
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Revisión antes de generar'),
        Row(children: [Icon(Icons.menu_book_outlined, color: c.accentText), const SizedBox(width: 8), Expanded(child: Text('Memoria anual $anioPortada', style: const TextStyle(fontWeight: FontWeight.w700))), Pill(anios.isEmpty ? 'SIN DOCUMENTOS' : '${docsAnio.length} DOCUMENTOS', fg: anios.isEmpty ? c.med : c.low)]),
        const SizedBox(height: 10),
        if (totalCaps > 0) Text('$terminados de $totalCaps capítulos marcados como listos en tus notas.', style: TextStyle(color: c.text2, fontSize: 12.5)),
        if (totalCaps > 0) ...[const SizedBox(height: 7), GgBar(value: terminados / totalCaps)],
        const SizedBox(height: 8),
        Text(anios.isEmpty ? 'Agrega documentos procesados para revisar evidencia y habilitar el PDF.' : 'Documentos incluidos: ${docsAnio.map((d) => d['nombre']).join(', ')}', style: TextStyle(color: c.text3, fontSize: 12, height: 1.35)),
        const SizedBox(height: 14),
        GgButton(generando ? 'Generando memoria…' : 'Generar borrador PDF', icon: Icons.picture_as_pdf_outlined, expand: true, loading: generando, onTap: anio == null || anios.isEmpty ? null : _generar),
        const SizedBox(height: 8),
        Text('El PDF incluye portada, índice, carta, capítulos, indicadores, gráficos, cobertura normativa y revisión de cifras. Revisa y valida el contenido antes de distribuirlo.', style: TextStyle(fontSize: 11.5, color: c.text3, height: 1.35)),
      ])),
      if (generando && progreso != null) GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${progreso!['paso'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 8), GgBar(value: ((progreso!['hechos'] as num?)?.toDouble() ?? 0) / max(1, (progreso!['total'] as num?)?.toDouble() ?? 1)), const SizedBox(height: 4), Text('${progreso!['hechos'] ?? 0} de ${progreso!['total'] ?? 1} pasos', style: TextStyle(fontSize: 11.5, color: c.text3))])),
      if (error != null && !cargando) GgCard(borderColor: c.crit, child: Text(error!, style: TextStyle(color: c.crit))),
      if (resultado != null) GgCard(borderColor: c.low, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.check_circle_outline, color: c.low), const SizedBox(width: 8), const Expanded(child: Text('Borrador PDF listo', style: TextStyle(fontWeight: FontWeight.w700)))]),
        const SizedBox(height: 6), Text('Memoria_Anual_${anioPortada}_borrador.pdf · ${(resultado!['revision'] as List? ?? const []).length} alertas de cifras. Revisa el archivo antes de aprobarlo.', style: TextStyle(fontSize: 12.5, color: c.text2)),
      ])),
    ]);
  }
}

/// Perfil de tono (Frente D1): el Redactor lo extrae de memorias anteriores; el gerente lo corrige y aprueba.
class PerfilTono extends StatefulWidget {
  const PerfilTono({super.key});
  @override
  State<PerfilTono> createState() => _PerfilTonoState();
}

class _PerfilTonoState extends State<PerfilTono> {
  static const _textos = [
    ('persona', 'Persona y a quién se dirige'),
    ('formalidad', 'Formalidad'),
    ('largo_capitulos', 'Largo típico'),
    ('cifras', 'Cómo presenta las cifras'),
    ('cierres', 'Cómo cierra las secciones'),
  ];
  static const _listas = [
    ('vocabulario_frecuente', 'Vocabulario típico (separado por comas)'),
    ('vocabulario_evitar', 'Vocabulario a evitar (separado por comas)'),
    ('rasgos', 'Otros rasgos (separados por comas)'),
  ];
  Map<String, dynamic>? perfil;
  int minimo = 3;
  bool cargando = true, trabajando = false;
  final Set<String> seleccion = {};
  final Map<String, TextEditingController> ctrl = {};
  String? error;

  AppState get st => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    for (final (k, _) in [..._textos, ..._listas]) {
      ctrl[k] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void dispose() {
    for (final c in ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _llenar() {
    final p = (perfil?['perfil'] as Map?) ?? {};
    for (final (k, _) in _textos) {
      ctrl[k]!.text = '${p[k] ?? ''}';
    }
    for (final (k, _) in _listas) {
      ctrl[k]!.text = [for (final x in (p[k] as List? ?? const [])) '$x'].join(', ');
    }
  }

  Future<void> _cargar() async {
    try {
      final r = await st.api.getJson('/api/memoria/perfil-tono', timeout: const Duration(seconds: 6));
      if (r['ok'] != true) throw Exception(r['error']);
      perfil = r['perfil'] is Map ? Map<String, dynamic>.from(r['perfil'] as Map) : null;
      minimo = (r['minimo_memorias'] as num?)?.toInt() ?? 3;
      _llenar();
      error = null;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => cargando = false);
  }

  Map<String, dynamic> _editado() => {
        for (final (k, _) in _textos) k: ctrl[k]!.text.trim(),
        for (final (k, _) in _listas) k: [for (final x in ctrl[k]!.text.split(',')) if (x.trim().isNotEmpty) x.trim()],
      };

  Future<void> _accion(Future<dynamic> Function() f, String ok) async {
    setState(() => trabajando = true);
    try {
      final r = await f();
      if (r['ok'] != true) throw Exception(r['error'] ?? 'error');
      perfil = Map<String, dynamic>.from(r['perfil'] as Map);
      _llenar();
      st.toast(ok);
    } catch (e) {
      st.toast(e.toString().replaceFirst('Exception: ', ''), err: true);
    }
    if (mounted) setState(() => trabajando = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final app = context.watch<AppState>();
    if (cargando) return const GgCard(child: EmptyState(icon: Icons.hourglass_empty, title: 'Cargando…', loading: true));
    final docs = app.documentos.where((d) => !estadosProcesando.contains(d['estado'])).toList();
    final corpus = [for (final x in (perfil?['corpus'] as List? ?? const [])) if (x is Map) x];
    final medidas = (perfil?['medidas'] as Map?) ?? {};
    final aprobado = perfil?['estado'] == 'aprobado';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (perfil == null && docs.isEmpty) const DemoAviso(text: 'Ejemplo del perfil editorial. Para extraer un tono real necesitas memorias anteriores cargadas y conexión al servidor.'),
      if (perfil == null && docs.isEmpty) const GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SecTitle('Ejemplo de tono corporativo'),
        DemoFila(titulo: 'Formalidad', detalle: 'Profesional, directa y orientada a decisiones.'),
        DemoFila(titulo: 'Estilo', detalle: 'Frases claras, cifras acompañadas de contexto y próximos pasos explícitos.'),
        DemoFila(titulo: 'Regla editorial', detalle: 'Distinguir hechos, proyecciones y asuntos pendientes de validación.'),
      ])),
      if (error != null) GgCard(borderColor: c.crit, child: Text(error!, style: TextStyle(color: c.crit))),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Memorias anteriores para aprender el tono'),
          Text('Elige al menos $minimo memorias de años anteriores ya subidas. El Redactor describe su estilo sin copiar frases ni cifras.',
              style: TextStyle(fontSize: 12.5, color: c.text2)),
          const SizedBox(height: 8),
          for (final d in docs)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: seleccion.contains('${d['id']}'),
              onChanged: (v) => setState(() => v == true ? seleccion.add('${d['id']}') : seleccion.remove('${d['id']}')),
              title: Text(nombreDoc(d), style: const TextStyle(fontSize: 13)),
            ),
          const SizedBox(height: 8),
          GgButton(perfil == null ? 'Extraer perfil de tono' : 'Volver a extraer con estas memorias', icon: Icons.auto_awesome,
              loading: trabajando, onTap: seleccion.isEmpty ? null : () => _accion(
                  () => st.api.postJson('/api/memoria/perfil-tono/extraer', {'documentos': seleccion.toList()}),
                  'Perfil extraído: revísalo y apruébalo')),
        ]),
      ),
      if (perfil != null)
        GgCard(
          borderColor: aprobado ? c.low : c.med,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Perfil de tono v${perfil!['version']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              Pill(aprobado ? 'APROBADO' : 'BORRADOR', fg: aprobado ? c.low : c.med),
            ]),
            const SizedBox(height: 4),
            Text('Corpus: ${corpus.map((x) => '${x['nombre']}${x['anio'] != null ? ' (${x['anio']})' : ''}').join(', ')}',
                style: TextStyle(fontSize: 12, color: c.text3)),
            if ('${perfil!['aviso'] ?? ''}'.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('${perfil!['aviso']}', style: TextStyle(fontSize: 12, color: c.med))),
            const SizedBox(height: 12),
            KpiStrip(items: [
              (valor: '${medidas['palabras_por_oracion'] ?? '-'}', etiqueta: 'Palabras por oración', color: null, onTap: null),
              (valor: '${medidas['primera_persona_pct'] ?? '-'}%', etiqueta: 'Primera persona', color: null, onTap: null),
              (valor: '${medidas['tercera_persona_pct'] ?? '-'}%', etiqueta: '«La Compañía»', color: null, onTap: null),
            ]),
            for (final (k, l) in _textos) ...[
              TextField(controller: ctrl[k], minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: l)),
              const SizedBox(height: 12),
            ],
            for (final (k, l) in _listas) ...[
              TextField(controller: ctrl[k], minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: l)),
              const SizedBox(height: 12),
            ],
            if ((medidas['terminos_frecuentes'] as List? ?? const []).isNotEmpty)
              Text('Términos más frecuentes (medidos): ${(medidas['terminos_frecuentes'] as List).take(10).join(', ')}',
                  style: TextStyle(fontSize: 11.5, color: c.text3)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              GgButton('Guardar cambios', icon: Icons.save_outlined, ghost: true, small: true, loading: trabajando,
                  onTap: () => _accion(() => st.api.putJson('/api/memoria/perfil-tono/${perfil!['id']}', {'perfil': _editado()}),
                      'Cambios guardados')),
              GgButton(aprobado ? 'Aprobado' : 'Aprobar perfil', icon: Icons.verified_outlined, small: true, loading: trabajando,
                  onTap: aprobado ? null : () => _accion(
                      () => st.api.putJson('/api/memoria/perfil-tono/${perfil!['id']}', {'perfil': _editado(), 'aprobar': true}),
                      'Perfil aprobado: los borradores lo usarán')),
            ]),
            const SizedBox(height: 16),
            const SecTitle('Sumar una memoria aprobada al corpus'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in docs.where((d) => !corpus.any((x) => x['document_id'] == d['id'])))
                ChipBtn(nombreDoc(d), on: false, maxWidth: 260, onTap: () => _accion(
                    () => st.api.postJson('/api/memoria/perfil-tono/corpus', {'document_id': d['id']}),
                    'Memoria sumada: el perfil nuevo queda en borrador para aprobar')),
            ]),
          ]),
        ),
    ]);
  }
}
