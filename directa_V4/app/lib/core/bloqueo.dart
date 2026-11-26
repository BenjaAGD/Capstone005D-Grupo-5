import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  /// Almacén cifrado del sistema (Keystore en Android, Keychain en iOS). El PIN ya no vive en
  /// SharedPreferences, que es un archivo de texto legible si alguien accede al celular.
  static const _s = FlutterSecureStorage();
  static const _claves = ['pin', 'sal', 'fallos', 'bio', 'modo'];
  static final _migrados = <String>{};

  static Future<String?> _leer(String uid, String que) async {
    await _migrar(uid);
    try {
      return await _s.read(key: _k(uid, que));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _escribir(String uid, String que, String valor) => _s.write(key: _k(uid, que), value: valor);

  static String _hash(String pin, String sal) => sha256.convert(utf8.encode('$sal:$pin:directa')).toString();

  /// Pasa al almacén cifrado lo que versiones anteriores dejaron en SharedPreferences (una sola vez).
  static Future<void> _migrar(String uid) async {
    if (!_migrados.add(uid)) return;
    try {
      final p = await SharedPreferences.getInstance();
      for (final c in _claves) {
        final k = _k(uid, c);
        final v = p.get(k);
        if (v == null) continue;
        await _s.write(key: k, value: '$v');
        await p.remove(k);
      }
    } catch (_) {
      _migrados.remove(uid);
    }
  }

  static Future<bool> tienePin(String uid) async => await _leer(uid, 'pin') != null;

  static Future<ModoBloqueo> modo(String uid) async {
    final m = await _leer(uid, 'modo');
    final hayPin = await _leer(uid, 'pin') != null;
    if (m == 'huella' && hayPin) return ModoBloqueo.huella;
    if (m == 'pin' || hayPin) return ModoBloqueo.pin;
    return ModoBloqueo.ninguno;
  }

  /// Huella como forma principal; el PIN (ya creado) queda de respaldo.
  static Future<void> usarHuella(String uid) => _escribir(uid, 'modo', 'huella');

  /// Solo PIN (mantiene el PIN ya creado).
  static Future<void> usarSoloPin(String uid) => _escribir(uid, 'modo', 'pin');

  static Future<void> definirPin(String uid, String pin) async {
    final r = Random.secure();
    final sal = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    await _escribir(uid, 'sal', sal);
    await _escribir(uid, 'pin', _hash(pin, sal));
    await _escribir(uid, 'fallos', '0');
    await _escribir(uid, 'modo', 'pin');
  }

  static Future<int> _fallos(String uid) async => int.tryParse(await _leer(uid, 'fallos') ?? '') ?? 0;

  /// true si el PIN es correcto. Cuenta los intentos fallidos.
  static Future<bool> verificarPin(String uid, String pin) async {
    final guardado = await _leer(uid, 'pin');
    final sal = await _leer(uid, 'sal') ?? '';
    final ok = guardado != null && guardado == _hash(pin, sal);
    await _escribir(uid, 'fallos', ok ? '0' : '${await _fallos(uid) + 1}');
    return ok;
  }

  static Future<int> intentosRestantes(String uid) async => maxIntentos - await _fallos(uid);

  /// Quita PIN y huella (al desactivar o tras demasiados intentos).
  static Future<void> quitar(String uid) async {
    await _migrar(uid);
    for (final k in _claves) {
      try {
        await _s.delete(key: _k(uid, k));
      } catch (_) {}
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
