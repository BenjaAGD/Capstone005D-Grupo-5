import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Notificaciones del sistema (Android) con barra de progreso para trabajos largos:
/// indexación y análisis de documentos, y generación de la memoria.
/// En web u otras plataformas no hace nada; nunca lanza errores hacia la app.
class Notificaciones {
  Notificaciones._();
  static const _canal = MethodChannel('directa/notif');

  static const idDocumento = 4101;
  static const idMemoria = 4102;

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool _permisoPedido = false;

  /// Pide el permiso de notificaciones (Android 13+) una sola vez por sesión.
  static Future<void> pedirPermiso() async {
    if (!_android || _permisoPedido) return;
    _permisoPedido = true;
    try {
      await _canal.invokeMethod<void>('permiso');
    } catch (_) {}
  }

  /// Permiso para ver archivos guardados antes de reinstalar la app (solo Android 10–12).
  static Future<void> pedirPermisoArchivos() async {
    if (!_android) return;
    try {
      await _canal.invokeMethod<void>('permisoArchivos');
    } catch (_) {}
  }

  /// [valor] de 0 a 100; usa -1 para una barra sin porcentaje.
  static Future<void> progreso(int id, String titulo, String texto, {int valor = -1}) async {
    if (!_android) return;
    try {
      await _canal.invokeMethod<void>('progreso', {'id': id, 'titulo': titulo, 'texto': texto, 'valor': valor});
    } catch (_) {}
  }

  static Future<void> listo(int id, String titulo, String texto) async {
    if (!_android) return;
    try {
      await _canal.invokeMethod<void>('listo', {'id': id, 'titulo': titulo, 'texto': texto});
    } catch (_) {}
  }

  static Future<void> cerrar(int id) async {
    if (!_android) return;
    try {
      await _canal.invokeMethod<void>('cerrar', {'id': id});
    } catch (_) {}
  }
}
