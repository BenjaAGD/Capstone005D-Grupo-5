/// RUT chileno: limpieza, validación del dígito verificador (módulo 11) y formato.
class Rut {
  Rut._();

  /// "12.345.678-k" → "12345678-K". Devuelve '' si no tiene forma de RUT.
  static String normalizar(String texto) {
    final limpio = texto.toUpperCase().replaceAll(RegExp(r'[^0-9K]'), '');
    if (limpio.length < 2) return '';
    final cuerpo = limpio.substring(0, limpio.length - 1);
    final dv = limpio.substring(limpio.length - 1);
    if (!RegExp(r'^[0-9]{1,8}$').hasMatch(cuerpo)) return '';
    return '${int.parse(cuerpo)}-$dv';
  }

  /// Calcula el dígito verificador de un cuerpo numérico.
  static String digito(String cuerpo) {
    var suma = 0;
    var factor = 2;
    for (var i = cuerpo.length - 1; i >= 0; i--) {
      suma += int.parse(cuerpo[i]) * factor;
      factor = factor == 7 ? 2 : factor + 1;
    }
    final r = 11 - (suma % 11);
    return r == 11 ? '0' : r == 10 ? 'K' : '$r';
  }

  static bool esValido(String texto) {
    final n = normalizar(texto);
    if (n.isEmpty) return false;
    final partes = n.split('-');
    final cuerpo = partes[0];
    if (int.parse(cuerpo) < 1000000) return false;
    return digito(cuerpo) == partes[1];
  }

  /// "12345678-5" → "12.345.678-5".
  static String formatear(String texto) {
    final n = normalizar(texto);
    if (n.isEmpty) return texto.trim();
    final partes = n.split('-');
    final c = partes[0];
    final b = StringBuffer();
    for (var i = 0; i < c.length; i++) {
      if (i > 0 && (c.length - i) % 3 == 0) b.write('.');
      b.write(c[i]);
    }
    return '$b-${partes[1]}';
  }

  /// Mensaje para formularios; null si está bien.
  static String? validar(String? v, {String que = 'RUT'}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Escribe tu $que.';
    if (normalizar(t).isEmpty) return 'Escribe el $que con su dígito verificador (ej: 12.345.678-5).';
    if (!esValido(t)) return 'El dígito verificador no corresponde.';
    return null;
  }
}
