import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Guía de uso (POST /api/guia/preguntar), igual que el botón flotante del MVP.
class GuiaScreen extends StatefulWidget {
  const GuiaScreen({super.key});
  @override
  State<GuiaScreen> createState() => _GuiaScreenState();
}

class _GuiaScreenState extends State<GuiaScreen> {
  static const sug = ['¿Cómo subo un documento?', '¿Qué es el Dashboard?', '¿Para qué sirve Memoria Anual?', '¿Qué son KPI y KRI?', '¿Cómo comparo documentos?'];
  final List<(bool, String)> msgs = [];
  final _q = TextEditingController();
  bool buscando = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _preguntar(String t) async {
    t = t.trim();
    if (t.isEmpty || buscando) return;
    _q.clear();
    final st = context.read<AppState>();
    setState(() {
      msgs.add((true, t));
      buscando = true;
    });
    String r;
    try {
      final d = await st.api.postJson('/api/guia/preguntar', {'pregunta': t, 'pantalla': AppState.tabs[st.tab]});
      r = d['ok'] == true ? '${d['texto']}' : '${d['error'] ?? 'No pude responder.'}';
    } catch (_) {
      r = 'No hay conexión con el servidor.';
    }
    if (mounted) {
      setState(() {
        msgs.add((false, r));
        buscando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(title: 'Guía de uso', subtitle: 'Pregunta cómo hacer algo en DIRECTA. Responde con el manual de la app.'),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final s in sug) ChipBtn(s, on: false, onTap: () => _preguntar(s))]),
      const SizedBox(height: 12),
      for (final (yo, t) in msgs)
        Align(
          alignment: yo ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 560),
            decoration: BoxDecoration(
              color: yo ? c.accentSoft : c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: yo ? Brand.accent.withValues(alpha: 0.5) : c.border),
            ),
            child: Text(t, style: const TextStyle(fontSize: 13.5, height: 1.5)),
          ),
        ),
      if (buscando) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Buscando…', style: TextStyle(color: c.text3))),
      Row(children: [
        Expanded(child: TextField(controller: _q, onSubmitted: _preguntar, decoration: const InputDecoration(hintText: 'Escribe tu pregunta…'))),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: () => _preguntar(_q.text),
          style: IconButton.styleFrom(backgroundColor: Brand.accent, foregroundColor: Brand.onAccent),
          icon: const Icon(Icons.send_rounded),
        ),
      ]),
    ]);
  }
}
