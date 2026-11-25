import 'dart:typed_data';

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
  bool _serif = false; // letra moderna por defecto; serif opcional

  // Página original del PDF (imagen): mantiene el orden real de columnas, tablas y títulos.
  bool _hayOriginal = false;
  bool _verOriginal = true;
  final Map<int, Uint8List> _imagenes = {};
  final Set<int> _imagenesConError = {};
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
    _serif = pref['serif'] == true;
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
      _revisarOriginal();
      if (paginas.isNotEmpty) await _cargarPagina(paginas.first);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Future<void> _revisarOriginal() async {
    try {
      final r = await context.read<AppState>().api.getJson('/api/documentos/$_id/original');
      if (!mounted) return;
      setState(() => _hayOriginal = r['ok'] == true);
      if (_hayOriginal && _paginas.isNotEmpty) _cargarImagen(_paginas[_indice]);
    } catch (_) {}
  }

  Future<void> _cargarImagen(int numero) async {
    if (_imagenes.containsKey(numero)) return;
    try {
      final ancho = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).clamp(600, 1600).round();
      final b = await context.read<AppState>().api.getBytes('/api/documentos/$_id/pagina/$numero/imagen?ancho=$ancho');
      if (!mounted) return;
      setState(() {
        _imagenes[numero] = b;
        _imagenesConError.remove(numero);
      });
    } catch (_) {
      if (mounted) setState(() => _imagenesConError.add(numero));
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
    if (_hayOriginal) _cargarImagen(_paginas[i]);
    await _cargarPagina(_paginas[i]);
  }

  void _guardarPref() => context.read<AppState>().store.setJson(_kLector, {'escala': _escala, 'tema': _tema, 'serif': _serif});

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
            const Text('Ajustes de lectura', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            const Text('Tamaño de letra', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < _escalas.length; i++)
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Center(child: Text('Aa', style: TextStyle(fontSize: 12 + i * 3.0, fontFamily: 'serif'))),
                    selected: _escala == i,
                    onSelected: (_) => cambiar(() => _escala = i),
                  ),
                )),
            ]),
            const SizedBox(height: 16),
            const Text('Tipo de letra', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ChoiceChip(label: const Center(child: Text('Moderna')), selected: !_serif, onSelected: (_) => cambiar(() => _serif = false))),
              const SizedBox(width: 8),
              Expanded(child: ChoiceChip(label: const Center(child: Text('Libro', style: TextStyle(fontFamily: 'serif'))), selected: _serif, onSelected: (_) => cambiar(() => _serif = true))),
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
    final c = context.c;
    final campo = TextEditingController();
    final texto = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ir a la página'),
        content: TextField(
          controller: campo,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: 'Entre ${_paginas.first} y ${_paginas.last}'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: TextStyle(color: c.text2))),
          TextButton(onPressed: () => Navigator.pop(ctx, campo.text), child: const Text('Ir')),
        ],
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
                const Text('Leer documento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                if (titulo.isNotEmpty)
                  Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: c.text2)),
              ]),
        actions: _buscando
            ? const []
            : [
                IconButton(
                  tooltip: 'Buscar en el documento',
                  onPressed: _paginas.isEmpty ? null : () => setState(() => _buscando = true),
                  icon: const Icon(Icons.search),
                ),
                if (_hayOriginal)
                  IconButton(
                    tooltip: _verOriginal ? 'Ver como texto' : 'Ver página original',
                    onPressed: () => setState(() => _verOriginal = !_verOriginal),
                    icon: Icon(_verOriginal ? Icons.notes_rounded : Icons.picture_as_pdf_outlined),
                  ),
                TextButton(
                  onPressed: _ajustesLectura,
                  child: Text('Aa', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.text)),
                ),
              ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: _buscando ? _vistaBusqueda(context) : _vistaLectura(context),
        ),
      ),
      bottomNavigationBar: (_buscando || _paginas.isEmpty)
          ? null
          : Container(
              decoration: BoxDecoration(color: c.bg2, border: Border(top: BorderSide(color: c.border))),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
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
                style: TextStyle(fontSize: 12, color: c.text3)),
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
    if (_hayOriginal && _verOriginal) return _vistaOriginal(numero, totalReal, avance, suave, fondo);
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
        for (final parrafo in _parrafos(texto))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SelectableText(
              parrafo,
              textAlign: TextAlign.start, // justificado dejaba huecos enormes en pantallas angostas
              style: TextStyle(fontFamily: _serif ? 'serif' : null, fontSize: (_serif ? 16.5 : 15.5) * escala, height: 1.6, color: tinta),
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
            Text('Página $numero de $totalReal', style: TextStyle(fontSize: 12.5, color: suave, fontWeight: FontWeight.w600)),
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
                  Center(child: Text('— $numero —', style: TextStyle(fontFamily: 'serif', fontSize: 12, color: suave, letterSpacing: 1))),
                  const SizedBox(height: 18),
                  cuerpo,
                ]),
              ),
              const SizedBox(height: 10),
              Center(child: Text('Desliza para cambiar de página', style: TextStyle(fontSize: 11, color: suave))),
            ]),
          ),
        ),
      ]),
    );
  }

  /// La página tal cual es en el PDF, con zoom (pellizcar) y doble toque para volver al tamaño normal.
  Widget _vistaOriginal(int numero, int total, double avance, Color suave, Color fondo) {
    final img = _imagenes[numero];
    return Container(
      color: fondo,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 10, 4),
          child: Row(children: [
            Text('Página $numero de $total', style: TextStyle(fontSize: 12.5, color: suave, fontWeight: FontWeight.w600)),
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
          child: img == null
              ? Center(
                  child: _imagenesConError.contains(numero)
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('No se pudo cargar la página.', style: TextStyle(color: suave)),
                          TextButton.icon(onPressed: () => _cargarImagen(numero), icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
                          TextButton(onPressed: () => setState(() => _verOriginal = false), child: const Text('Ver como texto')),
                        ])
                      : CircularProgressIndicator(color: suave),
                )
              : InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 4))]),
                        child: Image.memory(img, fit: BoxFit.contain, gaplessPlayback: true),
                      ),
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Pellizca para ampliar · flechas para cambiar de página', style: TextStyle(fontSize: 11, color: suave)),
        ),
      ]),
    );
  }

  /// Limpia una porción de texto del PDF: une líneas, quita los puntos de relleno de los índices
  /// ("Tabla 12 ........ 10" → "Tabla 12 · 10") y junta palabras con letras separadas ("R E S U M E N").
  static String _limpiarTexto(String t) {
    var s = t.trim().replaceAll(RegExp(r'-\s*\n\s*'), '').replaceAll(RegExp(r'\s*\n\s*'), ' ');
    s = s.replaceAll(RegExp(r'\s*(?:\.\s?){4,}\s*|\s*…{2,}\s*'), '  ·  ');
    s = s.replaceAllMapped(RegExp(r'(?:\b\p{L} ){3,}\p{L}\b', unicode: true), (m) => m[0]!.replaceAll(' ', ''));
    return s.replaceAll(RegExp(r' {3,}'), '  ').trim();
  }

  /// Divide la página en párrafos legibles. El texto del PDF suele venir en un solo bloque, así que se corta
  /// antes de tablas, figuras, títulos numerados y viñetas, y los bloques muy largos cada 2–3 oraciones.
  static List<String> _parrafos(String texto) {
    final out = <String>[];
    for (final bloque in texto.split(RegExp(r'\n{2,}'))) {
      final limpio = _limpiarTexto(bloque);
      if (limpio.isEmpty) continue;
      final cortes = limpio
          .replaceAllMapped(
              RegExp(r'\s+(?=(?:Tabla|Figura|Gráfico|Anexo|Capítulo)\s+\d|(?<!(?:Tabla|Figura|Gráfico|Anexo|Capítulo)\s)\d{1,2}\.\d?\s+[A-ZÁÉÍÓÚÑ][a-záéíóúñ]|[•▪●]\s|[A-ZÁÉÍÓÚÑ]{4,}(?:\s+[A-ZÁÉÍÓÚÑ]{2,})*\s+[A-ZÁÉÍÓÚÑ][a-záéíóúñ])', unicode: true),
              (_) => '\n')
          .split('\n');
      for (final c in cortes) {
        final p = c.trim();
        if (p.isEmpty) continue;
        if (p.length <= 420) {
          out.add(p);
          continue;
        }
        // Párrafo muy largo: se parte cada ~3 oraciones.
        final oraciones = p.split(RegExp(r'(?<=[.!?])\s+(?=[A-ZÁÉÍÓÚÑ¿¡])', unicode: true));
        var buf = '';
        var n = 0;
        for (final o in oraciones) {
          buf = buf.isEmpty ? o : '$buf $o';
          n++;
          if (n >= 3 || buf.length > 380) {
            out.add(buf);
            buf = '';
            n = 0;
          }
        }
        if (buf.isNotEmpty) out.add(buf);
      }
    }
    return out;
  }

  Widget _vistaBusqueda(BuildContext context) {
    final c = context.c;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      if (_cargandoBusqueda) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
      if (_errorBusqueda != null) Text(_errorBusqueda!, style: TextStyle(color: c.crit)),
      if (!_cargandoBusqueda && _busquedaHecha.isEmpty && _errorBusqueda == null)
        Text('Escribe lo que buscas y presiona buscar. Se muestran las páginas donde aparece.', style: TextStyle(color: c.text2, fontSize: 13)),
      if (!_cargandoBusqueda && _busquedaHecha.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _resultados.isEmpty
                ? 'Sin coincidencias para «$_busquedaHecha».'
                : '${_resultados.length} coincidencia${_resultados.length == 1 ? '' : 's'} en $_paginasConCoincidencia página${_paginasConCoincidencia == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12.5, color: c.text2),
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
              Text.rich(TextSpan(style: TextStyle(fontSize: 13, height: 1.5, color: c.text), children: [
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
