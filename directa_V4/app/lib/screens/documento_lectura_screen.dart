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
  final _scroll = ScrollController();

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
                TextButton(
                  onPressed: () => setState(() => _escala = (_escala + 1) % _escalas.length),
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
    final totalReal = (_documento?['total_paginas'] as num?)?.toInt();
    final texto = _textos[numero];
    final escala = _escalas[_escala];
    return ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      GgCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('$numero', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text(' de ${totalReal ?? _paginas.last}', style: TextStyle(fontSize: 13, color: c.text2)),
            const Spacer(),
            GgButton('Ir a página…', ghost: true, small: true, onTap: _irAPagina),
          ]),
          Slider(
            value: _indice.toDouble(),
            min: 0,
            max: _paginas.length > 1 ? (_paginas.length - 1).toDouble() : 1.0,
            divisions: _paginas.length > 1 ? _paginas.length - 1 : null,
            activeColor: Brand.accent,
            onChanged: _paginas.length > 1 ? (v) => setState(() => _indice = v.round()) : null,
            onChangeEnd: _paginas.length > 1 ? (v) => _irA(v.round()) : null,
          ),
        ]),
      ),
      GgCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PÁGINA $numero', style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: c.accentText)),
          const SizedBox(height: 14),
          if (texto == null && _cargandoPagina)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
          else if (texto == null)
            Text(_error ?? 'No se pudo cargar esta página.', style: TextStyle(color: c.crit))
          else if (texto.trim().isEmpty)
            Text('Esta página no tiene texto (puede ser una imagen).', style: TextStyle(color: c.text3))
          else
            for (final parrafo in texto.split(RegExp(r'\n{2,}')))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: SelectableText(parrafo.trim(), style: TextStyle(fontSize: 15.5 * escala, height: 1.7, color: c.text)),
              ),
        ]),
      ),
    ]);
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
