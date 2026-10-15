import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Menú "Más": el resto de las secciones del MVP (Informe IA y las herramientas).
class MasScreen extends StatelessWidget {
  const MasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final n = st.itemsInforme.length;
    Widget item(String id, IconData ic, String t, String d, {String? badge}) => GgCard(
          onTap: () => st.go(id),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(11)),
              child: Icon(ic, color: c.accentText, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  if (badge != null) ...[const SizedBox(width: 8), Pill(badge, fg: Colors.white, bg: c.crit)],
                ]),
                const SizedBox(height: 2),
                Text(d, style: TextStyle(fontSize: 12.3, color: c.text2)),
              ]),
            ),
            Icon(Icons.chevron_right, color: c.text3),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(title: 'Más', subtitle: 'Informe para el directorio, herramientas y configuración.'),
      item('informe', Icons.description_outlined, 'Informe IA', 'Reúne todo para exportar el PDF del directorio.', badge: n > 0 ? '$n' : null),
      const SecTitle('Herramientas'),
      item('dashboard', Icons.dashboard_outlined, 'Dashboard', 'Semáforo, señales, plan de acción y comparación con lo ya analizado.'),
      item('memoria', Icons.menu_book_outlined, 'Memoria Anual', 'Checklist por capítulos de la NCG 461 con la evidencia de tus documentos.'),
      item('indicadores', Icons.speed_outlined, 'Indicadores', 'KPI, KRI y soluciones: sugeridos con lo analizado y propios que tú agregas.'),
      const SecTitle('Ayuda y configuración'),
      item('guia', Icons.support_agent, 'Guía de uso', 'Pregunta cómo hacer algo en la app.'),
      item('ajustes', Icons.settings_outlined, 'Servidor y apariencia', 'Dirección del backend, tema y tamaño de letra.'),
    ]);
  }
}
