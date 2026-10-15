import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/sev.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'ayudas.dart';

String plano(Object? t) => (t ?? '').toString().replaceAll(RegExp(r'\*\*|__'), '').replaceAll(RegExp(r'^\s*[-•*]\s+', multiLine: true), '• ');

class InformeScreen extends StatelessWidget {
  const InformeScreen({super.key});

  /// Mismo texto que resumenGeneralJS() del MVP.
  List<String> _resumen(AppState st, List<Map<String, dynamic>> activos) {
    final an = activos.where((i) => i['tipo'] == 'analisis' && i['resultado'] is Map).toList();
    if (an.isEmpty) return [];
    final conInfo = an.where((i) => tieneInfo(i['resultado'] as Map)).toList();
    if (conInfo.length <= 2) {
      return [conInfo.isEmpty
          ? 'Ninguno de los ${an.length} agentes incluidos identificó contenido sustantivo en el documento.'
          : 'Solo ${conInfo.length} de los ${an.length} agentes incluidos identificó contenido relevante para su área.'];
    }
    final partes = ['El documento fue evaluado por ${an.length} agentes; ${conInfo.length} identificaron hallazgos relevantes.'];
    final cont = {for (final s in severidades) s: 0};
    final graves = <({String sv, String k, String t})>[];
    bool integ(String k) => st.agente(k)?.tipo == 'integrador';
    var transv = 0;
    for (final i in conInfo) {
      for (final s in listaDe(i['resultado'] as Map, 'senales')) {
        final sv = normSev(s['severidad']);
        cont[sv] = cont[sv]! + 1;
        if (integ('${i['agente_key']}')) transv++;
        if ((sv == 'crítica' || sv == 'alta') && s['titulo'] != null) graves.add((sv: sv, k: '${i['agente_key']}', t: '${s['titulo']}'));
      }
    }
    final total = cont.values.fold<int>(0, (a, b) => a + b);
    if (total > 0) {
      partes.add('Se levantaron $total señales: ${severidades.where((s) => cont[s]! > 0).map((s) => '${cont[s]} ${sevPlural(s).toLowerCase()}').join(', ')}.'
          '${transv > 0 ? ' $transv de ellas son transversales (Riesgos y Estrategia cruzan hechos que otros agentes ya reportaron, por lo que pueden repetir un mismo tema).' : ''}');
    }
    graves.sort((a, b) {
      final d = severidades.indexOf(a.sv).compareTo(severidades.indexOf(b.sv));
      return d != 0 ? d : (integ(a.k) ? 1 : 0).compareTo(integ(b.k) ? 1 : 0);
    });
    if (graves.isNotEmpty) {
      partes.add('Señales de mayor severidad: ${graves.take(5).map((g) => '${st.nombreAgente(g.k)}: ${g.t} (${g.sv})').join('; ')}.');
    }
    final bajos = [for (final i in conInfo) (k: '${i['agente_key']}', s: scoreDe(i['resultado'] as Map))].where((x) => x.s < 70).toList()
      ..sort((a, b) => a.s.compareTo(b.s));
    if (bajos.isNotEmpty) {
      partes.add('Áreas que requieren más atención: ${bajos.take(3).map((b) => '${st.nombreAgente(b.k)} (${b.s}/100)').join(', ')}.');
    }
    return partes;
  }

