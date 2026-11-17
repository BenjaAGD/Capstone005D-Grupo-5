class ArchivoGuardado {
  const ArchivoGuardado({
    required this.nombre,
    required this.ruta,
    required this.bytes,
    required this.modificado,
    required this.mime,
  });

  final String nombre;
  final String ruta;
  final int bytes;
  final DateTime modificado;
  final String mime;
}
