import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'archivo_guardado.dart';

Future<String> guardarArchivo(String nombre, Uint8List bytes, String mime) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = nombre;
  web.document.body?.append(a);
  a.click();
  a.remove();
  Future<void>.delayed(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
  return 'Descargado: $nombre';
}

Future<List<ArchivoGuardado>> listarArchivosGuardados() async => const [];

Future<void> compartirArchivoGuardado(ArchivoGuardado archivo) async {}

Future<void> eliminarArchivoGuardado(ArchivoGuardado archivo) async {}

Future<int> migrarArchivosAntiguos() async => 0;

Future<void> abrirArchivoGuardado(ArchivoGuardado archivo) async {}

Future<bool> abrirUltimoArchivo() async => false;

Future<void> eliminarArchivosGuardados(List<ArchivoGuardado> archivos) async {}
