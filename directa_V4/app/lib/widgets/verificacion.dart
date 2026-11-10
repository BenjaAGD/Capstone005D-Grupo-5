import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'common.dart';

/// Sello de confianza del verificador (Frente B): Verificada · Con reservas · No verificable.
/// Al tocarlo se ve, afirmación por afirmación, el fragmento del documento que la respalda.
class SelloVerificacion extends StatelessWidget {
  const SelloVerificacion({super.key, this.verificacion, this.verificando = false, this.textoOriginal, this.onVerificar});
  final Map<String, dynamic>? verificacion;
  final bool verificando;
  final String? textoOriginal;
  final VoidCallback? onVerificar;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (verificando) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8)),
        const SizedBox(width: 6),
        Text('Verificando con el documento…', style: TextStyle(fontSize: 11.5, color: c.text3)),
      ]);
    }
    final v = verificacion;
    if (v == null) {
      if (onVerificar == null) return const SizedBox.shrink();
      return TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: c.text2, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
        onPressed: onVerificar,
        icon: const Icon(Icons.fact_check_outlined, size: 16),
        label: const Text('Verificar con el documento', style: TextStyle(fontSize: 12)),
      );
    }
    final info = selloInfo(context, '${v['estado'] ?? ''}');
    return Material(
      color: info.color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: info.color.withValues(alpha: 0.45))),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => mostrarDetalleVerificacion(context, v, textoOriginal: textoOriginal),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(info.icon, size: 15, color: info.color),
            const SizedBox(width: 5),
            Text('${v['etiqueta'] ?? info.label}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: info.color)),
            if (textoOriginal != null) ...[
              const SizedBox(width: 6),
              Text('· corregida', style: TextStyle(fontSize: 11, color: info.color)),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 15, color: info.color),
          ]),
        ),
      ),
    );
  }
}

({Color color, IconData icon, String label}) selloInfo(BuildContext context, String estado) {
  final c = context.c;
  return switch (estado) {
    'verificada' => (color: c.low, icon: Icons.verified_outlined, label: 'Verificada'),
    'con_reservas' => (color: c.med, icon: Icons.rule, label: 'Con reservas'),
    _ => (color: c.text3, icon: Icons.help_outline, label: 'No verificable'),
  };
}

({Color color, String label}) estadoAfirmacion(BuildContext context, String estado) {
  final c = context.c;
  return switch (estado) {
    'respaldada' => (color: c.low, label: 'Respaldada'),
    'parcial' => (color: c.med, label: 'Parcial'),
    'corregida' => (color: c.info, label: 'Corregida'),
    'eliminada' => (color: c.text3, label: 'Eliminada'),
    'contradicha' => (color: c.crit, label: 'Contradicha'),
    _ => (color: c.high, label: 'Sin respaldo'),
  };
}

const _revisores = {'cifras': 'Cifras', 'evidencia': 'Evidencia', 'periodo': 'Período y alcance'};

