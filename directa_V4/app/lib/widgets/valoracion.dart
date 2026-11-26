import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';

/// Pulgares bajo cada respuesta (Frente C2). Si es abajo, se pide el motivo en un toque.
class Valoracion extends StatelessWidget {
  const Valoracion({super.key, required this.msg, this.documentId});
  final ChatMsg msg;
  final String? documentId;

  Future<void> _abajo(BuildContext context, AppState st) async {
    final c = context.c;
    final motivo = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('¿Qué falló en esta respuesta?', style: TextStyle(fontSize: Fs.reading, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Se guarda para mejorar al agente. Nada se aplica sin que una persona apruebe la lección.',
              style: TextStyle(fontSize: Fs.sm, color: c.text2)),
          const SizedBox(height: 12),
          for (final e in AppState.motivosValoracion.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              leading: Icon(Icons.radio_button_unchecked, color: c.text3),
              title: Text(e.value, style: const TextStyle(fontSize: Fs.body)),
              onTap: () => Navigator.pop(context, e.key),
            ),
        ]),
      ),
    );
    if (motivo != null) await st.valorar(msg, -1, motivo: motivo, documentId: documentId);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final v = st.valoraciones[msg.id];
    Widget boton(IconData icono, IconData lleno, bool activo, Color color, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: EdgeInsets.zero,
          iconSize: 20,
          onPressed: onTap,
          icon: Icon(activo ? lleno : icono, color: activo ? color : c.text3),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      boton(Icons.thumb_up_alt_outlined, Icons.thumb_up_alt, v == 1, c.low, 'Buena respuesta',
          () => st.valorar(msg, 1, documentId: documentId)),
      boton(Icons.thumb_down_alt_outlined, Icons.thumb_down_alt, v == -1, c.high, 'Mala respuesta', () => _abajo(context, st)),
    ]);
  }
}
