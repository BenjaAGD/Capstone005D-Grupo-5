import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'valoracion.dart';
import 'verificacion.dart';

/// Sugerencias distintas según la pantalla desde la que se abre el asistente.
const _sugDocumento = {
  'inicio': ['¿De qué trata el documento?', '¿Qué es lo más grave para el directorio?'],
  'docs': ['¿De qué trata el documento?', '¿Qué período cubre el documento?'],
  'resultados': ['¿Qué señal crítica debo explicar primero?', '¿Qué dato falta para responder al directorio?'],
  'preparar': ['¿Cuál es la pregunta más difícil que me harán?', '¿Qué cifra clave debo tener a mano?'],
  'dashboard': ['¿Qué indicador empeoró más?', '¿Qué área tiene el peor puntaje y por qué?'],
  'memoria': ['¿Qué contenidos de la NCG 461 trae el documento?', '¿Cómo describe la empresa su estrategia?'],
  'indicadores': ['¿Qué indicador está en rojo y por qué?', '¿Qué meta conviene comprometer?'],
  'informe': ['¿Qué debería ir primero en el informe?', '¿Qué conclusión destaca el documento?'],
  'aprendizaje': ['¿Qué respuestas valoró mal el gerente?'],
};

const _sugAyuda = {
  'inicio': ['¿Cómo preparo mi reunión?', '¿Qué hace cada pantalla?'],
  'docs': ['¿Cómo subo un documento?', '¿Por qué tarda el análisis?'],
  'chat': ['¿Qué es la ruta de preguntas?', '¿Qué significa el sello Verificada?'],
  'resultados': ['¿Qué significa el sello Verificada?', '¿Cómo se calcula el puntaje?'],
  'preparar': ['¿De dónde salen las preguntas probables?', '¿Cómo agrego una respuesta al informe?'],
  'dashboard': ['¿Cómo comparo dos documentos?', '¿Cómo descargo el Excel?'],
  'memoria': ['¿Cómo armo la memoria?', '¿Qué es el perfil de tono?'],
  'indicadores': ['¿Cómo creo un KPI?', '¿Qué diferencia hay entre KPI y KRI?'],
  'informe': ['¿Cómo descargo el informe?', '¿Qué incluye el PDF?'],
  'aprendizaje': ['¿Qué es una lección?', '¿Cómo se aprueba una lección?'],
  'ajustes': ['¿Cómo cambio la dirección del servidor?'],
};

/// Burbuja del asistente (Frente E2). Se puede ARRASTRAR a cualquier lugar de la pantalla: al soltarla
/// se acomoda sola en el borde izquierdo o derecho y la app recuerda dónde la dejaste.
/// Envuelve el cuerpo de cada pantalla (en el Shell y en las pantallas secundarias).
class AsistenteOverlay extends StatefulWidget {
  const AsistenteOverlay({super.key, required this.pantalla, required this.child, this.visible = true});
  final String pantalla;
  final Widget child;

  /// El chat de análisis ya es un chat, así que ahí la burbuja no se muestra.
  final bool visible;

  @override
  State<AsistenteOverlay> createState() => _AsistenteOverlayState();
}

class _AsistenteOverlayState extends State<AsistenteOverlay> {
  static const _tam = 56.0;
  static const _margen = 16.0;

