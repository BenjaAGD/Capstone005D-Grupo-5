import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/asistente.dart';
import '../widgets/common.dart';

/// Lector del texto extraído del documento, página por página.
///
/// Usa los endpoints de lectura.py: la lista real de páginas (contador "41 de 157"), el texto de cada
/// página ya ordenado y sin texto repetido, y la búsqueda dentro del documento.
class DocumentoLecturaScreen extends StatefulWidget {
  const DocumentoLecturaScreen({
    super.key,
    required this.documentId,
    this.nombreArchivo = '',
  });

  final String documentId;
  final String nombreArchivo;

  @override
  State<DocumentoLecturaScreen> createState() => _DocumentoLecturaScreenState();
}

class _DocumentoLecturaScreenState extends State<DocumentoLecturaScreen> {
  static const _escalas = [0.9, 1.0, 1.15, 1.3];

  Map<String, dynamic>? _documento;
  List<int> _paginas = [];
  int _indice = 0;
  final Map<int, String> _textos = {};
  bool _cargando = true;
  bool _cargandoPagina = false;
  String? _error;
  int _escala = 1;
  int _tema = 0; // 0 papel · 1 sepia · 2 noche
  final _scroll = ScrollController();

  // Colores de lectura tipo libro electrónico: (fondo de la hoja, tinta, tinta suave, fondo alrededor).
  static const _temas = <(String, Color, Color, Color, Color)>[
    ('Papel', Color(0xFFFBF8F1), Color(0xFF26231E), Color(0xFF7A7266), Color(0xFFEDE8DC)),
    ('Sepia', Color(0xFFF3E9D2), Color(0xFF3A2E1F), Color(0xFF85725A), Color(0xFFE4D8BD)),
    ('Noche', Color(0xFF1C1C21), Color(0xFFDDD8CE), Color(0xFF8E897F), Color(0xFF111114)),
  ];
  static const _kLector = 'directa_lector_v1';

  // búsqueda
  bool _buscando = false;
  final _consulta = TextEditingController();
  bool _cargandoBusqueda = false;
  String? _errorBusqueda;
  List<Map<String, dynamic>> _resultados = [];
  String _busquedaHecha = '';
  int _paginasConCoincidencia = 0;

  String get _id => Uri.encodeComponent(widget.documentId);

