import 'dart:typed_data';

import 'saver_io.dart' if (dart.library.js_interop) 'saver_web.dart' as impl;

/// Guarda o comparte un archivo generado (PDF, Excel, JSON).
/// En el navegador lo descarga; en el teléfono abre el menú "Compartir / Guardar en…".
/// Devuelve un texto corto para mostrar al usuario.
Future<String> guardarArchivo(String nombre, Uint8List bytes, String mime) =>
    impl.guardarArchivo(nombre, bytes, mime);
