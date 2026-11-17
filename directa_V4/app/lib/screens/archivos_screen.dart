import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/saver.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class ArchivosScreen extends StatefulWidget {
  const ArchivosScreen({super.key});

  @override
  State<ArchivosScreen> createState() => _ArchivosScreenState();
}

class _ArchivosScreenState extends State<ArchivosScreen> {
  late Future<List<ArchivoGuardado>> _carga;

  @override
  void initState() {
    super.initState();
    _carga = listarArchivosGuardados();
  }

  void _recargar() => setState(() => _carga = listarArchivosGuardados());

  Future<void> _compartir(ArchivoGuardado archivo) async {
    try {
      await compartirArchivoGuardado(archivo);
    } catch (e) {
      if (mounted) context.read<AppState>().toast('No se pudo compartir el archivo: $e', err: true);
    }
  }

  Future<void> _eliminar(ArchivoGuardado archivo) async {
    final ok = await confirmar(context, 'Se eliminará ${archivo.nombre} de Descargas/DIRECTA.', ok: 'Eliminar');
    if (!ok || !mounted) return;
    try {
      await eliminarArchivoGuardado(archivo);
      _recargar();
      if (mounted) context.read<AppState>().toast('Archivo eliminado');
    } catch (e) {
      if (mounted) context.read<AppState>().toast('No se pudo eliminar el archivo: $e', err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead(
        title: 'Archivos descargados',
        subtitle: 'PDF y Excel que DIRECTA ha guardado en este teléfono.',
        actions: [IconButton(onPressed: _recargar, tooltip: 'Actualizar', icon: const Icon(Icons.refresh))],
      ),
      GgCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, color: c.accentText),
        const SizedBox(width: 10),
        Expanded(child: Text(
          'En Android se muestran los archivos de Descargas/DIRECTA. En otros dispositivos, las copias guardadas dentro de DIRECTA.',
          style: TextStyle(fontSize: 12.5, color: c.text2),
        )),
      ])),
      GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SecTitle('Guardados en este dispositivo'),
        FutureBuilder<List<ArchivoGuardado>>(
          future: _carga,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return EmptyState(icon: Icons.error_outline, title: 'No se pudieron cargar los archivos', text: '${snapshot.error}');
            }
            final archivos = snapshot.data ?? const [];
            if (archivos.isEmpty) {
              return const EmptyState(
                icon: Icons.folder_open_outlined,
                title: 'Todavía no hay archivos guardados',
                text: 'Cuando generes un PDF o Excel desde la app, aparecerá aquí.',
              );
            }
            return Column(children: [
              for (final archivo in archivos)
                _ArchivoRow(archivo: archivo, compartir: () => _compartir(archivo), eliminar: () => _eliminar(archivo)),
            ]);
          },
        ),
      ])),
    ]);
  }
}

class _ArchivoRow extends StatelessWidget {
  const _ArchivoRow({required this.archivo, required this.compartir, required this.eliminar});
  final ArchivoGuardado archivo;
  final VoidCallback compartir;
  final VoidCallback eliminar;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final esPdf = archivo.nombre.toLowerCase().endsWith('.pdf');
    final fecha = MaterialLocalizations.of(context).formatShortDate(archivo.modificado);
    final tamano = archivo.bytes < 1024 * 1024
        ? '${(archivo.bytes / 1024).ceil()} KB'
        : '${(archivo.bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(13), border: Border.all(color: c.border)),
      child: Row(children: [
        Container(
          width: 42, height: 42, alignment: Alignment.center,
          decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(11)),
          child: Icon(esPdf ? Icons.picture_as_pdf_outlined : Icons.table_view_outlined, color: c.accentText),
        ),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(archivo.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 3),
          Text('$fecha · $tamano', style: TextStyle(color: c.text3, fontSize: 11.5)),
        ])),
        IconButton(onPressed: compartir, tooltip: 'Compartir o abrir', icon: Icon(Icons.ios_share_outlined, color: c.accentText)),
        IconButton(onPressed: eliminar, tooltip: 'Eliminar', icon: Icon(Icons.delete_outline, color: c.crit)),
      ]),
    );
  }
}
