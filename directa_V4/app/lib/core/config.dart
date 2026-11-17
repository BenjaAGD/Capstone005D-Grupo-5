import 'package:flutter/foundation.dart';

/// Dirección del backend por defecto. Se puede cambiar dentro de la app (Más → Servidor)
/// o al compilar:  flutter build apk --dart-define=API_BASE_URL=https://mi-servidor
class Config {
  Config._();
  static const _definida = String.fromEnvironment('API_BASE_URL');
  static const _servidorDirecta = 'https://capstone005d-grupo-5.onrender.com';

  static String apiPorDefecto() {
    if (_definida.isNotEmpty) return _definida;
    // En la versión web servida por Docker (nginx), /api va al backend en el mismo dominio.
    if (kIsWeb) return Uri.base.origin;
    // En Android/iOS, conecta al servicio publicado sin pedir que ingresen la URL.
    return _servidorDirecta;
  }
}