  // La posición se guarda como fracción del área (0 a 1), así sirve en cualquier tamaño de pantalla.
  double? _fx, _fy;
  Offset? _arrastre; // posición en píxeles mientras el dedo la mueve
  bool _moviendo = false;
  bool _ayuda = false;
  Timer? _timerAyuda;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppState>().store;
    final g = store.getJson<Map>(Store.kAsistentePos, const {});
    final x = g['x'], y = g['y'];
    if (x is num && y is num) {
      _fx = x.toDouble();
      _fy = y.toDouble();
    }
    if (store.getString(Store.kAsistenteAyuda) == null) {
      _ayuda = true;
      _timerAyuda = Timer(const Duration(seconds: 7), _cerrarAyuda);
    }
  }

  @override
  void dispose() {
    _timerAyuda?.cancel();
    super.dispose();
  }

  void _cerrarAyuda() {
    _timerAyuda?.cancel();
    if (!mounted) return;
    if (_ayuda) setState(() => _ayuda = false);
    unawaited(context.read<AppState>().store.setString(Store.kAsistenteAyuda, '1'));
  }

  Offset _predeterminada(Size s) => Offset(s.width - _tam - _margen, s.height - _tam - _margen);

  Offset _limitar(Offset o, Size s) => Offset(
        o.dx.clamp(_margen, math.max(_margen, s.width - _tam - _margen)).toDouble(),
        o.dy.clamp(_margen, math.max(_margen, s.height - _tam - _margen)).toDouble(),
      );

  Offset _actual(Size s) {
    if (_arrastre != null) return _limitar(_arrastre!, s);
    if (_fx != null && _fy != null) return _limitar(Offset(_fx! * s.width, _fy! * s.height), s);
    return _predeterminada(s);
  }

  void _soltar(Size s) {
    final p = _limitar(_arrastre ?? _actual(s), s);
    final alBordeIzq = p.dx + _tam / 2 < s.width / 2;
    final x = alBordeIzq ? _margen : s.width - _tam - _margen;
    setState(() {
      _moviendo = false;
      _arrastre = null;
      _fx = x / s.width;
      _fy = p.dy / s.height;
    });
    unawaited(context.read<AppState>().store.setJson(Store.kAsistentePos, {'x': _fx, 'y': _fy}));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      final pos = _actual(size);
      final izquierda = pos.dx + _tam / 2 < size.width / 2;
      // El cuerpo siempre es el primer hijo, para no perder su estado cuando la burbuja aparece o se oculta.
      return Stack(children: [
        Positioned.fill(child: widget.child),
        if (widget.visible && _ayuda && !_moviendo)
          Positioned(
            left: izquierda ? pos.dx + _tam + 10 : null,
            right: izquierda ? null : size.width - pos.dx + 10,
            top: pos.dy,
            child: _globoAyuda(context, math.max(120.0, math.min(240.0, size.width - _tam - 2 * _margen - 10))),
          ),
        if (widget.visible)
          AnimatedPositioned(
            duration: _moviendo ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            left: pos.dx,
            top: pos.dy,
            width: _tam,
            height: _tam,
            child: Tooltip(
              message: 'Asistente: ayuda y preguntas al documento',
              triggerMode: TooltipTriggerMode.manual,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _cerrarAyuda();
                  abrirAsistente(context, pantalla: widget.pantalla);
                },
                onPanStart: (_) {
                  _cerrarAyuda();
                  setState(() {
                    _moviendo = true;
                    _arrastre = _actual(size);
                  });
                },
                onPanUpdate: (d) => setState(() => _arrastre = _limitar((_arrastre ?? _actual(size)) + d.delta, size)),
                onPanEnd: (_) => _soltar(size),
                onPanCancel: () => _soltar(size),
                child: AnimatedScale(
                  scale: _moviendo ? 1.1 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: Material(
                    color: Brand.accent,
                    elevation: _moviendo ? 10 : 6,
                    borderRadius: BorderRadius.circular(16),
                    child: const Center(child: Icon(Icons.support_agent, size: 26, color: Brand.onAccent)),
                  ),
                ),
              ),
            ),
          ),
      ]);
    });
  }

  Widget _globoAyuda(BuildContext context, double ancho) {
    final c = context.c;
    return IgnorePointer(
      child: Container(
        width: ancho,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface3,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.open_with, size: 15, color: c.accentText),
            const SizedBox(width: 6),
            Flexible(child: Text('Muévelo donde quieras', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: c.accentText))),
          ]),
          const SizedBox(height: 3),
          Text('Mantén presionado y arrastra. Se acomoda sola en el borde.', style: TextStyle(fontSize: 11.5, height: 1.35, color: c.text2)),
        ]),
      ),
    );
  }
}

Future<void> abrirAsistente(BuildContext context, {required String pantalla, int pestana = 0}) {
  final st = context.read<AppState>();
  st.setPantalla(pantalla);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 720),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ChangeNotifierProvider.value(
      value: st,
      child: FractionallySizedBox(heightFactor: 0.86, child: _Asistente(pantalla: pantalla, pestana: pestana)),
    ),
  );
}

class _Asistente extends StatefulWidget {
  const _Asistente({required this.pantalla, required this.pestana});
  final String pantalla;
  final int pestana;
  @override
  State<_Asistente> createState() => _AsistenteState();
}

