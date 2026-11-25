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
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );

    // En el chat con el teclado abierto se oculta el selector de sección para dejar sitio al campo de texto.
    return LayoutBuilder(builder: (context, box) {
      final ocultarSelector = consultando && box.maxHeight < 420;
      return Column(children: [
      if (!ocultarSelector) Padding(
        padding: EdgeInsets.fromLTRB(16, consultando ? 8 : 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!consultando)
              const PageHead(title: 'Análisis', subtitle: 'Revisa hallazgos y trabaja cinco temas clave con la guía de DIRECTA.'),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: c.surface2, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(13)),
              child: Row(children: [
                opcion('Hallazgos', 0, Icons.insights_outlined),
                opcion('Guía y Chat', 1, Icons.chat_bubble_outline),
              ]),
            ),
          ]),
      ),
      Expanded(child: IndexedStack(
        index: seleccion,
        children: [
          const SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 8, 16, 96),
              child: ResultadosScreen(),
            ),
          ),
          const ChatScreen(),
        ],
      )),
    ]);
    });
  }
}
