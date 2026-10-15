import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'ayudas.dart';

class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final nDocs = st.documentos.length;
    final nChunks = st.documentos.fold<int>(0, (s, d) => s + ((d['chunks'] as num?)?.toInt() ?? 0));
    final nAnalisis = st.analisis?.length ?? 0;
    final nInforme = st.itemsInforme.length;
    final t = st.totalAgentes;

    final pasos = [
      (n: 1, t: 'Cargar documentos', d: 'Sube un PDF, Word o Excel. Se indexa y analiza automáticamente.', done: nDocs > 0,
        meta: nDocs > 0 ? '$nDocs archivo${nDocs > 1 ? 's' : ''}' : 'sin archivos', go: 'docs'),
      (n: 2, t: 'Revisar el análisis', d: 'Los $t agentes analizan el documento en segundo plano.', done: nAnalisis > 0,
        meta: nAnalisis > 0 ? '$nAnalisis/$t agentes' : 'sin análisis', go: 'resultados'),
      (n: 3, t: 'Preguntar a la IA', d: 'Consulta los hallazgos ya generados por los agentes.', done: st.mensajes.isNotEmpty,
        meta: st.mensajes.isNotEmpty ? 'conversación iniciada' : 'sin consultas', go: 'chat'),
      (n: 4, t: 'Armar el informe', d: 'Reúne lo consultado y descarga el PDF para el directorio.', done: nInforme > 0,
        meta: nInforme > 0 ? '$nInforme ítems' : 'sin ítems', go: 'informe'),
    ];
    final siguientes = pasos.where((p) => !p.done).toList();
    final a = ayudas['inicio']!;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead(
        title: 'Bienvenido al módulo de Gerencia General',
        subtitle: 'Sube un documento y el sistema lo indexa, lo analiza con $t agentes y deja todo listo para consultar.',
      ),
      AyudaTile(parrafos: a.p, pasos: a.pasos),
      const BackendAviso(),
      GridCols(cols: 2, children: [
        KpiTile(value: '$nDocs', label: 'Documentos cargados'),
        KpiTile(value: '$nChunks', label: 'Fragmentos indexados'),
        KpiTile(value: '$nAnalisis', label: 'Agentes con resultado (doc. activo)'),
        KpiTile(value: '$nInforme', label: 'Ítems en informe'),
      ]),
      const SizedBox(height: 14),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SecTitle('Pasos para la preparación'),
          for (final p in pasos)
            Builder(builder: (context) {
              final habilitado = p.done || nDocs > 0 || p.n == 1;
              return Opacity(
                opacity: habilitado ? 1 : 0.5,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: p.done ? c.low.withValues(alpha: 0.08) : c.surface2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: p.done ? c.low.withValues(alpha: 0.5) : c.border)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: habilitado ? () => st.go(p.go) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Container(
                            width: 28, height: 28, alignment: Alignment.center,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: p.done ? c.low : c.surface3),
                            child: Text(p.done ? '✓' : '${p.n}',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: p.done ? Colors.white : c.text2)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              Text(p.d, style: TextStyle(fontSize: 12, color: c.text2)),
                              const SizedBox(height: 3),
                              Text(p.meta, style: TextStyle(fontSize: 11.5, color: c.text3)),
                            ]),
                          ),
                          Icon(Icons.chevron_right, color: c.text3),
                        ]),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ]),
      ),
      siguientes.isNotEmpty
          ? GgCard(
              borderColor: Brand.accent,
              gradient: LinearGradient(colors: [c.accentSoft, c.surface], stops: const [0, 0.7]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SecTitle('Siguiente paso', color: c.accentText, bottom: 4),
                Text(siguientes.first.t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(siguientes.first.d, style: TextStyle(fontSize: 12.5, color: c.text2)),
                const SizedBox(height: 12),
                GgButton('Ir al paso', icon: Icons.play_arrow_rounded, onTap: () => st.go(siguientes.first.go)),
              ]),
            )
          : GgCard(
              borderColor: c.low,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Preparación completa', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('Todos los pasos están listos. Puedes generar el informe PDF.', style: TextStyle(fontSize: 12.5, color: c.text2)),
                const SizedBox(height: 12),
                GgButton('Ir al informe', icon: Icons.description_outlined, onTap: () => st.go('informe')),
              ]),
            ),
    ]);
  }
}
