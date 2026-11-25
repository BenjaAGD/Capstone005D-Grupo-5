import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';

import '../core/saver.dart';
import '../core/theme.dart';
import '../state/app_state.dart';

/// Visor de PDF dentro de DIRECTA para los archivos generados (memoria, informes, dashboard…):
/// página completa, pellizcar para ampliar, deslizar o flechas para cambiar de página.
class VisorPdfScreen extends StatefulWidget {
  const VisorPdfScreen({super.key, required this.archivo});
  final ArchivoGuardado archivo;

  /// Abre el visor si es PDF; cualquier otro tipo (Excel) se abre con la app del teléfono.
  static Future<void> abrir(BuildContext context, ArchivoGuardado archivo) async {
    if (!archivo.nombre.toLowerCase().endsWith('.pdf')) {
      await abrirArchivoGuardado(archivo);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VisorPdfScreen(archivo: archivo)));
  }

  @override
  State<VisorPdfScreen> createState() => _VisorPdfScreenState();
}

class _VisorPdfScreenState extends State<VisorPdfScreen> {
  PdfControllerPinch? _ctrl;
  String? _error;
  int _pagina = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final Uint8List bytes = await leerArchivoGuardado(widget.archivo);
      if (!mounted) return;
      setState(() => _ctrl = PdfControllerPinch(document: PdfDocument.openData(bytes)));
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo abrir el PDF dentro de la app.');
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _compartir() async {
    try {
      await compartirArchivoGuardado(widget.archivo);
    } catch (_) {
      if (mounted) context.read<AppState>().toast('No se pudo compartir el archivo', err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ctrl = _ctrl;
    return Scaffold(
      backgroundColor: const Color(0xFF4E5662),
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.archivo.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Fs.lg, fontWeight: FontWeight.w700)),
          if (_total > 0) Text('Página $_pagina de $_total', style: TextStyle(fontSize: Fs.sm, color: c.text2)),
        ]),
        actions: [
          IconButton(tooltip: 'Compartir', onPressed: _compartir, icon: const Icon(Icons.ios_share_outlined)),
          IconButton(
            tooltip: 'Abrir con otra app',
            onPressed: () => abrirArchivoGuardado(widget.archivo),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 12),
                  FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(48, 48)), onPressed: () => abrirArchivoGuardado(widget.archivo), child: const Text('Abrir con otra app')),
                ]),
              ),
            )
          : ctrl == null
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : PdfViewPinch(
                  controller: ctrl,
                  onDocumentLoaded: (doc) => setState(() => _total = doc.pagesCount),
                  onPageChanged: (p) => setState(() => _pagina = p),
                  onDocumentError: (_) => setState(() => _error = 'Este PDF no se pudo mostrar.'),
                ),
      bottomNavigationBar: ctrl == null || _total == 0
          ? null
          : Container(
              color: c.bg2,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: SafeArea(
                top: false,
                child: Row(children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _pagina > 1 ? () => ctrl.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut) : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Anterior'),
                  ),
                  Expanded(child: Text('$_pagina / $_total', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                  TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _pagina < _total ? () => ctrl.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut) : null,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Siguiente'),
                  ),
                ]),
              ),
            ),
    );
  }
}
