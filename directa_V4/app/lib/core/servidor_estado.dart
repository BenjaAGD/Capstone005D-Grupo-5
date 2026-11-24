import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum EstadoServidor { desconocido, despertando, enLinea, sinConexion }

/// Estado del servidor (Render). El plan gratuito lo duerme tras un rato sin uso y tarda cerca de
/// un minuto en despertar. Esta clase lo "despierta" apenas se abre la app, EN SEGUNDO PLANO:
///
///  * nunca se espera con `await` desde el arranque ni desde el login, así que no demora la entrada;
///  * mientras despierta, la app muestra un aviso suave (no un error) y reintenta sola;
///  * cuando responde, la app recarga los datos sin que nadie toque nada (lo hace el Shell).
///
/// Es un singleton porque el login se muestra antes de que exista el AppState.
class ServidorEstado extends ChangeNotifier {
  ServidorEstado._();
  static final ServidorEstado instance = ServidorEstado._();

  /// Intentos de despertar: 12 × (6 s de espera + 4 s de pausa) ≈ 2 minutos como máximo.
  static const maxIntentos = 12;
  static const _esperaPorIntento = Duration(seconds: 6);
  static const _pausaEntreIntentos = Duration(seconds: 4);

  EstadoServidor estado = EstadoServidor.desconocido;
  int intento = 0;
  Duration? latencia;
  DateTime? ultimaRevision;

  /// Versión que declara el backend en `/`. Si falta, el servidor en Render es anterior a esta app.
  static const versionEsperada = 'v2-pdf';
  String? versionBackend;
  bool get desactualizado => estado == EstadoServidor.enLinea && versionBackend != versionEsperada;

  String _base = '';
  bool _corriendo = false;

  /// Comienza a despertar el servidor. Llamar SIN await. Si ya está en curso, no hace nada.
  void iniciar(String baseUrl) {
    _base = _limpiar(baseUrl);
    if (_corriendo || _base.isEmpty) return;
    unawaited(_ciclo());
  }

  /// Cuando la persona cambia la dirección del servidor en Ajustes.
  void actualizarBase(String baseUrl) {
    _base = _limpiar(baseUrl);
    estado = EstadoServidor.desconocido;
    notifyListeners();
    if (!_corriendo) unawaited(_ciclo());
  }

  /// Botón "Reintentar ahora".
  void reintentarAhora() {
    if (_corriendo || _base.isEmpty) return;
    unawaited(_ciclo());
  }

  String _limpiar(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Future<void> _ciclo() async {
    _corriendo = true;
    intento = 0;
    estado = EstadoServidor.despertando;
    notifyListeners();
    try {
      while (intento < maxIntentos) {
        intento++;
        notifyListeners();
        if (await _ping()) {
          estado = EstadoServidor.enLinea;
          return;
        }
        if (intento < maxIntentos) await Future<void>.delayed(_pausaEntreIntentos);
      }
      estado = EstadoServidor.sinConexion;
    } finally {
      _corriendo = false;
      ultimaRevision = DateTime.now();
      notifyListeners();
    }
  }

  /// Cualquier respuesta que no sea un error del servidor (5xx) significa que ya despertó.
  /// Mientras duerme, Render responde 503 o no responde.
  Future<bool> _ping() async {
    final reloj = Stopwatch()..start();
    try {
      final r = await http.get(Uri.parse('$_base/')).timeout(_esperaPorIntento);
      if (r.statusCode < 500) {
        latencia = reloj.elapsed;
        try {
          versionBackend = '${(jsonDecode(r.body) as Map)['version'] ?? ''}';
        } catch (_) {
          versionBackend = '';
        }
        return true;
      }
    } catch (_) {
      // sin respuesta todavía: se reintenta
    }
    return false;
  }
}
