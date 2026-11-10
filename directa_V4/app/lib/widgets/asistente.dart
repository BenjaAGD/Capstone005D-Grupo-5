import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

/// Botón flotante del asistente (Frente E2). Está en todas las pantallas salvo el chat, que ya es un chat.
class AsistenteFab extends StatelessWidget {
  const AsistenteFab({super.key, required this.pantalla});
  final String pantalla;
  @override
  Widget build(BuildContext context) => FloatingActionButton(
        heroTag: 'asistente_$pantalla',
        tooltip: 'Asistente: ayuda y preguntas al documento',
        backgroundColor: Brand.accent,
        foregroundColor: Brand.onAccent,
        onPressed: () => abrirAsistente(context, pantalla: pantalla),
        child: const Icon(Icons.support_agent),
      );
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

class _AsistenteState extends State<_Asistente> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.pestana);
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _tabs.dispose();
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
    if (_tabs.index == 0) {
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
    return Column(children: [
      const SizedBox(height: 8),
      Container(width: 40, height: 4, decoration: BoxDecoration(color: c.border2, borderRadius: BorderRadius.circular(2))),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
        child: Row(children: [
          Icon(Icons.support_agent, color: c.accentText),
          const SizedBox(width: 8),
          const Expanded(child: Text('Asistente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
      ),
      TabBar(
        controller: _tabs,
        labelColor: c.accentText,
        indicatorColor: Brand.accent,
        onTap: (_) => setState(() {}),
        tabs: const [Tab(text: 'Preguntar al documento'), Tab(text: 'Ayuda de la app')],
      ),
      Expanded(
        child: AnimatedBuilder(
          animation: _tabs,
          builder: (context, _) => _tabs.index == 0 ? _documento(context, st) : _ayuda(context, st),
        ),
      ),
      Container(
        decoration: BoxDecoration(color: c.bg2, border: Border(top: BorderSide(color: c.border))),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
                decoration: InputDecoration(hintText: _tabs.index == 0 ? 'Pregunta sobre el documento activo…' : '¿Cómo hago…?'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Enviar',
              onPressed: (st.asistenteConsultando || st.ayudaBuscando) ? null : () => _enviar(_input.text),
              style: IconButton.styleFrom(backgroundColor: Brand.accent, foregroundColor: Brand.onAccent),
              icon: const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _chips(List<String> sug) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in sug) ChipBtn(s, on: false, maxWidth: 300, onTap: () => _enviar(s)),
      ]);

  Widget _documento(BuildContext context, AppState st) {
    final c = context.c;
    final sug = _sugDocumento[widget.pantalla] ?? _sugDocumento['inicio']!;
    return ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
      if (st.asistenteMsgs.isEmpty) ...[
        Text(st.docActivo == null
            ? 'Selecciona un documento para preguntarle.'
            : 'Responde el Asistente General con el documento activo, y cada respuesta pasa por el verificador.',
            style: TextStyle(fontSize: 12.5, color: c.text2)),
        const SizedBox(height: 12),
      ],
      _chips(sug),
      const SizedBox(height: 12),
      for (final m in st.asistenteMsgs)
        m.rol == 'me'
            ? _burbuja(context, m.texto, propia: true)
            : _burbuja(
                context,
                m.texto,
                cargando: m.streaming,
                error: m.error,
                pie: m.streaming || m.error
                    ? null
                    : Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        SelloVerificacion(verificacion: m.verificacion, textoOriginal: m.textoOriginal),
                        Valoracion(msg: m, documentId: st.docActivo),
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact, foregroundColor: c.text2),
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
      _chips(sug),
      const SizedBox(height: 12),
      for (final (yo, t) in st.ayudaMsgs) _burbuja(context, t, propia: yo),
      if (st.ayudaBuscando) _burbuja(context, '', cargando: true),
    ]);
  }

  Widget _burbuja(BuildContext context, String texto, {bool propia = false, bool cargando = false, bool error = false, Widget? pie}) {
    final c = context.c;
    return Align(
      alignment: propia ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 600),
        decoration: BoxDecoration(
          color: propia ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: propia ? Brand.accent.withValues(alpha: 0.5) : c.border),
        ),
        child: cargando
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text('Buscando…', style: TextStyle(color: c.text3)),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                propia ? Text(texto, style: const TextStyle(fontSize: 13.5)) : (error
                    ? Text(texto, style: TextStyle(color: c.high, fontSize: 13))
                    : MarkdownLite(texto, size: 13.2)),
                if (pie != null) ...[const SizedBox(height: 8), pie],
              ]),
      ),
    );
  }
}

/// Atajo usado por "Más → Asistente y ayuda".
void abrirAyuda(BuildContext context, String pantalla) => abrirAsistente(context, pantalla: pantalla, pestana: 1);
