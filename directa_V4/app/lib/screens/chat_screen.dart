import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/valoracion.dart';
import '../widgets/verificacion.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, String> _tab = {};
  int _ultimo = -1;
  String _ultimoTexto = '';

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    _input.text = st.borrador;
    if (st.docActivo != null && st.sugerencias.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => st.cargarSugerencias());
    if (st.docActivo != null) WidgetsBinding.instance.addPostFrameCallback((_) => st.cargarRuta());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _alFondo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _enviar(AppState st) {
    final t = _input.text;
    _input.clear();
    st.enviarPregunta(t);
  }

  Future<void> _elegirAgente(AppState st) async {
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
      // Selector compacto para dejar espacio a los mensajes.
      Container(
        padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
        decoration: BoxDecoration(color: c.bg2, border: Border(bottom: BorderSide(color: c.border))),
        child: Row(children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: c.surface2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.border2)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _elegirAgente(st),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AgentBadge(st.badgeAgente(st.agenteActual)),
                      const SizedBox(width: 7),
                      Flexible(child: Text(st.nombreAgente(st.agenteActual), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
                      Icon(Icons.expand_more, size: 18, color: c.text2),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Nueva conversación',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            onPressed: st.mensajes.isEmpty || st.consultando
                ? null
                : () async {
                    if (await confirmar(context, '¿Borrar la conversación de este documento? Lo ya agregado al informe se conserva.',
                        ok: 'Borrar')) {
                      st.nuevaConversacion();
                    }
                  },
            icon: const Icon(Icons.add_comment_outlined, size: 19),
          ),
          IconButton(
            tooltip: 'Nuevas sugerencias',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            onPressed: () => st.cargarSugerencias(forzar: true),
            icon: const Icon(Icons.refresh, size: 19),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          children: [
            if (st.mensajes.isEmpty) ...[
              const BackendAviso(),
              if (doc == null && st.documentos.isNotEmpty)
                GgCard(
                  borderColor: c.med,
                  child: Row(children: [
                    const Expanded(child: Text('Selecciona un documento activo en Documentos o en el selector de arriba.')),
                    GgButton('Documentos', ghost: true, small: true, onTap: () => st.go('docs')),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [c.accentSoft.withValues(alpha: 0.48), c.surface.withValues(alpha: 0.38)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: c.accentText.withValues(alpha: 0.22)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: c.accentSoft.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(13)),
                          child: Icon(Icons.auto_awesome_outlined, color: c.accentText, size: 21),
                        ),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Conversa con tu asistente', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          Text('Pregunta sobre el documento activo. Puedes repreguntar y la IA mantendrá el contexto.',
                              style: TextStyle(fontSize: 12.5, height: 1.45, color: c.text2)),
                        ])),
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
      // sugerencias + entrada
      Container(
        decoration: BoxDecoration(color: c.bg2, border: Border(top: BorderSide(color: c.border))),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: SafeArea(
          top: false,
          child: Column(children: [
            if (st.agenteActual != 'general' && doc != null) const _RutaPreguntas(),
            SizedBox(
              height: 34,
              child: st.cargandoSugerencias
                  ? Row(children: [
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text('Buscando sugerencias…', style: TextStyle(fontSize: 12, color: c.text3)),
                    ])
                  : ListView(scrollDirection: Axis.horizontal, children: [
                      for (final s in st.sugerencias)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChipBtn(s, on: false, maxWidth: 250, onTap: () => _input.text = s),
                        ),
                      ChipBtn('¿De qué trata el documento?', on: true,
                          onTap: () => _input.text = '¿De qué trata el documento?'),
                    ]),
            ),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _enviar(st),
                  decoration: const InputDecoration(hintText: 'Escribe tu pregunta…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Enviar pregunta',
                onPressed: st.consultando || doc == null ? null : () => _enviar(st),
                style: IconButton.styleFrom(backgroundColor: Brand.accent, foregroundColor: Brand.onAccent),
                icon: st.consultando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Brand.onAccent))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _burbujaIA(BuildContext context, AppState st, ChatMsg m) {
    final c = context.c;
    final enInforme = st.chatEnInforme(m.id);
    final tieneFuentes = m.fuentes.isNotEmpty && !m.streaming;
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
              Text('[${i + 1}] Página ${m.fuentes[i]['pagina'] ?? '?'}'
                  '${(num.tryParse('${m.fuentes[i]['similarity']}') ?? 0) > 0 ? '  · similitud ${m.fuentes[i]['similarity']}' : ''}',
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
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(bottom: 12, right: 24),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('> ${m.agente.isEmpty ? 'Asistente' : m.agente}', style: AppTheme.mono(context, size: 11, color: c.accentText)),
          if (tieneFuentes) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              ChipBtn('Respuesta', on: tab == 'respuesta', onTap: () => setState(() => _tab[m.id] = 'respuesta')),
              ChipBtn('Fuentes (${m.fuentes.length})', on: tab == 'fuentes', onTap: () => setState(() => _tab[m.id] = 'fuentes')),
            ]),
          ],
          const SizedBox(height: 8),
          cuerpo,
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
          margin: const EdgeInsets.only(bottom: 12, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(color: context.c.accentSoft, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.accent.withValues(alpha: 0.5))),
          child: Text(texto, style: const TextStyle(fontSize: 13.5)),
        ),
      );
}

/// Ruta de preguntas guía del agente (Frente A): seis preguntas en tres niveles. La siguiente aparece
/// solo cuando la anterior tiene respuesta; las que abordan una señal grave del análisis suben primero.
class _RutaPreguntas extends StatelessWidget {
  const _RutaPreguntas();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final ruta = st.rutaActual;
    if (ruta.isEmpty) return const SizedBox.shrink();
    final hechas = st.rutaRespondidas.length + st.rutaSaltadas.length;
    final q = st.siguienteDeRuta;
    final nombre = st.nombreAgente(st.agenteActual);
    Widget marco(Widget hijo) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border2),
          ),
          child: hijo,
        );
    if (st.rutaEnCurso != null) {
      return marco(Row(children: [
        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8)),
        const SizedBox(width: 8),
        Expanded(child: Text('Ruta de $nombre: esperando la respuesta para mostrar la siguiente pregunta…',
            style: TextStyle(fontSize: 11.5, color: c.text3))),
      ]));
    }
    if (q == null) {
      return marco(Row(children: [
        Icon(Icons.flag_outlined, size: 16, color: c.low),
        const SizedBox(width: 8),
        Expanded(child: Text('Ruta de $nombre completa ($hechas de ${ruta.length}).', style: TextStyle(fontSize: 12, color: c.text2))),
        TextButton(onPressed: st.reiniciarRuta, child: const Text('Reiniciar', style: TextStyle(fontSize: 12))),
      ]));
    }
    final nivel = nivelesGuia['${q['nivel']}'] ?? '${q['nivel']}';
    final prioridad = (q['prioridad'] as num?)?.toInt() ?? 0;
    final saltable = q['puede_saltarse'] == true;
    return marco(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.route_outlined, size: 15, color: c.accentText),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Ruta de $nombre · ${hechas + 1} de ${ruta.length} · $nivel',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.accentText, letterSpacing: 0.2)),
        ),
      ]),
      const SizedBox(height: 4),
      Text('${q['pregunta']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35)),
      if (prioridad > 0 || saltable) ...[
        const SizedBox(height: 3),
        Text(prioridad > 0 ? '${q['motivo']}' : '${q['motivo_salto']}', maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.2, color: prioridad > 0 ? c.high : c.text3)),
      ],
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: () => st.saltarDeRuta('${q['id']}'), child: const Text('Saltar', style: TextStyle(fontSize: 12.5))),
        const SizedBox(width: 4),
        FilledButton.tonalIcon(
          onPressed: st.consultando ? null : () => st.preguntarDeRuta(q),
          icon: const Icon(Icons.send_rounded, size: 16),
          label: const Text('Preguntar', style: TextStyle(fontSize: 12.5)),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ]),
    ]));
  }
}
