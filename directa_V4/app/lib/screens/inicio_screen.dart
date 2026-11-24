import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/saver.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'documento_lectura_screen.dart';

/// Inicio: subir documentos, ver cómo avanza su análisis y elegir cuál usar.
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

  String _extension(String nombre) {
    final e = nombre.contains('.') ? nombre.split('.').last.toUpperCase() : 'DOC';
    return e.length > 4 ? e.substring(0, 4) : e;
  }

  Widget _insignia(BuildContext context, String nombre, {bool activo = true}) {
    final c = context.c;
    return Container(
      width: 44, height: 44, alignment: Alignment.center,
      decoration: BoxDecoration(color: c.surface3, borderRadius: BorderRadius.circular(11)),
      child: Text(_extension(nombre),
          style: AppTheme.mono(context, size: 10, weight: FontWeight.w700, color: activo ? c.accentText : c.text3)),
    );
  }

  /// Tres tramos: Subido · Indexando · Agentes.
  Widget _tramos(BuildContext context, {required double indexado, required double agentes, required String textoAgentes}) {
    final c = context.c;
    Widget tramo(double v, Color color) => Expanded(child: GgBar(value: v, color: color, height: 6));
    final indexando = indexado < 1;
    return Column(children: [
      Row(children: [
        tramo(1, c.low),
        const SizedBox(width: 6),
        tramo(indexado, Brand.accent),
        const SizedBox(width: 6),
        tramo(agentes, c.low),
      ]),
      const SizedBox(height: 7),
      Row(children: [
        Expanded(child: Text('Subido', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.low))),
        Expanded(
          child: Text('Indexando', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: indexando ? c.accentText : c.low)),
        ),
        Expanded(child: Text(textoAgentes, textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: c.text3))),
      ]),
    ]);
  }

  Widget _tarjetaProceso(BuildContext context, {required String nombre, required String detalle, required int pct,
      required double indexado, required double agentes, required String textoAgentes}) {
    final c = context.c;
    return GgCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _insignia(context, nombre),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(detalle, style: TextStyle(fontSize: 12, color: c.text2)),
            ]),
          ),
          const SizedBox(width: 8),
          Pill('$pct%', fg: c.accentText),
        ]),
        const SizedBox(height: 14),
        _tramos(context, indexado: indexado, agentes: agentes, textoAgentes: textoAgentes),
      ]),
    );
  }

  /// Documentos que se están subiendo o analizando ahora mismo.
  List<Widget> _enProceso(BuildContext context, AppState st) {
    final total = st.totalAgentes;
    final tarjetas = <Widget>[];
    final nombreSubida = st.subiendoNombre;
    if (st.subiendo && st.progreso != null) {
      final p = st.progreso!;
      final tot = (p['total'] as num?)?.toInt() ?? 0;
      final proc = (p['procesados'] as num?)?.toInt() ?? 0;
      final fase = '${p['fase']}';
      final enAnalisis = fase == 'analisis';
      final frac = tot > 0 ? (proc / tot).clamp(0.0, 1.0).toDouble() : 0.03;
      tarjetas.add(_tarjetaProceso(
        context,
        nombre: nombreSubida.isEmpty ? 'Documento' : nombreSubida,
        detalle: '${enAnalisis ? 'Analizando · $proc de $tot agentes' : (tot > 0 ? 'Indexando · página $proc de $tot' : 'Preparando el documento…')}'
            '${((p['estimado_seg'] as num?) ?? 0) > 0 ? ' · faltan ~${formatTiempo((p['estimado_seg'] as num?) ?? 0)}' : ''}',
        pct: (frac * 100).round(),
        indexado: enAnalisis ? 1 : frac,
        agentes: enAnalisis ? frac : 0,
        textoAgentes: 'Agentes ${enAnalisis ? proc : 0}/${tot > 0 && enAnalisis ? tot : total}',
      ));
    }
    for (final d in st.documentos) {
      if (!estadosProcesando.contains(d['estado'])) continue;
      final nombre = nombreDoc(d);
      if (st.subiendo && nombre == nombreSubida) continue;
      final nAn = (d['analisis_count'] as num?)?.toInt() ?? 0;
      final analizando = d['estado'] == 'Analizando';
      final fr = total > 0 ? (nAn / total).clamp(0.0, 1.0).toDouble() : 0.0;
      tarjetas.add(_tarjetaProceso(
        context,
        nombre: nombre.isEmpty ? 'Documento' : nombre,
        detalle: analizando ? 'Analizando · $nAn de $total agentes' : 'Indexando el documento…',
        pct: analizando ? (fr * 100).round() : 0,
        indexado: analizando ? 1 : 0.1,
        agentes: analizando ? fr : 0,
        textoAgentes: 'Agentes $nAn/$total',
      ));
    }
    if (tarjetas.isEmpty) return const [];
    return [const SecTitle('En proceso'), ...tarjetas];
  }

  Widget _tarjetaArchivo(BuildContext context, AppState st, Map<String, dynamic> d) {
    final c = context.c;
    final id = '${d['id']}';
    final activo = st.docActivo == id;
    final nombre = nombreDoc(d);
    final estado = '${d['estado'] ?? ''}';
    final procesando = estadosProcesando.contains(estado);
    final error = estado == 'Error';
    final nAn = (d['analisis_count'] as num?)?.toInt() ?? 0;
    final total = st.totalAgentes;
    final pendientes = total > nAn ? total - nAn : 0;
    final paginas = '${d['total_paginas'] ?? '?'} páginas';
    return GgCard(
      borderColor: activo ? Brand.accent : c.border,
      onTap: activo ? null : () async {
        if (await st.cambiarDocumento(id)) st.toast('Documento activado');
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _insignia(context, nombre, activo: activo),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre.isEmpty ? '(sin título)' : nombre, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: activo ? c.text : c.text2)),
              const SizedBox(height: 2),
              Text('$paginas · $nAn/$total agentes${activo ? '' : ' · Desactivado'}',
                  style: TextStyle(fontSize: 12, color: c.text3)),
            ]),
          ),
          const SizedBox(width: 8),
          Switch(
            value: activo,
            onChanged: (v) async {
              if (v && !activo && await st.cambiarDocumento(id)) {
                st.toast('Documento activado');
              } else if (!v && activo) {
                st.desactivarDocumento();
              }
            },
          ),
        ]),
        if (activo) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Pill('En uso', fg: c.accentText),
            if (error) Pill('Error al procesar', fg: c.crit, dot: true),
            if (!error && procesando) Pill('Procesando', fg: c.accentText, dot: true),
            if (!error && !procesando && nAn > 0) Pill('$nAn listos', fg: c.low),
            if (!error && !procesando && pendientes > 0) Pill('$pendientes pendientes', fg: c.med),
          ]),
          if (total > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              for (var i = 0; i < total; i++)
                Expanded(
                  child: Container(
                    height: 6,
                    margin: EdgeInsets.only(right: i == total - 1 ? 0 : 3),
                    decoration: BoxDecoration(
                      color: i < nAn ? c.low : (procesando ? c.track : c.med),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              flex: 4,
              child: GgButton('Leer', icon: Icons.visibility_outlined, ghost: true, onTap: () => _abrirDocumento(context, d)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: GgButton('Ver agentes', ghost: true, onTap: () => st.go('diagnosticos')),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Eliminar documento',
              child: Material(
                color: c.surface2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.border2)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    if (await confirmar(context, '¿Eliminar este documento, sus fragmentos y sus análisis?', ok: 'Eliminar')) {
                      await st.eliminarDocumento(id);
                    }
                  },
                  child: SizedBox(width: 44, height: 42, child: Icon(Icons.delete_outline, size: 19, color: c.crit)),
                ),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final st = context.watch<AppState>();
    final nAnalisis = st.analisis?.length ?? 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHead(
        title: 'Gerencia General',
        subtitle: 'Sube documentos, mira cómo avanza su análisis y elige cuál usar.',
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
            Text('PDF, Word o Excel. La IA lo indexa y lo revisa con los agentes.',
                style: TextStyle(fontSize: 12, color: c.text2, height: 1.35)),
          ])),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: c.text3),
        ]),
      ),
      ..._enProceso(context, st),
      const SecTitle('Tus archivos'),
      if (st.documentos.isEmpty)
        const GgCard(
          child: EmptyState(
            icon: Icons.description_outlined,
            title: 'Aún no hay documentos',
            text: 'Sube el primer archivo para empezar. Se indexará y analizará automáticamente.',
          ),
        )
      else
        for (final d in st.documentos) _tarjetaArchivo(context, st, d),
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