  @override
  void initState() {
    super.initState();
    final pref = context.read<AppState>().store.getJson<Map>(_kLector, const {});
    _escala = ((pref['escala'] as num?)?.toInt() ?? 1).clamp(0, _escalas.length - 1).toInt();
    _tema = ((pref['tema'] as num?)?.toInt() ?? 0).clamp(0, _temas.length - 1).toInt();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarInfo());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _consulta.dispose();
    super.dispose();
  }

  Future<void> _cargarInfo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final st = context.read<AppState>();
      final r = await st.api.getJson('/api/documentos/$_id/lectura');
      if (r['ok'] != true) throw Exception('${r['error'] ?? 'No se pudo leer el documento'}');
      final paginas = [for (final p in (r['paginas'] as List? ?? const [])) if (p is num) p.toInt()]..sort();
      if (!mounted) return;
      setState(() {
        _documento = r['documento'] is Map ? Map<String, dynamic>.from(r['documento'] as Map) : null;
        _paginas = paginas;
        _indice = 0;
        _cargando = false;
      });
      if (paginas.isNotEmpty) await _cargarPagina(paginas.first);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Future<void> _cargarPagina(int numero) async {
    if (_textos.containsKey(numero)) return;
    setState(() => _cargandoPagina = true);
    try {
      final st = context.read<AppState>();
      final r = await st.api.getJson('/api/documentos/$_id/pagina/$numero');
      if (r['ok'] != true) throw Exception('${r['error'] ?? 'No se pudo leer la página'}');
      if (!mounted) return;
      setState(() {
        _textos[numero] = '${r['texto'] ?? ''}';
        _cargandoPagina = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargandoPagina = false;
      });
    }
  }

  Future<void> _irA(int indice) async {
    if (_paginas.isEmpty) return;
    final i = indice.clamp(0, _paginas.length - 1).toInt();
    setState(() => _indice = i);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _cargarPagina(_paginas[i]);
  }

  void _guardarPref() => context.read<AppState>().store.setJson(_kLector, {'escala': _escala, 'tema': _tema});

  /// Ajustes de lectura: tamaño de letra y color de la hoja.
  Future<void> _ajustesLectura() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void cambiar(VoidCallback f) {
          setState(f);
          setSheet(() {});
          _guardarPref();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ajustes de lectura', style: TextStyle(fontSize: Fs.xl, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            const Text('Tamaño de letra', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < _escalas.length; i++)
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Center(child: Text('Aa', style: TextStyle(fontSize: Fs.sm + i * 3.0, fontFamily: 'serif'))),
                    selected: _escala == i,
                    onSelected: (_) => cambiar(() => _escala = i),
                  ),
                )),
            ]),
            const SizedBox(height: 16),
            const Text('Color de la hoja', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < _temas.length; i++)
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => cambiar(() => _tema = i),
                    child: Container(
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _temas[i].$2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _tema == i ? Brand.accent : const Color(0x33000000), width: _tema == i ? 2.5 : 1),
                      ),
                      child: Text(_temas[i].$1, style: TextStyle(color: _temas[i].$3, fontFamily: 'serif', fontWeight: FontWeight.w600)),
                    ),
                  ),
                )),
            ]),
          ]),
        );
      }),
    );
  }

  Future<void> _irAPagina() async {
    final campo = TextEditingController();
    final texto = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        // Sube con el teclado para que el campo y el botón queden a la vista.
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Ir a la página', style: TextStyle(fontSize: Fs.xl, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: campo,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(hintText: 'Entre ${_paginas.first} y ${_paginas.last}'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          const SizedBox(height: 16),
          GgButton('Ir', expand: true, onTap: () => Navigator.pop(ctx, campo.text)),
          const SizedBox(height: 8),
          GgButton('Cancelar', ghost: true, expand: true, onTap: () => Navigator.pop(ctx)),
        ]),
      ),
    );
    campo.dispose();
    final n = int.tryParse((texto ?? '').trim());
    if (n == null) return;
    // Si la página pedida no tiene texto, se va a la más cercana que sí lo tiene.
    var mejor = 0;
    for (var i = 0; i < _paginas.length; i++) {
      if ((_paginas[i] - n).abs() < (_paginas[mejor] - n).abs()) mejor = i;
    }
    await _irA(mejor);
  }

  Future<void> _buscar() async {
    final q = _consulta.text.trim();
    if (q.length < 3) {
      setState(() {
        _errorBusqueda = 'Escribe al menos 3 letras.';
        _resultados = [];
      });
      return;
    }
    setState(() {
      _cargandoBusqueda = true;
      _errorBusqueda = null;
    });
    try {
      final st = context.read<AppState>();
      final r = await st.api.getJson('/api/documentos/$_id/buscar', query: {'q': q});
      if (r['ok'] != true) throw Exception('${r['error'] ?? 'No se pudo buscar'}');
      if (!mounted) return;
      setState(() {
        _resultados = [for (final x in (r['coincidencias'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
        _paginasConCoincidencia = (r['paginas'] as num?)?.toInt() ?? 0;
        _busquedaHecha = q;
        _cargandoBusqueda = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorBusqueda = e.toString().replaceFirst('Exception: ', '');
        _cargandoBusqueda = false;
      });
    }
  }

  void _cerrarBusqueda() => setState(() {
        _buscando = false;
        _consulta.clear();
        _resultados = [];
        _busquedaHecha = '';
        _errorBusqueda = null;
      });

  Future<void> _irAResultado(Map<String, dynamic> r) async {
    final n = (r['pagina'] as num?)?.toInt();
    final i = n == null ? -1 : _paginas.indexOf(n);
    _cerrarBusqueda();
    if (i >= 0) await _irA(i);
  }

  Future<void> _preguntarSobrePagina() async {
    if (_paginas.isEmpty) return;
    final st = context.read<AppState>();
    final numero = _paginas[_indice];
    final extracto = (_textos[numero] ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final cita = extracto.length > 320 ? '${extracto.substring(0, 320)}…' : extracto;
    if (st.docActivo != widget.documentId) await st.cambiarDocumento(widget.documentId);
    if (!mounted) return;
    final pregunta = 'Sobre la página $numero del documento${cita.isEmpty ? '' : ' («$cita»)'}: '
        '¿qué dice y qué debería destacar para el directorio?';
    // No se espera: la respuesta llega sola al asistente mientras se abre el panel.
    // ignore: unawaited_futures
    st.preguntarAsistente(pregunta);
    await abrirAsistente(context, pantalla: 'docs');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final titulo = (_documento?['nombre_archivo'] ?? _documento?['titulo'] ?? widget.nombreArchivo).toString();
    return Scaffold(
      appBar: AppBar(
        leading: _buscando ? IconButton(tooltip: 'Cerrar búsqueda', onPressed: _cerrarBusqueda, icon: const Icon(Icons.arrow_back)) : null,
        title: _buscando
            ? TextField(
                controller: _consulta,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _buscar(),
                decoration: InputDecoration(
                  hintText: 'Buscar en el documento…',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  suffixIcon: IconButton(tooltip: 'Buscar', onPressed: _buscar, icon: const Icon(Icons.search)),
                ),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Leer documento', style: TextStyle(fontSize: Fs.reading, fontWeight: FontWeight.w700)),
                if (titulo.isNotEmpty)
                  Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Fs.sm, color: c.text2)),
              ]),
        actions: _buscando
            ? const []
            : [
                IconButton(
                  tooltip: 'Buscar en el documento',
                  onPressed: _paginas.isEmpty ? null : () => setState(() => _buscando = true),
                  icon: const Icon(Icons.search),
                ),
                TextButton(
                  onPressed: _ajustesLectura,
                  child: Text('Aa', style: TextStyle(fontWeight: FontWeight.w700, fontSize: Fs.lg, color: c.text)),
                ),
              ],
      ),
      body: SafeArea(
        top: false,
        bottom: _buscando || _paginas.isEmpty, // con la barra inferior, ella ya respeta la barra de gestos
        child: _buscando ? _vistaBusqueda(context) : _vistaLectura(context),
      ),
      bottomNavigationBar: (_buscando || _paginas.isEmpty)
          ? null
          : Container(
              decoration: BoxDecoration(color: c.bg2, border: Border(top: BorderSide(color: c.border))),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SafeArea(
                top: false,
                child: Row(children: [
                  IconButton.outlined(
                    tooltip: 'Página anterior',
                    onPressed: _indice > 0 ? () => _irA(_indice - 1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: GgButton('Preguntar sobre esta página', icon: Icons.support_agent, expand: true, onTap: _preguntarSobrePagina)),
                  const SizedBox(width: 10),
                  IconButton.outlined(
                    tooltip: 'Página siguiente',
                    onPressed: _indice + 1 < _paginas.length ? () => _irA(_indice + 1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _vistaLectura(BuildContext context) {
    final c = context.c;
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null && _paginas.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        GgCard(
          borderColor: c.crit,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No se pudo cargar el documento', style: TextStyle(fontWeight: FontWeight.w700, color: c.crit)),
            const SizedBox(height: 6),
            Text(_error!, style: TextStyle(color: c.text2)),
            const SizedBox(height: 4),
            Text('Si el servidor se actualizó hace poco, espera a que termine de reiniciar y reintenta.',
                style: TextStyle(fontSize: Fs.sm, color: c.text3)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(onPressed: _cargarInfo, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
            ),
          ]),
        ),
      ]);
    }
    if (_paginas.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        EmptyState(
          icon: Icons.description_outlined,
          title: 'No hay texto disponible',
          text: 'Este documento no tiene texto guardado para mostrar. Si es un PDF escaneado, el texto no se pudo extraer.',
        ),
      ]);
    }

    final numero = _paginas[_indice];
    final totalReal = (_documento?['total_paginas'] as num?)?.toInt() ?? _paginas.last;
    final texto = _textos[numero];
    final escala = _escalas[_escala];
    final (_, hoja, tinta, suave, fondo) = _temas[_tema];
    final avance = _paginas.length > 1 ? _indice / (_paginas.length - 1) : 1.0;
    Widget cuerpo;
    if (texto == null && _error != null && !_cargandoPagina) {
      cuerpo = Column(children: [
        Text('No se pudo cargar esta página.', style: TextStyle(color: c.crit)),
        TextButton.icon(onPressed: () => _irA(_indice), icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
      ]);
    } else if (texto == null) {
      // Mientras llega la página se muestra la carga, no un error.
      cuerpo = Padding(padding: const EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: suave)));
    } else if (texto.trim().isEmpty) {
      cuerpo = Text('Esta página no tiene texto (puede ser una imagen).', style: TextStyle(color: suave, fontFamily: 'serif'));
    } else {
      cuerpo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final parrafo in texto.split(RegExp(r'\n{2,}')))
          if (parrafo.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SelectableText(
                _limpiarTexto(parrafo),
                textAlign: TextAlign.start, // justificado dejaba huecos enormes en pantallas angostas
                style: TextStyle(fontFamily: 'serif', fontSize: Fs.reading * escala, height: 1.65, color: tinta, letterSpacing: .1),
              ),
            ),
      ]);
    }
    return Container(
      color: fondo,
      child: Column(children: [
        // Barra fina de avance del documento + página actual.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 10, 4),
          child: Row(children: [
            Text('Página $numero de $totalReal', style: TextStyle(fontSize: Fs.md, color: suave, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(onPressed: _irAPagina, child: Text('Ir a página', style: TextStyle(color: suave))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: avance, minHeight: 3, color: Brand.accent, backgroundColor: suave.withValues(alpha: .2)),
          ),
        ),
        Expanded(
          // Deslizar a la izquierda o derecha cambia de página, como un libro.
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -250 && _indice + 1 < _paginas.length) _irA(_indice + 1);
              if (v > 250 && _indice > 0) _irA(_indice - 1);
            },
            child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
              Container(
                padding: const EdgeInsets.fromLTRB(26, 28, 26, 30),
                decoration: BoxDecoration(
                  color: hoja,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 4))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Text('— $numero —', style: TextStyle(fontFamily: 'serif', fontSize: Fs.sm, color: suave, letterSpacing: 1))),
                  const SizedBox(height: 18),
                  cuerpo,
                ]),
              ),
              const SizedBox(height: 10),
              Center(child: Text('Desliza para cambiar de página', style: TextStyle(fontSize: Fs.xs, color: suave))),
            ]),
          ),
        ),
      ]),
    );
  }

  /// Une los saltos de línea del PDF y junta las palabras que vienen con letras separadas
  /// ("R E S U M E N  E J E C U T I V O" → "RESUMEN EJECUTIVO").
  static String _limpiarTexto(String t) {
    var s = t.trim().replaceAll(RegExp(r'\s*\n\s*'), ' ');
    s = s.replaceAllMapped(RegExp(r'(?:\b\p{L} ){3,}\p{L}\b', unicode: true), (m) {
      final letras = m[0]!.split(' ');
      // Dos o más espacios seguidos en el original separan palabras; aquí todo viene con uno solo, así que se juntan.
      return letras.join();
    });
    return s;
  }

  Widget _vistaBusqueda(BuildContext context) {
    final c = context.c;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      if (_cargandoBusqueda) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
      if (_errorBusqueda != null) Text(_errorBusqueda!, style: TextStyle(color: c.crit)),
      if (!_cargandoBusqueda && _busquedaHecha.isEmpty && _errorBusqueda == null)
        Text('Escribe lo que buscas y presiona buscar. Se muestran las páginas donde aparece.', style: TextStyle(color: c.text2, fontSize: Fs.md)),
      if (!_cargandoBusqueda && _busquedaHecha.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _resultados.isEmpty
                ? 'Sin coincidencias para «$_busquedaHecha».'
                : '${_resultados.length} coincidencia${_resultados.length == 1 ? '' : 's'} en $_paginasConCoincidencia página${_paginasConCoincidencia == 1 ? '' : 's'}',
            style: TextStyle(fontSize: Fs.md, color: c.text2),
          ),
        ),
        for (final r in _resultados)
          GgCard(
            onTap: () => _irAResultado(r),
            padding: const EdgeInsets.all(13),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Pill('pág. ${r['pagina'] ?? '?'}', fg: c.text2, bg: c.surface2),
                const Spacer(),
                Icon(Icons.chevron_right, size: 18, color: c.text3),
              ]),
              const SizedBox(height: 8),
              Text.rich(TextSpan(style: TextStyle(fontSize: Fs.md, height: 1.5, color: c.text), children: [
                TextSpan(text: '${r['antes'] ?? ''}'),
                TextSpan(
                  text: '${r['coincide'] ?? ''}',
                  style: TextStyle(color: c.accentText, backgroundColor: c.accentSoft, fontWeight: FontWeight.w600),
                ),
                TextSpan(text: '${r['despues'] ?? ''}'),
              ])),
            ]),
          ),
      ],
    ]);
  }
}
