import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'resultados_screen.dart';

/// Reúne hallazgos y consultas al asistente en una sola sección.
class AnalisisScreen extends StatelessWidget {
  const AnalisisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = context.c;
    final seleccion = st.analisisPestana;
    final consultando = seleccion == 1;

    Widget opcion(String texto, int indice, IconData icono) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: TextButton.icon(
          onPressed: () => st.seleccionarAnalisis(indice),
          icon: Icon(icono, size: 17),
          label: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: TextButton.styleFrom(
            foregroundColor: seleccion == indice ? c.accentText : c.text2,
            backgroundColor: seleccion == indice ? c.accentSoft : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );

    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, consultando ? 8 : 14, 16, consultando ? 6 : 10),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!consultando)
              const PageHead(title: 'Análisis', subtitle: 'Revisa los hallazgos de la IA o consulta sobre el documento activo.'),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: c.surface2, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(13)),
              child: Row(children: [
                opcion('Hallazgos', 0, Icons.insights_outlined),
                opcion('Consultar a la IA', 1, Icons.chat_bubble_outline),
              ]),
            ),
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
