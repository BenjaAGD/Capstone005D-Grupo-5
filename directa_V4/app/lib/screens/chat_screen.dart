import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/valoracion.dart';
import '../widgets/verificacion.dart';

const _temasGuia = <({String tema, String pregunta})>[
  (tema: 'Rentabilidad', pregunta: '¿Qué explica los cambios de ingresos, margen y caja durante el período?'),
  (tema: 'Inversión', pregunta: '¿Qué inversiones concentran capital y cómo se medirá su retorno?'),
  (tema: 'Seguridad operacional', pregunta: '¿Qué riesgos y controles críticos requieren seguimiento?'),
  (tema: 'Sostenibilidad', pregunta: '¿Qué metas, impactos o brechas ambientales y sociales deben revisarse?'),
  (tema: 'Personas', pregunta: '¿Qué cambios en talento, seguridad y sucesión son relevantes para el directorio?'),
];

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final Map<String, String> _tab = {};
  int _ultimo = -1;
  String _ultimoTexto = '';
  bool _guiaAbierta = true;

  static const _sugerencias = <({IconData icono, String titulo, String detalle, String pregunta})>[
    (icono: Icons.notes_rounded, titulo: 'Resumen ejecutivo', detalle: 'Los puntos más importantes en pocas líneas', pregunta: 'Resume los puntos más importantes del documento'),
    (icono: Icons.warning_amber_rounded, titulo: 'Riesgos y alertas', detalle: 'Qué señales graves aparecen y por qué', pregunta: '¿Qué riesgos o alertas destacan en el documento?'),
    (icono: Icons.attach_money_rounded, titulo: 'Cifras clave', detalle: 'Qué números debería revisar el directorio', pregunta: '¿Qué cifras clave debería revisar el directorio?'),
    (icono: Icons.help_outline_rounded, titulo: 'Preguntas del directorio', detalle: 'Las que probablemente te harán en la sesión', pregunta: '¿Qué preguntas es probable que haga el directorio sobre este documento?'),
  ];

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    _input.text = st.borrador;
    _inputFocus.addListener(_alCambiarFoco);
  }

  // Al abrir el teclado se compacta la guía (para que no tape la conversación)
  // y se baja al último mensaje una vez que el teclado terminó de subir.
  void _alCambiarFoco() {
    if (!mounted) return;
    setState(() {});
    if (_inputFocus.hasFocus) {
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        if (mounted) _alFondo(animar: true, forzar: true);
      });
    }
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_alCambiarFoco);
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Baja al final solo si el usuario ya estaba abajo (o se fuerza),
  /// para no quitarle el control mientras lee mensajes anteriores.
  void _alFondo({bool animar = false, bool forzar = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      final cerca = pos.maxScrollExtent - pos.pixels < 160;
      if (!cerca && !forzar) return;
      if (animar) {
        _scroll.animateTo(pos.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  /// Envía una pregunta sugerida de inmediato, sin abrir el teclado ni copiarla al campo de texto.
  Future<void> _enviarDirecto(AppState st, String pregunta) async {
    if (st.consultando) return;
    if (st.docActivoMap == null) {
      st.toast('Selecciona un documento activo para consultar la IA', err: true);
      return;
    }
    _inputFocus.unfocus();
    st.modoGuia = false;
    setState(() {
      _guiaAbierta = false; // la guía queda en una línea; se reabre con el botón de sugerencias
    });
    _alFondo(animar: true, forzar: true);
    await st.enviarPregunta(pregunta);
  }

  /// Hoja con los temas de la guía y las preguntas sugeridas, a un toque desde el campo de texto.
  Future<void> _abrirSugerencias(AppState st) async {
    _inputFocus.unfocus();
    final c = context.c;
    final pregunta = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        Widget fila(IconData icono, String titulo, String detalle, String q, {bool hecho = false}) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: c.surface2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.pop(ctx, q),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
                        child: Icon(hecho ? Icons.check_rounded : icono, size: 18, color: hecho ? c.low : c.accentText),
                      ),
                      const SizedBox(width: 11),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(detalle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: c.text2)),
                      ])),
                      Icon(Icons.north_east_rounded, size: 17, color: c.accentText),
                    ]),
                  ),
                ),
              ),
            );
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .7,
          maxChildSize: .92,
          builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), children: [
            Center(child: Container(width: 38, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: c.border2, borderRadius: BorderRadius.circular(3)))),
            const Text('Sugerencias', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('Toca una y se envía al tiro.', style: TextStyle(fontSize: 12, color: c.text2)),
            const SizedBox(height: 14),
            SecTitle('Guía de análisis · ${st.guiaTemasCompletados.length}/5', bottom: 8),
            for (var i = 0; i < _temasGuia.length; i++)
              fila(Icons.route_outlined, _temasGuia[i].tema, _temasGuia[i].pregunta, _temasGuia[i].pregunta,
                  hecho: st.guiaTemasCompletados.contains(i)),
            const SizedBox(height: 8),
            const SecTitle('Preguntas rápidas', bottom: 8),
            for (final q in _sugerencias) fila(q.icono, q.titulo, q.detalle, q.pregunta),
          ]),
        );
      },
    );
    if (pregunta != null && mounted) await _enviarDirecto(st, pregunta);
  }

  /// La persona quiere escribir su propia respuesta al tema: aquí sí se abre el teclado.
  void _responderConMisPalabras() {
    setState(() => _guiaAbierta = false);
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  Future<void> _enviar(AppState st) async {
    final respuesta = _input.text.trim();
    if (respuesta.isEmpty || st.consultando) return;
    _inputFocus.unfocus(); // el teclado se cierra al enviar y no vuelve a abrirse solo
    final documento = st.docActivoMap;
    if (documento == null && !context.read<AppState>().modoGuia) {
      st.toast('Selecciona un documento activo para consultar la IA', err: true);
      return;
    }

    _input.clear();
    _alFondo(animar: true, forzar: true);
    if (!context.read<AppState>().modoGuia) {
      await st.enviarPregunta(respuesta);
      return;
    }

    final indice = st.guiaTemaSeleccionado;
    final paso = _temasGuia[indice];
    final contextoPrevio = st.respuestasGuia.entries
        .where((e) => e.key != indice)
        .map((e) => '${_temasGuia[e.key].tema}: ${e.value}')
        .join('\n');
    final consulta = [
      'Guía de análisis: ${paso.tema}.',
      'Pregunta de la guía: ${paso.pregunta}',
      if (contextoPrevio.isNotEmpty) 'Contexto previo entregado por gerencia:\n$contextoPrevio',
      'Respuesta de gerencia para este tema:\n$respuesta',
      'Contrasta el contexto de gerencia con el documento activo. Distingue lo que está respaldado por evidencia, lo que es contexto aportado por gerencia y lo que falta validar. Cita las páginas disponibles y no inventes datos.',
    ].join('\n\n');

    // Sin documento no se simula una respuesta de IA: se conserva el contexto del gerente localmente.
    if (documento == null) {
      st.completarTemaGuia(indice, respuesta);
      st.toast('Respuesta guardada en este dispositivo; queda pendiente de contrastar con un documento.');
      return;
    }

    final ok = await st.enviarPregunta(respuesta, consulta: consulta);
    if (!mounted) return;
    st.completarTemaGuia(indice, respuesta);
    if (!ok) st.toast('Respuesta guardada; la consulta de IA no se completó.', err: true);
  }

  Widget _panelGuia(AppState st) {
    final c = context.c;
    final seleccion = st.guiaTemaSeleccionado;
    final paso = _temasGuia[seleccion];
    final completados = st.guiaTemasCompletados;
    final respuestas = st.respuestasGuia;
    if (_inputFocus.hasFocus || !_guiaAbierta) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _inputFocus.unfocus();
          setState(() => _guiaAbierta = true);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.accentText.withValues(alpha: .3))),
          child: Row(children: [
            Icon(Icons.route_outlined, size: 17, color: c.accentText),
            const SizedBox(width: 8),
            Expanded(child: Text('Tema ${seleccion + 1}/5 · ${paso.tema}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.accentText))),
            Text('${completados.length}/5', style: TextStyle(fontSize: 11.5, color: c.text3)),
            Icon(Icons.expand_more, size: 18, color: c.text3),
          ]),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.route_outlined, size: 17, color: c.accentText),
          const SizedBox(width: 7),
          Expanded(child: Text('Guía de análisis · Tema ${seleccion + 1} de 5',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentText))),
          Text('${completados.length}/5', style: TextStyle(fontSize: 11, color: c.text3)),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          for (var i = 0; i < 5; i++)
            Expanded(child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i == 4 ? 0 : 5),
              decoration: BoxDecoration(
                color: completados.contains(i) ? c.accentText : (i == seleccion ? c.accentText.withValues(alpha: .45) : c.track),
                borderRadius: BorderRadius.circular(3),
              ),
            )),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < _temasGuia.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => st.seleccionarTemaGuia(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: seleccion == i ? Brand.accent : c.surface2,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: seleccion == i ? Brand.accent : c.border2),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (completados.contains(i)) ...[
                          Icon(Icons.check_rounded, size: 15, color: seleccion == i ? Brand.onAccent : c.low),
                          const SizedBox(width: 4),
                        ],
                        Text(_temasGuia[i].tema, style: TextStyle(
                          fontSize: 12.5, fontWeight: seleccion == i ? FontWeight.w800 : FontWeight.w500,
                          color: seleccion == i ? Brand.onAccent : c.text2)),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.accentText.withValues(alpha: .35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [c.accentText.withValues(alpha: .14), c.accentText.withValues(alpha: .03)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TEMA ${seleccion + 1} DE 5 · ${paso.tema.toUpperCase()}',
                style: TextStyle(fontSize: 10.5, letterSpacing: .8, fontWeight: FontWeight.w800, color: c.accentText)),
            const SizedBox(height: 6),
            Text(paso.pregunta, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35)),
            if (respuestas[seleccion] != null) ...[
              const SizedBox(height: 6),
              Text('Tu respuesta: ${respuestas[seleccion]}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: c.text3)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: st.docActivo == null || st.consultando ? null : () => _enviarDirecto(st, paso.pregunta),
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.accent, foregroundColor: Brand.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Analizar con el documento', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _responderConMisPalabras,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  side: BorderSide(color: c.border2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('Responder con mis palabras', style: TextStyle(color: c.text2)),
              ),
            ),
            if (st.docActivo == null) ...[
              const SizedBox(height: 6),
              Text('Selecciona un documento para analizar este tema.', style: TextStyle(fontSize: 11, color: c.text3)),
            ],
          ]),
        ),
        if (completados.length == 5) ...[
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuiaSintesisScreen())),
              icon: const Icon(Icons.fact_check_outlined, size: 17),
              label: const Text('Ver síntesis y seguimiento'),
            ),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final doc = st.docActivoMap;
    if (st.borrador.isNotEmpty && _input.text != st.borrador) {
      _input.text = st.borrador;
      st.borrador = '';
    }
    final ultimoTexto = st.mensajes.isEmpty ? '' : st.mensajes.last.texto;
    if (st.mensajes.length != _ultimo || ultimoTexto != _ultimoTexto) {
      _ultimo = st.mensajes.length;
      _ultimoTexto = ultimoTexto;
      _alFondo();
    }

    return Column(children: [
      Expanded(
        child: ListView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          children: [
            if (doc == null) ...[
              GgCard(
                borderColor: c.border2,
                child: Row(children: [
                  Icon(Icons.description_outlined, color: c.text3),
                  const SizedBox(width: 9),
                  const Expanded(child: Text('La guía está disponible. Para contrastar tus respuestas y ver evidencia, selecciona un documento.')),
                  TextButton(onPressed: () => st.go('documentos'), child: const Text('Documentos')),
                ]),
              ),
            ],
            if (st.mensajes.isEmpty && (context.read<AppState>().modoGuia || doc == null))
              GgCard(
                borderColor: c.accentText.withValues(alpha: .35),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.auto_awesome_outlined, color: c.accentText, size: 21),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.read<AppState>().modoGuia ? 'Revisa cinco temas clave' : 'Consulta el documento',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(context.read<AppState>().modoGuia
                        ? 'Responde cada pregunta de la gerencia. DIRECTA contrastará tus respuestas con la evidencia disponible.'
                        : 'Escribe una pregunta. La respuesta mostrará fuentes y páginas cuando estén disponibles.',
                        style: TextStyle(fontSize: 12, height: 1.4, color: c.text2)),
                  ])),
                ]),
              ),
            if (context.read<AppState>().modoGuia) _panelGuia(st),
            if (!context.read<AppState>().modoGuia && doc != null && st.mensajes.isEmpty) ...[
              Center(child: Column(children: [
                Container(
                  width: 54, height: 54, alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(18)),
                  child: Icon(Icons.auto_awesome, color: c.accentText, size: 25),
                ),
                const SizedBox(height: 10),
                const Text('Pregúntale al documento', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Respuestas con página y fuente. Toca una sugerencia para enviarla.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: c.text2, height: 1.4)),
                const SizedBox(height: 14),
              ])),
              for (final q in _sugerencias)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: c.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.border)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: st.consultando ? null : () => _enviarDirecto(st, q.pregunta),
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Row(children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
                            child: Icon(q.icono, size: 19, color: c.accentText),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(q.titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            const SizedBox(height: 2),
                            Text(q.detalle, style: TextStyle(fontSize: 12, color: c.text2, height: 1.3)),
                          ])),
                          Icon(Icons.north_east_rounded, size: 18, color: c.accentText),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
            for (final m in st.mensajes) m.rol == 'me' ? _Mio(m.texto) : _burbujaIA(context, st, m),
          ],
        ),
      ),
      Container(
        decoration: BoxDecoration(color: c.bg2, border: Border(top: BorderSide(color: c.border))),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: SafeArea(
          top: false,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              tooltip: 'Sugerencias',
              onPressed: doc == null || st.consultando ? null : () => _abrirSugerencias(st),
              style: IconButton.styleFrom(backgroundColor: c.accentSoft, foregroundColor: c.accentText, minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.lightbulb_outline_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _inputFocus.hasFocus ? c.accentText : c.border2),
                ),
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  // No se deshabilita mientras la IA responde: así el teclado no se cierra solo.
                  enabled: doc != null || context.read<AppState>().modoGuia,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 14.5),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    hintText: doc == null
                        ? (context.read<AppState>().modoGuia ? 'Escribe tu respuesta; se guardará en este teléfono' : 'Selecciona un documento para consultar')
                        : (context.read<AppState>().modoGuia ? 'Responde este tema…' : 'Pregunta sobre el documento…'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: context.read<AppState>().modoGuia ? 'Enviar respuesta del tema' : 'Enviar pregunta',
              onPressed: st.consultando || (doc == null && !context.read<AppState>().modoGuia) ? null : () => _enviar(st),
              style: IconButton.styleFrom(backgroundColor: Brand.accent, foregroundColor: Brand.onAccent, minimumSize: const Size(48, 48)),
              icon: st.consultando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Brand.onAccent))
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _burbujaIA(BuildContext context, AppState st, ChatMsg m) {
    final c = context.c;
    final enInforme = st.chatEnInforme(m.id);
    final tieneFuentes = m.fuentes.isNotEmpty && !m.streaming;
    final paginas = m.fuentes.map((f) => '${f['pagina'] ?? '?'}').toSet().join(', ');
    final tab = _tab[m.id] ?? 'respuesta';
    Widget cuerpo;
    if (tab == 'fuentes' && tieneFuentes) {
      cuerpo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < m.fuentes.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.surface3, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('[${i + 1}] Página ${m.fuentes[i]['pagina'] ?? '?'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 3),
              Text('${m.fuentes[i]['preview'] ?? ''}', style: TextStyle(fontSize: 12, color: c.text2)),
            ]),
          ),
      ]);
    } else if (m.streaming) {
      cuerpo = m.texto.isEmpty
          ? Row(children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Analizando el documento…', style: TextStyle(color: c.text3)),
            ])
          : Text('${m.texto}▍', style: const TextStyle(fontSize: 13.5, height: 1.5));
    } else if (m.error) {
      cuerpo = Text(m.texto, style: TextStyle(color: c.high));
    } else {
      cuerpo = MarkdownLite(m.texto);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        margin: const EdgeInsets.only(bottom: 14, right: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
          border: Border.all(color: c.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 22, height: 22, alignment: Alignment.center,
              decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.auto_awesome, size: 13, color: c.accentText),
            ),
            const SizedBox(width: 7),
            Flexible(child: Text(m.agente.isEmpty ? 'Asistente' : m.agente, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentText))),
          ]),
          if (tieneFuentes) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              ChipBtn('Respuesta', on: tab == 'respuesta', onTap: () => setState(() => _tab[m.id] = 'respuesta')),
              ChipBtn('Fuentes (${m.fuentes.length})', on: tab == 'fuentes', onTap: () => setState(() => _tab[m.id] = 'fuentes')),
            ]),
          ],
          const SizedBox(height: 8),
          cuerpo,
          if (tieneFuentes && tab != 'fuentes') ...[
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: c.border),
              ),
              child: Row(children: [
                Icon(Icons.description_outlined, size: 16, color: c.accentText),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Fuente del documento · pág. $paginas',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: c.text2),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _tab[m.id] = 'fuentes'),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), visualDensity: VisualDensity.compact),
                  child: const Text('Ver citas', style: TextStyle(fontSize: 11.5)),
                ),
              ]),
            ),
          ],
          if (!m.streaming && !m.error) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SelloVerificacion(
                verificacion: m.verificacion,
                verificando: m.verificando || st.verificandoIds.contains(m.id),
                textoOriginal: m.textoOriginal,
                onVerificar: () => st.verificarMensaje(m.id),
              ),
              Valoracion(msg: m),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: enInforme ? c.low : c.text2, padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact),
                onPressed: () => st.toggleChatEnInforme(m.id),
                icon: Icon(enInforme ? Icons.check : Icons.add, size: 16),
                label: Text(enInforme ? 'En el informe' : 'Agregar al informe', style: const TextStyle(fontSize: 12.5)),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _Mio extends StatelessWidget {
  const _Mio(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.only(bottom: 14, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Brand.accent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4)),
          ),
          child: Text(texto, style: const TextStyle(fontSize: 14, height: 1.4, color: Brand.onAccent, fontWeight: FontWeight.w500)),
        ),
      );
}

