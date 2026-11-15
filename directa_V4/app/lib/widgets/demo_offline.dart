import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'common.dart';

/// Aviso visible para separar datos ilustrativos de información real del cliente.
class DemoAviso extends StatelessWidget {
  const DemoAviso({super.key, this.text = 'Contenido de ejemplo para revisar la pantalla. No corresponde a información real ni se incluirá en informes.'});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GgCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderColor: c.info.withValues(alpha: .55),
      color: c.info.withValues(alpha: .08),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.visibility_outlined, color: c.info, size: 20),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Modo demostración', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            Pill('EJEMPLO', fg: c.info),
          ]),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(fontSize: 12, height: 1.4, color: c.text2)),
        ])),
      ]),
    );
  }
}

class DemoDato extends StatelessWidget {
  const DemoDato({super.key, required this.valor, required this.titulo, this.detalle});
  final String valor, titulo;
  final String? detalle;
  @override
  Widget build(BuildContext context) => GgCard(
    margin: EdgeInsets.zero,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(valor, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: context.c.text)),
      const SizedBox(height: 5),
      Text(titulo, style: TextStyle(fontSize: 12, color: context.c.text2)),
      if (detalle != null) ...[const SizedBox(height: 4), Text(detalle!, style: TextStyle(fontSize: 10.5, color: context.c.text3))],
    ]),
  );
}

class DemoFila extends StatelessWidget {
  const DemoFila({super.key, required this.titulo, required this.detalle, this.icon = Icons.arrow_outward, this.color});
  final String titulo, detalle;
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color ?? c.accentText, size: 18),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(detalle, style: TextStyle(fontSize: 12, height: 1.4, color: c.text2)),
        ])),
      ]),
    );
  }
}
