import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<String> guardarArchivo(String nombre, Uint8List bytes, String mime) async {
  final dir = await getApplicationDocumentsDirectory();
  final f = File('${dir.path}/$nombre');
  await f.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], subject: nombre));
  return 'Archivo listo: $nombre';
}