class _AsistenteState extends State<_Asistente> {
  late int _modo = widget.pestana; // 0 = preguntar al documento, 1 = ayuda de la app
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _alFondo() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _enviar(String t) async {
    final st = context.read<AppState>();
    _input.clear();
    _alFondo();
    if (_modo == 0) {
      await st.preguntarAsistente(t);
    } else {
      await st.preguntarAyuda(t);
    }
    _alFondo();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final doc = st.docActivoMap;
    final nombre = nombreDoc(doc);
    final paginas = doc?['total_paginas'];
    return Column(children: [
      const SizedBox(height: 8),
      Container(width: 40, height: 4, decoration: BoxDecoration(color: c.border2, borderRadius: BorderRadius.circular(2))),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.support_agent, size: 19, color: c.accentText),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Asistente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(
                nombre.isEmpty ? 'Sin documento activo' : '$nombre${paginas != null ? ' · $paginas páginas' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: c.text3),
              ),
            ]),
          ),
          IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          ChipBtn('Preguntar al documento', on: _modo == 0, onTap: () => setState(() => _modo = 0)),
          ChipBtn('Ayuda de la app', on: _modo == 1, onTap: () => setState(() => _modo = 1)),
        ]),
      ),
      Expanded(child: _modo == 0 ? _documento(context, st) : _ayuda(context, st)),
      Container(
        decoration: BoxDecoration(color: c.bg2, border: Border(top: BorderSide(color: c.border))),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _enviar,
                decoration: InputDecoration(
                  hintText: _modo == 0 ? 'Pregunta sobre el documento activo…' : '¿Cómo hago…?',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: c.border2)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: c.border2)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Brand.accent)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Enviar',
              onPressed: (st.asistenteConsultando || st.ayudaBuscando) ? null : () => _enviar(_input.text),
              style: IconButton.styleFrom(backgroundColor: Brand.accent, foregroundColor: Brand.onAccent, fixedSize: const Size(46, 46)),
              icon: const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ),
    ]);
  }

  /// Preguntas sugeridas, una por fila.
  Widget _sugerencias(List<String> sug) {
    final c = context.c;
    return Column(children: [
      for (final s in sug)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.border2)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _enviar(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                child: Row(children: [
                  Icon(Icons.auto_awesome_outlined, size: 17, color: c.accentText),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
                  Icon(Icons.chevron_right, size: 17, color: c.text3),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _documento(BuildContext context, AppState st) {
    final c = context.c;
    final sug = _sugDocumento[widget.pantalla] ?? _sugDocumento['inicio']!;
    return ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
      if (st.asistenteMsgs.isEmpty) ...[
        GgCard(
          color: c.surface2,
          padding: const EdgeInsets.all(13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.verified_outlined, size: 20, color: c.low),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                st.docActivo == null
                    ? 'Selecciona un documento para preguntarle.'
                    : 'Responde el Asistente General con el documento activo, y cada respuesta pasa por el verificador. Te muestro la página de donde salió.',
                style: TextStyle(fontSize: 12.5, height: 1.45, color: c.text2),
              ),
            ),
          ]),
        ),
        const SecTitle('Prueba preguntando'),
        _sugerencias(sug),
      ],
      for (final m in st.asistenteMsgs)
        m.rol == 'me'
            ? _burbuja(context, m.texto, propia: true)
            : _burbuja(
                context,
                m.texto,
                cargando: m.streaming,
                error: m.error,
                fuentes: m.fuentes,
                pie: m.streaming || m.error
                    ? null
                    : Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        SelloVerificacion(verificacion: m.verificacion, textoOriginal: m.textoOriginal),
                        Valoracion(msg: m, documentId: st.docActivo),
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, foregroundColor: c.accentText),
                          onPressed: () => st.asistenteAlChat(m),
                          icon: const Icon(Icons.forum_outlined, size: 15),
                          label: const Text('Llevar al chat', style: TextStyle(fontSize: 12)),
                        ),
                      ]),
              ),
    ]);
  }

  Widget _ayuda(BuildContext context, AppState st) {
    final sug = _sugAyuda[widget.pantalla] ?? _sugAyuda['inicio']!;
    return ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
      if (st.ayudaMsgs.isEmpty) ...[
        const SecTitle('Dudas frecuentes'),
        _sugerencias(sug),
      ],
      for (final (yo, t) in st.ayudaMsgs) _burbuja(context, t, propia: yo),
      if (st.ayudaBuscando) _burbuja(context, '', cargando: true),
    ]);
  }

  Widget _burbuja(BuildContext context, String texto,
      {bool propia = false, bool cargando = false, bool error = false, Widget? pie, List<Map<String, dynamic>> fuentes = const []}) {
    final c = context.c;
    final paginas = <String>[];
    for (final f in fuentes) {
      final p = '${f['pagina'] ?? ''}'.trim();
      if (p.isNotEmpty && !paginas.contains(p)) paginas.add(p);
    }
    return Align(
      alignment: propia ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: BoxConstraints(maxWidth: propia ? 520 : 600),
        decoration: BoxDecoration(
          color: propia ? Brand.accent : c.surface2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(propia ? 16 : 4),
            bottomRight: Radius.circular(propia ? 4 : 16),
          ),
          border: propia ? null : Border.all(color: c.border),
        ),
        child: cargando
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('Buscando…', style: TextStyle(color: c.text3)),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                propia
                    ? Text(texto, style: const TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w500, color: Brand.onAccent))
                    : (error
                        ? Text(texto, style: TextStyle(color: c.high, fontSize: 13))
                        : MarkdownLite(texto, size: 13.4)),
                if (!propia && !error && paginas.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (var i = 0; i < paginas.length && i < 6; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(color: c.bg2, borderRadius: BorderRadius.circular(9), border: Border.all(color: c.border)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.description_outlined, size: 12, color: c.text2),
                          const SizedBox(width: 5),
                          Text('pág. ${paginas[i]}', style: TextStyle(fontSize: 11.5, color: c.text2)),
                        ]),
                      ),
                  ]),
                ],
                if (pie != null) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: c.border),
                  const SizedBox(height: 8),
                  pie,
                ],
              ]),
      ),
    );
  }
}

/// Atajo usado por "Más → Asistente y ayuda".
void abrirAyuda(BuildContext context, String pantalla) => abrirAsistente(context, pantalla: pantalla, pestana: 1);