class GuiaSintesisScreen extends StatefulWidget {
  const GuiaSintesisScreen({super.key});
  @override
  State<GuiaSintesisScreen> createState() => _GuiaSintesisScreenState();
}

class _GuiaSintesisScreenState extends State<GuiaSintesisScreen> {
  late final List<TextEditingController> _responsables;
  late final List<TextEditingController> _fechas;

  @override
  void initState() {
    super.initState();
    final acuerdos = context.read<AppState>().acuerdosGuia;
    _responsables = List.generate(5, (i) => TextEditingController(text: acuerdos[i]?['responsable'] ?? ''));
    _fechas = List.generate(5, (i) => TextEditingController(text: acuerdos[i]?['fecha'] ?? ''));
  }

  @override
  void dispose() {
    for (final controller in [..._responsables, ..._fechas]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = context.c;
    final fuentes = <Map<String, dynamic>>[];
    final vistas = <String>{};
    for (final m in st.mensajes.where((m) => m.rol == 'ai')) {
      for (final f in m.fuentes) {
        final clave = '${f['documento'] ?? st.docActivo}::${f['pagina'] ?? '?'}::${f['preview'] ?? ''}';
        if (vistas.add(clave)) fuentes.add(f);
      }
    }
    final respuestas = st.respuestasGuia;

    return Scaffold(
      appBar: AppBar(title: const Text('Síntesis y seguimiento')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            const PageHead(title: 'Cinco temas revisados', subtitle: 'Separa la evidencia del documento del contexto que aportó gerencia.'),
            GgCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SecTitle('Evidencia del documento'),
                if (fuentes.isEmpty)
                  Text('La conversación todavía no tiene referencias de página.', style: TextStyle(color: c.text2, fontSize: 12.5))
                else
                  for (final f in fuentes.take(8))
                    _InfoFila(
                      titulo: '${nombreDoc(st.docActivoMap)} · pág. ${f['pagina'] ?? '?'}',
                      detalle: '${f['preview'] ?? 'Fragmento citado por el asistente.'}',
                      icon: Icons.description_outlined,
                    ),
              ]),
            ),
            GgCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SecTitle('Contexto de gerencia'),
                for (var i = 0; i < _temasGuia.length; i++)
                  if (respuestas[i] != null)
                    _InfoFila(titulo: _temasGuia[i].tema, detalle: respuestas[i]!, icon: Icons.person_outline_rounded),
              ]),
            ),
            const SecTitle('Acuerdos para seguimiento'),
            for (var i = 0; i < _temasGuia.length; i++)
              GgCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_temasGuia[i].tema, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _responsables[i],
                    decoration: const InputDecoration(labelText: 'Responsable o área'),
                    onChanged: (v) => st.guardarAcuerdoGuia(i, responsable: v, fecha: _fechas[i].text),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _fechas[i],
                    decoration: const InputDecoration(labelText: 'Fecha de seguimiento', hintText: 'dd/mm/aaaa'),
                    onChanged: (v) => st.guardarAcuerdoGuia(i, responsable: _responsables[i].text, fecha: v),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoFila extends StatelessWidget {
  const _InfoFila({required this.titulo, required this.detalle, required this.icon});
  final String titulo;
  final String detalle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: c.accentText),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(detalle, style: TextStyle(fontSize: 12, height: 1.4, color: c.text2)),
        ])),
      ]),
    );
  }
}

/// Hoja para elegir el asistente (se abre desde la barra de Análisis).
Future<void> elegirAgente(BuildContext context, AppState st) async {
    final c = context.c;
    final integ = st.agentes.where((a) => a.tipo == 'integrador').toList();
    final prod = st.agentes.where((a) => a.tipo == 'productor').toList();
    Widget op(String key, String badge, String name, String desc) => ListTile(
          leading: AgentBadge(badge),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(desc, style: TextStyle(fontSize: 12, color: c.text2)),
          trailing: st.agenteActual == key ? Icon(Icons.check, color: c.accentText) : null,
          selected: st.agenteActual == key,
          onTap: () => Navigator.pop(context, key),
        );
    Widget grp(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: SecTitle(t, bottom: 0));
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, sc) => ListView(controller: sc, children: [
          grp('General'),
          op('general', 'GEN', 'Asistente general', 'Consultas generales sobre cualquier documento.'),
          grp('Integradores'),
          for (final a in integ) op(a.key, a.badge, a.name, a.desc),
          grp('Especialistas'),
          for (final a in prod) op(a.key, a.badge, a.name, a.desc),
          const SizedBox(height: 16),
        ]),
      ),
    );
    if (r != null) st.cambiarAgente(r);
  }
