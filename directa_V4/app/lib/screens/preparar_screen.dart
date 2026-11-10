import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/sev.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/verificacion.dart';

/// "Preparar mi reunión" (Frente E1): las preguntas probables del directorio, ordenadas por la gravedad
/// de lo que detectaron los agentes, con una respuesta sugerida para el Gerente General.
class PrepararScreen extends StatefulWidget {
  const PrepararScreen({super.key});
  @override
  State<PrepararScreen> createState() => _PrepararScreenState();
}

class _PrepararScreenState extends State<PrepararScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().cargarPreparacion());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final items = st.prepPreguntas;
    final sinSugerir = items.where((x) => x['sugerida'] == null).length;

    if (st.docActivo == null || (st.analisis == null && !st.cargandoAnalisis)) {
      return Column(children: [
        const PageHead(title: 'Preparar mi reunión'),
        GgCard(
          child: EmptyState(
            icon: Icons.event_note_outlined,
            title: 'Primero sube y analiza un documento',
            text: 'Las preguntas probables del directorio salen del análisis de los agentes.',
            action: GgButton('Ir a Documentos', icon: Icons.upload_file, onTap: () {
              Navigator.of(context).maybePop();
              st.go('docs');
            }),
          ),
        ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead(
        title: 'Preparar mi reunión',
        subtitle: 'Lo que probablemente le preguntará el directorio, de lo más grave a lo menos grave, con una respuesta sugerida.',
        actions: [
          GgButton(
            st.generandoPrep ? 'Generando…' : sinSugerir > 0 ? 'Sugerir respuestas ($sinSugerir)' : 'Respuestas listas',
            icon: Icons.auto_awesome,
            onTap: st.generandoPrep || sinSugerir == 0 ? null : st.generarRespuestasSugeridas,
          ),
          GgButton('Actualizar', icon: Icons.refresh, ghost: true, onTap: () => st.cargarPreparacion(forzar: true)),
        ],
      ),
      if (st.cargandoPrep && items.isEmpty) const GgCard(child: EmptyState(icon: Icons.hourglass_empty, title: 'Preparando…', loading: true)),
      if (st.prepSenales.isNotEmpty)
        GgCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SecTitle('Lo más grave del documento'),
            for (final sg in st.prepSenales)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 1), child: SevPill(normSev(sg['severidad']))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${sg['titulo']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(st.nombreAgente('${sg['agente']}'), style: TextStyle(fontSize: 11.5, color: c.text3)),
                        MarcaVerificacionSenal(sg),
                      ]),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      if (items.isNotEmpty) SecTitle('Preguntas probables del directorio (${items.length})'),
      for (var i = 0; i < items.length; i++) _TarjetaPregunta(n: i + 1, it: items[i]),
      if (!st.cargandoPrep && items.isEmpty)
        const GgCard(child: EmptyState(icon: Icons.check_circle_outline, title: 'Sin preguntas probables',
            text: 'Los agentes no dejaron preguntas para este documento.')),
    ]);
  }
}

class _TarjetaPregunta extends StatelessWidget {
  const _TarjetaPregunta({required this.n, required this.it});
  final int n;
  final Map<String, dynamic> it;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.read<AppState>();
    final sev = normSev(it['severidad']);
    final sug = it['sugerida'] as Map?;
    final verif = sug?['verificacion'] as Map?;
    return GgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('$n', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sevColor(context, sev))),
          const SizedBox(width: 10),
          SevPill(sev),
          const SizedBox(width: 8),
          Expanded(
            child: Text(st.nombreAgente('${it['agente']}'), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.text3)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('“${it['pregunta']}”', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.35)),
        if ('${it['motivo'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Porque el agente detectó: ${it['motivo']}', style: TextStyle(fontSize: 12, color: c.text2)),
        ],
        const SizedBox(height: 10),
        if (sug != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SecTitle('Respuesta sugerida', bottom: 4, color: c.accentText),
              MarkdownLite('${sug['respuesta'] ?? ''}', size: 13),
              if ('${sug['falta'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Falta: ${sug['falta']}', style: TextStyle(fontSize: 12, color: c.med)),
              ],
              if (verif != null) ...[
                const SizedBox(height: 8),
                Builder(builder: (context) {
                  final estado = '${verif['estado']}';
                  final col = estado == 'cifras_ok' ? c.low : estado == 'con_reservas' ? c.med : c.text3;
                  return Row(children: [
                    Icon(estado == 'cifras_ok' ? Icons.verified_outlined : estado == 'con_reservas' ? Icons.rule : Icons.help_outline,
                        size: 14, color: col),
                    const SizedBox(width: 5),
                    Expanded(child: Text('${verif['etiqueta']} · ${verif['resumen']}', style: TextStyle(fontSize: 11.5, color: col))),
                  ]);
                }),
              ],
              for (final a in (sug['alertas'] as List? ?? const []))
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $a', style: TextStyle(fontSize: 11.5, color: c.med))),
            ]),
          )
        else
          Text('Sin respuesta sugerida todavía. Usa «Sugerir respuestas» arriba o pregúntale al agente.',
              style: TextStyle(fontSize: 12, color: c.text3)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          GgButton('Preguntar al agente', icon: Icons.chat_bubble_outline, small: true, ghost: true, onTap: () {
            Navigator.of(context).maybePop();
            st.preguntarEnChat('${it['agente']}', '${it['pregunta']}');
          }),
          GgButton('Al informe', icon: Icons.add, small: true, ghost: true, onTap: () => st.prepAlInforme(it)),
        ]),
      ]),
    );
  }
}
