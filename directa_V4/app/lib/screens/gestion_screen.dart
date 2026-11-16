import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Reúne las herramientas para preparar materiales e indicadores ejecutivos.
class GestionScreen extends StatelessWidget {
  const GestionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final cantidadInforme = st.itemsInforme.length;

    Widget acceso(String id, IconData icono, String titulo, String descripcion, {String? distintivo}) => GgCard(
      onTap: () => st.go(id),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
          child: Icon(icono, color: c.accentText),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            if (distintivo != null) ...[const SizedBox(width: 7), Pill(distintivo, fg: Colors.white, bg: c.accentText)],
          ]),
          const SizedBox(height: 3),
          Text(descripcion, style: TextStyle(fontSize: 12, height: 1.35, color: c.text2)),
        ])),
        Icon(Icons.chevron_right, color: c.text3),
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(
        title: 'Gestión',
        subtitle: 'Prepara materiales y revisa indicadores para la sesión del directorio.',
      ),
      const SecTitle('Informes y herramientas'),
      acceso('informe', Icons.description_outlined, 'Informe del directorio',
          'Reúne hallazgos y notas para preparar el PDF.', distintivo: cantidadInforme > 0 ? '$cantidadInforme' : null),
      acceso('dashboard', Icons.dashboard_outlined, 'Dashboard',
          'Semáforo, señales, plan de acción y comparación entre análisis.'),
      acceso('indicadores', Icons.speed_outlined, 'Indicadores',
          'Consulta KPI y KRI sugeridos y agrega los propios.'),
    ]);
  }
}
