import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'archivo_guardado.dart';

const _downloads = MethodChannel('directa/downloads');

Future<String> guardarArchivo(String nombre, Uint8List bytes, String mime) async {
  if (Platform.isAndroid) {
    try {
      await _downloads.invokeMethod<Object?>('save', {
        'name': nombre,
        'mime': mime,
        'bytes': bytes,
      });
      return 'Guardado en Documentos/Directa Gerente General: $nombre';
    } on PlatformException catch (e) {
      if (e.code != 'UNAVAILABLE') rethrow;
    }
  }
  final dir = await getApplicationDocumentsDirectory();
  final f = File('${dir.path}/$nombre');
  await f.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], subject: nombre));
  return 'Archivo listo: $nombre';
}

Future<List<ArchivoGuardado>> listarArchivosGuardados() async {
  if (Platform.isAndroid) {
    try {
      final rows = await _downloads.invokeMethod<List<dynamic>>('list');
      if (rows != null) {
        return [
          for (final row in rows)
            if (row is Map)
              ArchivoGuardado(
                nombre: '${row['nombre'] ?? 'Archivo'}',
                ruta: '${row['uri'] ?? ''}',
                bytes: (row['bytes'] as num?)?.toInt() ?? 0,
                modificado: DateTime.fromMillisecondsSinceEpoch((row['modificado'] as num?)?.toInt() ?? 0),
                mime: '${row['mime'] ?? 'application/octet-stream'}',
                carpeta: '${row['carpeta'] ?? 'Otros'}',
              ),
        ];
      }
    } on PlatformException {
      // En dispositivos anteriores a Android 10 se usa la carpeta privada de la app.
    }
  }

  final dir = await getApplicationDocumentsDirectory();
  if (!await dir.exists()) return const [];
  final archivos = <ArchivoGuardado>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    try {
      final stat = await entity.stat();
      final nombre = entity.uri.pathSegments.last;
      archivos.add(ArchivoGuardado(
        nombre: nombre,
        ruta: entity.path,
        bytes: stat.size,
        modificado: stat.modified,
        mime: nombre.toLowerCase().endsWith('.pdf') ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ));
    } on FileSystemException {
      // El archivo pudo desaparecer mientras se leía la carpeta.
    }
  }
  archivos.sort((a, b) => b.modificado.compareTo(a.modificado));
  return archivos;
}

Future<void> compartirArchivoGuardado(ArchivoGuardado archivo) async {
  if (Platform.isAndroid && archivo.ruta.startsWith('content://')) {
    await _downloads.invokeMethod<void>('share', {'uri': archivo.ruta, 'mime': archivo.mime});
    return;
  }
  await SharePlus.instance.share(ShareParams(
    files: [XFile(archivo.ruta, mimeType: archivo.mime)],
    subject: archivo.nombre,
  ));
}

Future<void> eliminarArchivoGuardado(ArchivoGuardado archivo) async {
  if (Platform.isAndroid && archivo.ruta.startsWith('content://')) {
    await _downloads.invokeMethod<void>('delete', {'uri': archivo.ruta});
    return;
  }
  final file = File(archivo.ruta);
  if (await file.exists()) await file.delete();
}

/// Mueve a "Documentos/Directa Gerente General" lo que versiones anteriores dejaron en Descargas/DIRECTA.
/// Devuelve cuántos archivos se movieron (0 si no había nada o no es Android).
Future<int> migrarArchivosAntiguos() async {
  if (!Platform.isAndroid) return 0;
  try {
    return await _downloads.invokeMethod<int>('migrate') ?? 0;
  } on PlatformException {
    return 0;
  }
}
