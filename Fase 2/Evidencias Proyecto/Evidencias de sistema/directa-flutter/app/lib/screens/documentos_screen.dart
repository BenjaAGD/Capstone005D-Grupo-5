import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'ayudas.dart';

class DocumentosScreen extends StatelessWidget {
  const DocumentosScreen({super.key});

  Future<void> _elegir(BuildContext context) async {
    final st = context.read<AppState>();
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'docx', 'doc', 'xlsx', 'xls']);
    if (f == null) return;
    final bytes = await f.xFile.readAsBytes();
    await st.subirArchivo(f.name, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final a = ayudas['docs']!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead(
        title: 'Documentos',
        subtitle: 'Sube un PDF, Word o Excel. Se indexa y analiza con los ${st.totalAgentes} agentes automáticamente. Cuando termine, podrás consultarlo.',
      ),
      AyudaTile(parrafos: a.p, pasos: a.pasos),
      const BackendAviso(),
      GgCard(
        child: Column(children: [
          Material(
            color: c.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.border2)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: st.subiendo ? null : () => _elegir(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(children: [
                  Icon(Icons.upload_file, size: 34, color: c.accentText),
                  const SizedBox(height: 8),
                  const Text('Subir un documento', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const SizedBox(height: 4),
                  Text('PDF, Word o Excel · análisis automático al terminar la indexación',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.text2)),
                ]),
              ),
            ),
          ),
          if (st.subiendo && st.progreso != null) _Progreso(p: st.progreso!, nombre: st.subiendoNombre, total: st.totalAgentes),
        ]),
      ),
      GgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SecTitle('Documentos cargados (${st.documentos.length})'),
          if (st.documentos.isEmpty)
            const EmptyState(icon: Icons.description_outlined, title: 'Aún no hay documentos',
                text: 'Sube el primer archivo para empezar. Se indexará y analizará automáticamente.')
          else
            for (final d in st.documentos) _DocRow(d: d),
        ]),
      ),
    ]);
  }
}

class _Progreso extends StatelessWidget {
  const _Progreso({required this.p, required this.nombre, required this.total});
  final Map<String, dynamic> p;
  final String nombre;
  final int total;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tot = (p['total'] as num?)?.toInt() ?? 0;
    final proc = (p['procesados'] as num?)?.toInt() ?? 0;
    final pct = tot > 0 ? (100 * proc / tot).round() : 3;
    final restante = (p['estimado_seg'] as num?) ?? 0;
    final fase = switch (p['fase']) {
      'embeddings' => 'Indexando documento',
      'analisis' => 'Analizando con $total agentes',
      'listo' => 'Listo',
      _ => '${p['estado'] ?? 'Procesando'}',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(children: [
        ScoreRing(value: pct, color: Brand.accent, caption: '%', size: 60),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(fase, style: TextStyle(fontSize: 12.5, color: c.text2)),
          ]),
        ),
        Text(restante > 0 ? '~${formatTiempo(restante)}' : '…', style: TextStyle(fontSize: 12, color: c.text3)),
      ]),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.d});
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final estado = '${d['estado'] ?? '—'}';
    final color = switch (estado) {
      'Listo' => c.low,
      'Listo con errores' => c.med,
      'Analizando' || 'Procesando' || 'Iniciando' => c.accentText,
      'Error' => c.crit,
      _ => c.text3,
    };
    final id = '${d['id']}';
    final activo = st.docActivo == id;
    final nAn = (d['analisis_count'] as num?)?.toInt() ?? 0;
    final procesando = estadosProcesando.contains(estado);
    final incompleto = !procesando && estado != 'Error' && nAn < st.totalAgentes;
    final nombre = (d['nombre_archivo'] ?? d['titulo'] ?? '').toString();
    final ext = nombre.contains('.') ? nombre.split('.').last.toUpperCase() : 'DOC';
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 6),
      decoration: BoxDecoration(
        color: activo ? c.accentSoft : c.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: activo ? Brand.accent : c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 38, alignment: Alignment.center,
            decoration: BoxDecoration(color: c.surface3, borderRadius: BorderRadius.circular(9)),
            child: Text(ext.length > 4 ? ext.substring(0, 4) : ext,
                style: AppTheme.mono(context, size: 10, color: c.text2, weight: FontWeight.w700)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombreDoc(d).isEmpty ? '(sin título)' : nombreDoc(d), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 3),
              Text.rich(TextSpan(style: TextStyle(fontSize: 11.8, color: c.text3), children: [
                TextSpan(text: '${d['total_paginas'] ?? '?'} páginas · ${d['chunks'] ?? 0} fragmentos · $nAn/${st.totalAgentes} agentes'),
                if (activo) TextSpan(text: ' · activo', style: TextStyle(color: c.accentText)),
                if (incompleto) TextSpan(text: ' · análisis incompleto', style: TextStyle(color: c.med)),
              ])),
              const SizedBox(height: 6),
              Pill(estado, fg: color, dot: true),
            ]),
          ),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(tooltip: 'Marcar como activo', icon: Icon(Icons.check_circle_outline, color: activo ? c.accentText : c.text2),
              onPressed: () async {
                if (await st.cambiarDocumento(id)) st.toast('Documento activado');
              }),
          IconButton(tooltip: 'Preguntar sobre este documento', icon: Icon(Icons.chat_bubble_outline, color: c.text2),
              onPressed: () async {
                if (await st.cambiarDocumento(id)) {
                  st.go('chat');
                  st.cargarSugerencias();
                }
              }),
          IconButton(tooltip: 'Ver resultados', icon: Icon(Icons.insights_outlined, color: c.text2),
              onPressed: () async {
                if (await st.cambiarDocumento(id)) st.go('resultados');
              }),
          IconButton(tooltip: 'Eliminar', icon: Icon(Icons.delete_outline, color: c.crit),
              onPressed: () async {
                if (await confirmar(context, '¿Eliminar este documento, sus fragmentos y sus análisis?', ok: 'Eliminar')) {
                  await st.eliminarDocumento(id);
                }
              }),
        ]),
      ]),
    );
  }
}
