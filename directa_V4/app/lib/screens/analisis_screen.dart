import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'resultados_screen.dart';

/// Reúne hallazgos y la guía conversacional de análisis en una sola sección.
class AnalisisScreen extends StatelessWidget {
  const AnalisisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = context.c;
    final seleccion = st.analisisPestana;
    final seccion = st.seccionAnalisis;
    final consultando = seleccion == 1;

    Widget opcion(String texto, int indice) => Expanded(
      child: TextButton(
        onPressed: () => st.irSeccionAnalisis(indice),
        style: TextButton.styleFrom(
          foregroundColor: seccion == indice ? c.accentText : c.text2,
          backgroundColor: seccion == indice ? c.accentSoft : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          minimumSize: const Size(0, 38),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, fontWeight: seccion == indice ? FontWeight.w700 : FontWeight.w500)),
      ),
    );

    // Botón chico del asistente (solo en Guía y Chat): muestra la sigla y abre la lista.
    Widget asistente() => Tooltip(
      message: st.nombreAgente(st.agenteActual),
      child: Material(
        color: c.surface2,
        shape: StadiumBorder(side: BorderSide(color: c.border2)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => elegirAgente(context, st),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AgentBadge(st.badgeAgente(st.agenteActual)),
              Icon(Icons.expand_more, size: 16, color: c.text2),
            ]),
          ),
        ),
      ),
    );

    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, consultando ? 8 : 14, 12, consultando ? 6 : 10),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!consultando)
              const PageHead(title: 'Análisis', subtitle: 'Revisa hallazgos y trabaja cinco temas clave con la guía de DIRECTA.'),
            Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: c.surface2, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    opcion('Hallazgos', 0),
                    opcion('Guía', 1),
                    opcion('Chat', 2),
                  ]),
                ),
              ),
              if (consultando) ...[
                const SizedBox(width: 8),
                asistente(),
                if (seccion == 2 && st.mensajes.isNotEmpty)
                  IconButton(
                    tooltip: 'Nueva conversación',
                    visualDensity: VisualDensity.compact,
                    onPressed: st.consultando
                        ? null
                        : () async {
                            if (await confirmar(context, '¿Borrar la conversación de este documento? Lo ya agregado al informe se conserva.', ok: 'Borrar')) {
                              st.nuevaConversacion();
                            }
                          },
                    icon: const Icon(Icons.add_comment_outlined, size: 19),
                  ),
              ],
            ]),
          ]),
        )),
      ),
      Expanded(child: IndexedStack(
        index: seleccion,
        children: [
          SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: const ResultadosScreen(),
            )),
          ),
          const ChatScreen(),
        ],
      )),
    ]);
  }
}
