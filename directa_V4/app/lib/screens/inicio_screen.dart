import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'documento_lectura_screen.dart';

/// Inicio enfocado en cargar, recordar y analizar documentos.
class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  Future<void> _elegirDocumento(BuildContext context) async {
    final st = context.read<AppState>();
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'doc', 'xlsx', 'xls'],
    );
    if (f == null) return;
    final bytes = await f.xFile.readAsBytes();
    await st.subirArchivo(f.name, bytes);
  }

  Future<void> _pdfDirecto(BuildContext context, AppState st) async {
    final bytes = await st.informeDirecto();
    if (bytes == null) return;
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    st.toast(await guardarArchivo('Directa_Informe_$hoy.pdf', bytes, 'application/pdf'));
  }

  void _abrirDocumento(BuildContext context, Map<String, dynamic> doc) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DocumentoLecturaScreen(
        documentId: '${doc['id']}',
        nombreArchivo: nombreDoc(doc),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final doc = st.docActivoMap;
    final nAnalisis = st.analisis?.length ?? 0;
    final procesando = doc != null && estadosProcesando.contains(doc['estado']);
    final nombre = doc == null ? '' : nombreDoc(doc);
    final extension = nombre.contains('.') ? nombre.split('.').last.toUpperCase() : 'DOC';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(
        title: 'Gerencia General',
        subtitle: 'Carga documentos, revisa el análisis de IA y prepara información para el directorio.',
      ),
      const BackendAviso(),
      GgCard(
        borderColor: Brand.accent,
        gradient: LinearGradient(colors: [c.accentSoft, c.surface], stops: const [0, 0.8]),
        onTap: st.subiendo ? null : () => _elegirDocumento(context),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: Brand.accent, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.upload_file, color: Brand.onAccent),
          ),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(st.subiendo ? 'Cargando documento…' : 'Cargar documento para analizar',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 3),
            Text('PDF, Word o Excel. La IA lo indexa y revisa con los agentes.',
                style: TextStyle(fontSize: 12, color: c.text2, height: 1.35)),
            if (st.subiendo && st.progreso != null) ...[
              const SizedBox(height: 9),
              const LinearProgressIndicator(),
            ],
          ])),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: c.text3),
        ]),
      ),
      const SecTitle('Documento de trabajo'),
      if (doc == null)
        GgCard(
          child: Row(children: [
            Icon(Icons.description_outlined, color: c.text3, size: 25),
            const SizedBox(width: 12),
            Expanded(child: Text('Todavía no hay un documento activo. Carga uno para comenzar.',
                style: TextStyle(color: c.text2, height: 1.4))),
            TextButton(onPressed: () => st.go('documentos'), child: const Text('Ver lista')),
          ]),
        )
      else
        GgCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(11)),
                child: Text(extension.length > 4 ? extension.substring(0, 4) : extension,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: c.accentText)),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre.isEmpty ? 'Documento sin nombre' : nombre, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text('${doc['total_paginas'] ?? '—'} páginas · ${doc['analisis_count'] ?? 0}/${st.totalAgentes} agentes',
                    style: TextStyle(fontSize: 11.5, color: c.text3)),
              ])),
              Pill('${doc['estado'] ?? 'Sin estado'}', fg: procesando ? c.accentText : c.low, dot: true),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              TextButton.icon(
                onPressed: () => _abrirDocumento(context, doc),
                icon: const Icon(Icons.menu_book_outlined, size: 17),
                label: const Text('Leer documento'),
              ),
              TextButton.icon(
                onPressed: () => st.go('documentos'),
                icon: const Icon(Icons.folder_open_outlined, size: 17),
                label: const Text('Ver documentos'),
              ),
            ]),
          ]),
        ),
      GgCard(
        onTap: () => st.go('resultados'),
        child: Row(children: [
          Icon(procesando ? Icons.hourglass_top : Icons.manage_search, color: c.accentText, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(procesando ? 'Análisis en curso' : 'Revisar análisis y consultar a la IA',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 3),
            Text(procesando ? 'Los agentes están trabajando en el documento.' : '$nAnalisis agentes con resultados · hallazgos y chat en un mismo lugar.',
                style: TextStyle(fontSize: 12, color: c.text2)),
          ])),
          Icon(Icons.chevron_right, color: c.text3),
        ]),
      ),
      const SecTitle('Accesos rápidos'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => st.go('memoria'), icon: const Icon(Icons.menu_book_outlined), label: const Text('Memoria Anual')),
        OutlinedButton.icon(onPressed: () => st.go('informe'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Informe del directorio')),
        if (nAnalisis > 0)
          OutlinedButton.icon(
            onPressed: st.generandoPdf ? null : () => _pdfDirecto(context, st),
            icon: st.generandoPdf
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined),
            label: const Text('Exportar análisis'),
          ),
      ]),
    ]);
  }
}