Future<void> mostrarDetalleVerificacion(BuildContext context, Map<String, dynamic> v, {String? textoOriginal}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 680),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, sc) {
        final c = context.c;
        final info = selloInfo(context, '${v['estado'] ?? ''}');
        final afirm = [for (final a in (v['afirmaciones'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
        final problemas = [
          for (final p in ((v['capa1'] as Map?)?['problemas'] as List? ?? const []))
            if (p is Map && p['gravedad'] != 'baja') Map<String, dynamic>.from(p)
        ];
        return ListView(controller: sc, padding: const EdgeInsets.fromLTRB(18, 18, 18, 28), children: [
          Row(children: [
            Icon(info.icon, color: info.color),
            const SizedBox(width: 8),
            Text('${v['etiqueta'] ?? info.label}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: info.color)),
          ]),
          const SizedBox(height: 6),
          Text('${v['resumen'] ?? ''}', style: TextStyle(fontSize: 13, color: c.text2)),
          if (v['motivo'] != null) ...[
            const SizedBox(height: 6),
            Text('${v['motivo']}', style: TextStyle(fontSize: 12, color: c.text3)),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
            child: Text(
              'El verificador comprueba que la respuesta sea fiel al documento (cifras, citas y período). '
              'No comprueba que el documento sea cierto.'
              '${v['mismo_modelo'] == true ? ' Esta vez lo revisó el mismo modelo que escribió la respuesta, porque el otro no respondió.' : ''}',
              style: TextStyle(fontSize: 11.8, color: c.text2, height: 1.4),
            ),
          ),
          if (textoOriginal != null) ...[
            const SizedBox(height: 14),
            const SecTitle('Respuesta original (antes de la corrección)'),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.surface3, borderRadius: BorderRadius.circular(10)),
              child: Text(textoOriginal, style: TextStyle(fontSize: 12.3, color: c.text2, height: 1.45)),
            ),
          ],
          const SizedBox(height: 14),
          SecTitle('Afirmaciones revisadas (${afirm.length})'),
          if (afirm.isEmpty) Text('No hay afirmaciones revisadas.', style: TextStyle(color: c.text3)),
          for (final a in afirm)
            Builder(builder: (context) {
              final e = estadoAfirmacion(context, '${a['estado_final'] ?? a['estado'] ?? ''}');
              return SigRow(
                color: e.color,
                title: '${a['texto'] ?? ''}',
                body: [
                  if ((a['cita'] ?? '').toString().isNotEmpty) 'Documento${a['pagina'] != null ? ' (pág. ${a['pagina']})' : ''}: «${a['cita']}»',
                  if ((a['correccion'] ?? '').toString().isNotEmpty && a['estado'] != 'respaldada') 'Según el documento: ${a['correccion']}',
                ].join('\n'),
                footer: Wrap(spacing: 8, children: [
                  Pill(e.label, fg: e.color, dot: true),
                  Text(_revisores['${a['revisor']}'] ?? '', style: TextStyle(fontSize: 11.5, color: c.text3)),
                ]),
              );
            }),
          if (problemas.isNotEmpty) ...[
            const SizedBox(height: 10),
            const SecTitle('Comprobaciones automáticas'),
            for (final p in problemas)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: p['gravedad'] == 'alta' ? c.high : c.med),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${p['detalle']}', style: TextStyle(fontSize: 12, color: c.text2))),
                ]),
              ),
          ],
        ]);
      },
    ),
  );
}

/// Marca pequeña para una señal del análisis que pasó por el verificador.
class MarcaVerificacionSenal extends StatelessWidget {
  const MarcaVerificacionSenal(this.senal, {super.key});
  final Map<String, dynamic> senal;
  @override
  Widget build(BuildContext context) {
    final v = senal['verificacion'];
    if (v is! Map) return const SizedBox.shrink();
    final estado = '${v['estado'] ?? ''}';
    final e = switch (estado) {
      'respaldada' => (color: context.c.low, label: 'Verificada', icon: Icons.verified_outlined),
      'parcial' => (color: context.c.med, label: 'Con reservas', icon: Icons.rule),
      'contradicha' => (color: context.c.crit, label: 'El documento la contradice', icon: Icons.report_outlined),
      'no_respaldada' => (color: context.c.high, label: 'Sin respaldo', icon: Icons.help_outline),
      _ => (color: context.c.text3, label: 'No verificable', icon: Icons.help_outline),
    };
    final tip = [
      if ((v['nota'] ?? '').toString().isNotEmpty) '${v['nota']}',
      if ((v['cita'] ?? '').toString().isNotEmpty) 'Documento${v['pagina'] != null ? ' (pág. ${v['pagina']})' : ''}: «${v['cita']}»',
      if (senal['severidad_original'] != null) 'Severidad original: ${senal['severidad_original']}.',
    ].join('\n');
    return Tooltip(
      message: tip.isEmpty ? e.label : tip,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(e.icon, size: 14, color: e.color),
        const SizedBox(width: 3),
        Text(e.label, style: TextStyle(fontSize: 11.2, color: e.color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
