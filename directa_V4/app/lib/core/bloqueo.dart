import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Forma principal de desbloqueo. Con huella, el PIN queda de respaldo si la huella falla.
enum ModoBloqueo { ninguno, pin, huella }

/// Bloqueo de la app: PIN de 4 dígitos, o huella/rostro como forma principal con el PIN de respaldo.
/// Es por usuario y por celular. El PIN nunca se guarda: solo su huella SHA-256 con sal.
class Bloqueo {
  Bloqueo._();

  static const largoPin = 4;
  static const maxIntentos = 5;
  static const volverABloquear = Duration(minutes: 5);

  static final _auth = LocalAuthentication();

  static String _k(String uid, String que) => 'directa.bloqueo.$uid.$que';

  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  static String _hash(String pin, String sal) => sha256.convert(utf8.encode('$sal:$pin:directa')).toString();

  static Future<bool> tienePin(String uid) async => (await _p).getString(_k(uid, 'pin')) != null;

  static Future<ModoBloqueo> modo(String uid) async {
    final p = await _p;
    final m = p.getString(_k(uid, 'modo'));
    final hayPin = p.getString(_k(uid, 'pin')) != null;
    if (m == 'huella' && hayPin) return ModoBloqueo.huella;
    if (m == 'pin' || p.getString(_k(uid, 'pin')) != null) return ModoBloqueo.pin;
    return ModoBloqueo.ninguno;
  }

  /// Huella como forma principal; el PIN (ya creado) queda de respaldo.
  static Future<void> usarHuella(String uid) async => (await _p).setString(_k(uid, 'modo'), 'huella');

  /// Solo PIN (mantiene el PIN ya creado).
  static Future<void> usarSoloPin(String uid) async => (await _p).setString(_k(uid, 'modo'), 'pin');

  static Future<void> definirPin(String uid, String pin) async {
    final r = Random.secure();
    final sal = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    final p = await _p;
    await p.setString(_k(uid, 'sal'), sal);
    await p.setString(_k(uid, 'pin'), _hash(pin, sal));
    await p.setInt(_k(uid, 'fallos'), 0);
    await p.setString(_k(uid, 'modo'), 'pin');
  }

  /// true si el PIN es correcto. Cuenta los intentos fallidos.
  static Future<bool> verificarPin(String uid, String pin) async {
    final p = await _p;
    final guardado = p.getString(_k(uid, 'pin'));
    final sal = p.getString(_k(uid, 'sal')) ?? '';
    final ok = guardado != null && guardado == _hash(pin, sal);
    await p.setInt(_k(uid, 'fallos'), ok ? 0 : (p.getInt(_k(uid, 'fallos')) ?? 0) + 1);
    return ok;
  }

  static Future<int> intentosRestantes(String uid) async =>
      maxIntentos - ((await _p).getInt(_k(uid, 'fallos')) ?? 0);

  /// Quita PIN y huella (al desactivar o tras demasiados intentos).
  static Future<void> quitar(String uid) async {
    final p = await _p;
    for (final k in ['pin', 'sal', 'fallos', 'bio', 'modo']) {
      await p.remove(_k(uid, k));
    }
  }

  /// ¿El celular tiene huella o rostro registrado?
  static Future<bool> biometriaDisponible() async {
    if (kIsWeb) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Pide huella o rostro. Devuelve true si la persona se identificó.
  static Future<bool> pedirBiometria({String motivo = 'Confirma que eres tú para entrar a DIRECTA'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: motivo,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
