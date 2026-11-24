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
    _carga = _cargar(migrar: true);
  }

  Future<List<ArchivoGuardado>> _cargar({bool migrar = false}) async {
    if (migrar) {
      // Mueve lo que quedó en Descargas/DIRECTA de versiones anteriores.
      final movidos = await migrarArchivosAntiguos();
      if (movidos > 0 && mounted) {
        context.read<AppState>().toast('Moví $movidos archivo(s) antiguos a Documentos/Directa Gerente General');
      }
    }
    return listarArchivosGuardados();
  }

  Future<void> _recargar() async {
    final f = _cargar();
    setState(() => _carga = f);
    await f.catchError((_) => <ArchivoGuardado>[]);
  }

  Future<void> _compartir(ArchivoGuardado archivo) async {
    try {
      await compartirArchivoGuardado(archivo);
    } catch (e) {
      if (mounted) context.read<AppState>().toast('No se pudo abrir el archivo. Inténtalo de nuevo.', err: true);
    }
  }

  Future<void> _eliminar(ArchivoGuardado archivo) async {
    final ok = await confirmar(context, 'Se eliminará "${archivo.nombre}" de tu teléfono.', ok: 'Eliminar');
    if (!ok || !mounted) return;
    try {
      await eliminarArchivoGuardado(archivo);
      await _recargar();
      if (mounted) context.read<AppState>().toast('Archivo eliminado');
    } catch (e) {
      if (mounted) context.read<AppState>().toast('No se pudo eliminar. Puede que ya no exista; actualiza la lista.', err: true);
    }
  }

  Future<void> _eliminarTodo(List<ArchivoGuardado> archivos) async {
    final ok = await confirmar(context, 'Se eliminarán ${archivos.length} archivos de tu teléfono. Esto no se puede deshacer.', ok: 'Eliminar todo');
    if (!ok || !mounted) return;
    var fallos = 0;
    for (final a in archivos) {
      try {
        await eliminarArchivoGuardado(a);
      } catch (_) {
        fallos++;
      }
    }
    await _recargar();
    if (mounted) {
      context.read<AppState>().toast(fallos == 0 ? 'Archivos eliminados' : 'No se pudieron eliminar $fallos archivo(s)', err: fallos > 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHead(
        title: 'Mis archivos',
        subtitle: 'PDF y Excel guardados en Documentos/Directa Gerente General.',
        actions: [IconButton(onPressed: _recargar, tooltip: 'Actualizar', icon: const Icon(Icons.refresh))],
      ),
      FutureBuilder<List<ArchivoGuardado>>(
        future: _carga,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Column(children: [for (var i = 0; i < 4; i++) const _Esqueleto()]);
          }
          if (snapshot.hasError) {
            return GgCard(child: Column(children: [
              const EmptyState(
                icon: Icons.error_outline,
                title: 'No pudimos leer tus archivos',
                text: 'Revisa que la app tenga acceso al almacenamiento e inténtalo de nuevo.',
              ),
              GgButton('Reintentar', icon: Icons.refresh, onTap: _recargar),
            ]));
          }
          final archivos = snapshot.data ?? const <ArchivoGuardado>[];
          if (archivos.isEmpty) {
            return const GgCard(child: EmptyState(
              icon: Icons.folder_open_outlined,
              title: 'Todavía no hay archivos',
              text: 'Cuando descargues un PDF o Excel, quedará guardado en Documentos/Directa Gerente General y aparecerá aquí.',
            ));
          }
          final grupos = <String, List<ArchivoGuardado>>{};
          for (final a in archivos) {
            grupos.putIfAbsent(a.carpeta, () => []).add(a);
          }
          final nombres = grupos.keys.toList()..sort();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(child: Text('${archivos.length} archivos', style: TextStyle(color: c.text3, fontSize: 12.5))),
                TextButton.icon(
                  onPressed: () => _eliminarTodo(archivos),
                  icon: Icon(Icons.delete_sweep_outlined, size: 18, color: c.crit),
                  label: Text('Eliminar todo', style: TextStyle(color: c.crit)),
                ),
              ]),
            ),
            for (final n in nombres)
              GgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SecTitle('$n · ${grupos[n]!.length}'),
                for (final a in grupos[n]!)
                  _ArchivoRow(archivo: a, compartir: () => _compartir(a), eliminar: () => _eliminar(a)),
              ])),
          ]);
        },
      ),
    ]);
  }
}

class _Esqueleto extends StatelessWidget {
  const _Esqueleto();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 66,
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(13), border: Border.all(color: c.border)),
    );
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
        IconButton(onPressed: compartir, tooltip: 'Abrir o compartir', icon: Icon(Icons.ios_share_outlined, color: c.accentText)),
        IconButton(onPressed: eliminar, tooltip: 'Eliminar', icon: Icon(Icons.delete_outline, color: c.crit)),
      ]),
    );
  }
}
