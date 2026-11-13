import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Lector del texto extraído e indexado, ordenado por página.
class DocumentoLecturaScreen extends StatefulWidget {
  const DocumentoLecturaScreen({
    super.key,
    required this.documentId,
    this.nombreArchivo = '',
  });

  final String documentId;
  final String nombreArchivo;

  @override
  State<DocumentoLecturaScreen> createState() => _DocumentoLecturaScreenState();
}

class _DocumentoLecturaScreenState extends State<DocumentoLecturaScreen> {
  final List<Map<String, dynamic>> _fragmentos = [];
  Map<String, dynamic>? _documento;
  int _offset = 0;
  int _total = 0;
  bool _cargando = false;
  bool _hayMas = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarMas());
  }

  Future<void> _cargarMas() async {
    if (_cargando || !_hayMas) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final st = context.read<AppState>();
      final ruta = '/api/documentos/${Uri.encodeComponent(widget.documentId)}/vista-previa?offset=$_offset&limit=12';
      final respuesta = await st.api.getJson(ruta);
      if (respuesta['ok'] != true) throw Exception('${respuesta['error'] ?? 'No se pudo leer el documento'}');
      final lista = (respuesta['fragmentos'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final doc = respuesta['documento'];
      if (!mounted) return;
      setState(() {
        if (doc is Map) _documento = Map<String, dynamic>.from(doc);
        _fragmentos.addAll(lista);
        _offset += lista.length;
        _total = (respuesta['total_fragmentos'] as num?)?.toInt() ?? _offset;
        _hayMas = _offset < _total && lista.isNotEmpty;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final titulo = (_documento?['nombre_archivo'] ?? _documento?['titulo'] ?? widget.nombreArchivo).toString();

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Leer documento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (titulo.isNotEmpty)
            Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: c.text2)),
        ]),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c.accentSoft.withValues(alpha: 0.62), c.surface.withValues(alpha: 0.72)],
                  ),
                  border: Border.all(color: c.accentText.withValues(alpha: 0.28)),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(13)),
                    child: Icon(Icons.menu_book_outlined, color: c.accentText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titulo.isEmpty ? 'Contenido del documento' : titulo,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 5),
                    Text(
                      '${_documento?['total_paginas'] ?? '—'} páginas · Texto extraído y ordenado por página',
                      style: TextStyle(fontSize: 12, height: 1.4, color: c.text2),
                    ),
                  ])),
                ]),
              ),
              const SizedBox(height: 14),
              const Text('LECTURA DEL DOCUMENTO',
                  style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_fragmentos.isEmpty && _cargando)
                const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator())),
              if (_error != null)
                GgCard(
                  borderColor: c.crit,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('No se pudo cargar el contenido', style: TextStyle(fontWeight: FontWeight.w700, color: c.crit)),
                    const SizedBox(height: 6),
                    Text(_error!, style: TextStyle(color: c.text2)),
                    Align(alignment: Alignment.centerRight, child: TextButton.icon(
                      onPressed: _cargarMas, icon: const Icon(Icons.refresh), label: const Text('Reintentar'))),
                  ]),
                ),
              if (_fragmentos.isEmpty && !_cargando && _error == null)
                const EmptyState(
                  icon: Icons.description_outlined,
                  title: 'No hay texto disponible',
                  text: 'Este documento no tiene fragmentos de texto guardados para mostrar.',
                ),
              for (var i = 0; i < _fragmentos.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface.withValues(alpha: 0.62),
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.description_outlined, size: 16, color: c.accentText),
                      const SizedBox(width: 7),
                      Text('Página ${_fragmentos[i]['page_number'] ?? '—'}',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: c.accentText)),
                    ]),
                    const SizedBox(height: 10),
                    SelectableText('${_fragmentos[i]['content'] ?? ''}',
                        style: TextStyle(fontSize: 13.5, height: 1.6, color: c.text)),
                  ]),
                ),
              if (_hayMas)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton.icon(
                    onPressed: _cargando ? null : _cargarMas,
                    icon: _cargando
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.expand_more),
                    label: Text(_cargando ? 'Cargando contenido…' : 'Cargar más contenido'),
                  ),
                ),
              if (_fragmentos.isNotEmpty && !_hayMas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: Text('Fin del contenido indexado', style: TextStyle(color: c.text3, fontSize: 12))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
