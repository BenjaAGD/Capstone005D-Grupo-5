/// Dirección del backend por defecto. Se puede cambiar dentro de la app (Más → Servidor)
/// o al compilar:  flutter build apk --dart-define=API_BASE_URL=https://mi-servidor
class Config {
  Config._();
  static const _definida = String.fromEnvironment('API_BASE_URL');
  static const _servidorDirecta = 'https://capstone005d-grupo-5.onrender.com';

  static String apiPorDefecto() {
    if (_definida.isNotEmpty) return _definida;
    return _servidorDirecta;
  }
}
