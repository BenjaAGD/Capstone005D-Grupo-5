import 'dart:typed_data';

import 'saver_io.dart' if (dart.library.js_interop) 'saver_web.dart' as impl;
import 'archivo_guardado.dart';

export 'archivo_guardado.dart';

/// Guarda o comparte un archivo generado (PDF, Excel, JSON).
/// En el navegador lo descarga; en el teléfono abre el menú "Compartir / Guardar en…".
/// Devuelve un texto corto para mostrar al usuario.
Future<String> guardarArchivo(String nombre, Uint8List bytes, String mime) =>
    impl.guardarArchivo(nombre, bytes, mime);

Future<List<ArchivoGuardado>> listarArchivosGuardados() => impl.listarArchivosGuardados();

Future<void> compartirArchivoGuardado(ArchivoGuardado archivo) => impl.compartirArchivoGuardado(archivo);

Future<void> eliminarArchivoGuardado(ArchivoGuardado archivo) => impl.eliminarArchivoGuardado(archivo);
