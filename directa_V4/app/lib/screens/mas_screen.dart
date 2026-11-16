import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Acciones de apoyo y configuración menos frecuentes.
class MasScreen extends StatelessWidget {
  const MasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    Widget item(String id, IconData ic, String t, String d) => GgCard(
      onTap: () => st.go(id),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(11)),
          child: Icon(ic, color: c.accentText, size: 21),
        ),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text(d, style: TextStyle(fontSize: 12.3, color: c.text2)),
        ])),
        Icon(Icons.chevron_right, color: c.text3),
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(title: 'Más', subtitle: 'Preparación, aprendizaje y configuración de la aplicación.'),
      item('preparar', Icons.event_note_outlined, 'Preparar mi reunión', 'Anticipa preguntas y temas para el directorio.'),
      item('aprendizaje', Icons.school_outlined, 'Aprendizaje de los agentes', 'Revisa valoraciones y lecciones de los agentes.'),
      const SecTitle('Ayuda y configuración'),
      item('guia', Icons.support_agent, 'Guía de uso', 'Pregunta cómo hacer algo en la aplicación.'),
      item('ajustes', Icons.settings_outlined, 'Servidor y apariencia', 'Dirección del backend, tema y tamaño de letra.'),
    ]);
  }
}
