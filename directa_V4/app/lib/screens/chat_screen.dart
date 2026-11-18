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
  bool _modoGuia = true;
  int _ultimo = -1;
  String _ultimoTexto = '';

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    _input.text = st.borrador;
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _alFondo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _usarPreguntaEnChat(AppState st) {
    final pregunta = _temasGuia[st.guiaTemaSeleccionado].pregunta;
    setState(() => _modoGuia = false);
    _input.value = TextEditingValue(
      text: pregunta,
      selection: TextSelection.collapsed(offset: pregunta.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
    st.toast('Pregunta lista para revisar y enviar');
  }

  Future<void> _enviar(AppState st) async {
    final respuesta = _input.text.trim();
    if (respuesta.isEmpty || st.consultando) return;
    final documento = st.docActivoMap;
    if (documento == null && !_modoGuia) {
      st.toast('Selecciona un documento activo para consultar la IA', err: true);
      return;
    }

    _input.clear();
    if (!_modoGuia) {
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

  Widget _selectorModo(AppState st) {
    final c = context.c;
    Widget item(String texto, bool guia, IconData icono) => Expanded(
          child: TextButton.icon(
            onPressed: () => setState(() => _modoGuia = guia),
            icon: Icon(icono, size: 16),
            label: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis),
            style: TextButton.styleFrom(
              foregroundColor: _modoGuia == guia ? c.accentText : c.text2,
              backgroundColor: _modoGuia == guia ? c.accentSoft : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surface2, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        item('Guía de análisis', true, Icons.route_outlined),
        item('Chat libre', false, Icons.chat_bubble_outline),
      ]),
    );
  }

  Widget _panelGuia(AppState st) {
    final c = context.c;
    final seleccion = st.guiaTemaSeleccionado;
    final paso = _temasGuia[seleccion];
    final completados = st.guiaTemasCompletados;
    final respuestas = st.respuestasGuia;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
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
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: completados.length / 5, minHeight: 5, color: c.accentText, backgroundColor: c.surface3),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < _temasGuia.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_temasGuia[i].tema, style: const TextStyle(fontSize: 11)),
                    selected: seleccion == i,
                    avatar: completados.contains(i) ? Icon(Icons.check_circle, size: 15, color: c.low) : null,
                    onSelected: (_) => st.seleccionarTemaGuia(i),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Text('Pregunta del tema · responde en el campo inferior',
            style: TextStyle(fontSize: 10.5, color: c.text3, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(paso.pregunta, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35)),
        if (respuestas[seleccion] != null) ...[
          const SizedBox(height: 4),
          Text('Respuesta registrada: ${respuestas[seleccion]}',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.text3)),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: st.docActivo == null ? null : () => _usarPreguntaEnChat(st),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Usar pregunta en el chat'),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          st.docActivo == null
              ? 'Selecciona un documento para consultar esta pregunta.'
              : 'Se copiará al chat para que puedas revisarla antes de enviarla.',
          style: TextStyle(fontSize: 11, color: c.text3, height: 1.35),
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
      Container(
        padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
        decoration: BoxDecoration(color: c.bg2, border: Border(bottom: BorderSide(color: c.border))),
        child: Row(children: [
          Material(
            color: c.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.border2)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _elegirAgente(st),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AgentBadge(st.badgeAgente(st.agenteActual)),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(st.nombreAgente(st.agenteActual), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  Icon(Icons.expand_more, size: 17, color: c.text2),
                ]),
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Nueva conversación',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            onPressed: st.mensajes.isEmpty || st.consultando
                ? null
                : () async {
                    if (await confirmar(context, '¿Borrar la conversación de este documento? Lo ya agregado al informe se conserva.', ok: 'Borrar')) {
                      st.nuevaConversacion();
                    }
                  },
            icon: const Icon(Icons.add_comment_outlined, size: 19),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: _selectorModo(st),
      ),
      Expanded(
        child: ListView(
          controller: _scroll,
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
            if (st.mensajes.isEmpty)
              GgCard(
                borderColor: c.accentText.withValues(alpha: .35),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.auto_awesome_outlined, color: c.accentText, size: 21),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_modoGuia ? 'Revisa cinco temas clave' : 'Consulta el documento',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(_modoGuia
                        ? 'Responde cada pregunta de la gerencia. DIRECTA contrastará tus respuestas con la evidencia disponible.'
                        : 'Escribe una pregunta. La respuesta mostrará fuentes y páginas cuando estén disponibles.',
                        style: TextStyle(fontSize: 12, height: 1.4, color: c.text2)),
                  ])),
                ]),
              ),
            if (_modoGuia) _panelGuia(st),
            for (final m in st.mensajes) m.rol == 'me' ? _Mio(m.texto) : _burbujaIA(context, st, m),
          ],
        ),
      ),
      Container(
        decoration: BoxDecoration(color: c.bg2, border: Border(top: BorderSide(color: c.border))),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  enabled: (doc != null || _modoGuia) && !st.consultando,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _enviar(st),
                  decoration: InputDecoration(
                    hintText: doc == null
                        ? (_modoGuia ? 'Escribe tu respuesta; se guardará localmente' : 'Selecciona un documento para consultar')
                        : (_modoGuia ? 'Escribe tu respuesta para este tema…' : 'Escribe tu pregunta…'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: _modoGuia ? 'Enviar respuesta del tema' : 'Enviar pregunta',
                onPressed: st.consultando || (doc == null && !_modoGuia) ? null : () => _enviar(st),
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
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(bottom: 12, right: 24),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.agente.isEmpty ? 'Asistente' : m.agente, style: AppTheme.mono(context, size: 11, color: c.accentText)),
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
          margin: const EdgeInsets.only(bottom: 12, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(color: context.c.accentSoft, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.accent.withValues(alpha: 0.5))),
          child: Text(texto, style: const TextStyle(fontSize: 13.5)),
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
