import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const _downloads = MethodChannel('directa/downloads');

Future<String> guardarArchivo(String nombre, Uint8List bytes, String mime) async {
  if (Platform.isAndroid) {
    try {
      await _downloads.invokeMethod<void>('save', {
        'name': nombre,
        'mime': mime,
        'bytes': bytes,
      });
      return 'Guardado en Descargas/DIRECTA: $nombre';
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