  Future<void> _pdf(BuildContext context, AppState st) async {
    st.toast('Generando informe…');
    final bytes = await st.descargarInformePdf();
    if (bytes == null) return;
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    try {
      st.toast(await guardarArchivo('Directa_Informe_$hoy.pdf', bytes, 'application/pdf'));
    } catch (e) {
      st.toast('No se pudo guardar el PDF: $e', err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final items = st.itemsInforme;
    final activos = items.where((i) => i['excluido'] != true).toList();
    final doc = st.docActivoMap;
    int orden(Map it) => st.ordenAgente('${it['agente_key']}') * 10 + (it['tipo'] == 'analisis' ? 0 : 1);
    final ordenados = [...items]..sort((a, b) => orden(a).compareTo(orden(b)));
    final a = ayudas['informe']!;

    // vista previa
    final porAgente = <String, ({String nombre, List<Map<String, dynamic>> chats, List<Map<String, dynamic>> analisis})>{};
    for (final it in activos) {
      final k = '${it['agente_key'] ?? 'general'}';
      porAgente.putIfAbsent(k, () => (nombre: '${it['agente'] ?? st.nombreAgente(k)}', chats: [], analisis: []));
      (it['tipo'] == 'chat' ? porAgente[k]!.chats : porAgente[k]!.analisis).add(it);
    }
    final analisisIncl = activos.where((i) => i['tipo'] == 'analisis' && i['resultado'] is Map).toList();
    final gs = st.scoreGlobal({for (final i in analisisIncl) '${i['agente_key']}': Map<String, dynamic>.from(i['resultado'] as Map)});
    final gi = scoreInfo(context, gs.score);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead(
        title: 'Informe IA',
        subtitle: 'Reúne las conversaciones y análisis que quieras incluir. Al final, se descarga un PDF formal listo para el directorio.',
        actions: [
          GgButton(st.generandoPdf ? 'Generando…' : 'Descargar PDF', icon: Icons.picture_as_pdf_outlined, loading: st.generandoPdf,
              onTap: activos.isEmpty ? null : () => _pdf(context, st)),
          GgButton('Vaciar', icon: Icons.delete_outline, ghost: true,
              onTap: items.isEmpty
                  ? null
                  : () async {
                      if (await confirmar(context, '¿Vaciar los ítems del informe del documento activo?', ok: 'Vaciar')) st.limpiarInforme();
                    }),
        ],
      ),
      AyudaTile(parrafos: a.p, pasos: a.pasos),
      const BackendAviso(),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Contenidos (${activos.length} / ${items.length})', style: const TextStyle(fontWeight: FontWeight.w700))),
            GgButton('Todos', ghost: true, small: true, onTap: () => st.setTodosExcluidos(false)),
            const SizedBox(width: 6),
            GgButton('Ninguno', ghost: true, small: true, onTap: () => st.setTodosExcluidos(true)),
          ]),
          const SizedBox(height: 10),
          if (items.isEmpty)
            EmptyState(
              icon: Icons.description_outlined,
              title: 'Sin contenidos todavía',
              text: 'Cuando agregues respuestas del chat o análisis al informe, aparecerán aquí. Se guardan en este teléfono.',
              action: Wrap(spacing: 8, children: [
                GgButton('Ir al chat', icon: Icons.chat_bubble_outline, ghost: true, onTap: () => st.go('chat')),
                GgButton('Ir a Resultados', icon: Icons.insights_outlined, ghost: true, onTap: () => st.go('resultados')),
              ]),
            ),
          for (final it in ordenados)
            Opacity(
              opacity: it['excluido'] == true ? 0.5 : 1,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(4, 6, 10, 10),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Checkbox(value: it['excluido'] != true, onChanged: (_) => st.toggleExcluir(it)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        AgentBadge(st.badgeAgente('${it['agente_key']}')),
                        Text('${it['agente'] ?? st.nombreAgente('${it['agente_key']}')}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Pill(it['tipo'] == 'chat' ? 'CONVERSACIÓN' : 'ANÁLISIS', fg: c.text2, bg: c.surface3),
                      ]),
                      const SizedBox(height: 5),
                      Text(
                        it['tipo'] == 'chat'
                            ? 'P: ${it['pregunta']} — R: ${plano(it['respuesta']).replaceAll(RegExp(r'\s+'), ' ')}'
                            : plano((it['resultado'] as Map?)?['resumen_ejecutivo']).replaceAll(RegExp(r'\s+'), ' '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.3, color: c.text2),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Vista previa', style: TextStyle(fontWeight: FontWeight.w700))),
            Flexible(child: Text('El PDF final puede variar en el diseño', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: c.text3))),
          ]),
          const SizedBox(height: 12),
          if (activos.isEmpty)
            const EmptyState(icon: Icons.visibility_outlined, title: 'Vista previa', text: 'Selecciona al menos un ítem para ver el informe consolidado.')
          else ...[
            const Text('Informe de Preparación Pre-Directorio', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Documento: ${nombreDoc(doc).isEmpty ? '—' : nombreDoc(doc)}\nGenerado por DIRECTA v2 · Gerencia General',
                style: TextStyle(fontSize: 12, color: c.text3)),
            const SizedBox(height: 12),
            const Text('Resumen general', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (analisisIncl.isEmpty)
              Text('Incluye al menos un análisis para ver el resumen general (el PDF final lo genera con todos los ítems seleccionados).',
                  style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: c.text2))
            else ...[
              _Puntaje(n: gs.score, color: gi.color, titulo: 'Preparación global', label: gi.label),
              for (final p in _resumen(st, activos)) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(p, style: const TextStyle(fontSize: 12.8, height: 1.45))),
            ],
            const SizedBox(height: 8),
            const Text('Análisis por agente', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            for (final e in (porAgente.entries.toList()..sort((x, y) => st.ordenAgente(x.key).compareTo(st.ordenAgente(y.key))))) ...[
              const SizedBox(height: 10),
              Text(e.value.nombre, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.accentText)),
              for (final an in e.value.analisis) ...[
                const SizedBox(height: 6),
                Builder(builder: (context) {
                  final r = an['resultado'] as Map?;
                  final si = scoreInfo(context, scoreDe(r));
                  return _Puntaje(n: scoreDe(r), color: si.color, titulo: 'Índice de Preparación', label: si.label);
                }),
                Text(plano((an['resultado'] as Map?)?['resumen_ejecutivo']), style: const TextStyle(fontSize: 12.5, height: 1.45)),
              ],
              for (final ch in e.value.chats) ...[
                const SizedBox(height: 6),
                Text.rich(TextSpan(style: const TextStyle(fontSize: 12.5, height: 1.45), children: [
                  const TextSpan(text: 'P: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: '${ch['pregunta']}'),
                ])),
                Text.rich(TextSpan(style: const TextStyle(fontSize: 12.5, height: 1.45), children: [
                  const TextSpan(text: 'R: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: plano(ch['respuesta']).length > 300 ? '${plano(ch['respuesta']).substring(0, 300)}…' : plano(ch['respuesta'])),
                ])),
              ],
            ],
          ],
        ]),
      ),
    ]);
  }
}

class _Puntaje extends StatelessWidget {
  const _Puntaje({required this.n, required this.color, required this.titulo, required this.label});
  final int n;
  final Color color;
  final String titulo, label;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: context.c.surface2, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Text('$n', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 12),
          Expanded(child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12.5), children: [
            TextSpan(text: '$titulo\n', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: label, style: TextStyle(color: color)),
          ]))),
        ]),
      );
}
