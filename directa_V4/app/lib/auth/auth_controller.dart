import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_config.dart';
import 'auth_repository.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.config, this.repository, this.configurationError}) {
    _subscription = repository?.events.listen((event) {
      if (_disposed) return;
      if (event == AuthSignal.signedOut) {
        _epoch++;
        _forget();
        phase = AuthPhase.signedOut;
        busy = false;
        _notify();
      } else if (event == AuthSignal.passwordRecovery) {
        _epoch++;
        _forget();
        passwordRecoveryActive = true;
        _signedOutByUser = false;
        _lastIdentifier = '';
        phase = AuthPhase.signedOut;
        busy = false;
        _notify();
        unawaited(checkSession());
      } else if (!busy && phase == AuthPhase.signedOut) {
        if (_signedOutByUser) { unawaited(repository!.signOut().catchError((_) {})); }
        else { unawaited(checkSession()); }
      }
    }, onError: (Object _, StackTrace _) {
      if (_disposed) return;
      ++_epoch;
      _forget();
      busy = false;
      phase = AuthPhase.connectionError;
      error = 'Se perdió la verificación de acceso. Comprueba tu conexión y vuelve a verificar.';
      _notify();
    });
  }

  final AuthConfig config;
  final AuthRepository? repository;
  final String? configurationError;
  AuthPhase phase = AuthPhase.checking;
  bool busy = false;
  bool passwordRecoveryActive = false;
  String? error, notice;
  IdentityCheck? identity;
  OrganizationAccess? organization;
  MfaEnrollment? enrollment;
  String _lastIdentifier = '';
  int _epoch = 0;
  bool _disposed = false;
  int _failedAttempts = 0;
  bool _signedOutByUser = false;
  DateTime? _retryAfter;
  StreamSubscription<AuthSignal>? _subscription;
  Future<void> _clearing = Future<void>.value();
  Future<void> Function(String, String)? clearLocalSession;

  bool get ready => phase == AuthPhase.ready && organization != null && identity != null;
  String get sessionKey => ready ? '${identity!.userId}:${organization!.id}' : 'signed-out';
  bool get configured => repository != null && configurationError == null;

  void _notify() { if (!_disposed) notifyListeners(); }
  void _forget() {
    final user = identity?.userId, tenant = organization?.id;
    identity = null; organization = null; enrollment = null; passwordRecoveryActive = false;
    if (user != null && tenant != null && clearLocalSession != null) {
      // Revoca la escritura de la sesión anterior inmediatamente. Antes de
      // reabrir el mismo espacio esperamos a que termine su limpieza.
      _clearing = Future.wait([_clearing, clearLocalSession!(user, tenant)])
          .then<void>((_) {}).catchError((_) {});
    }
  }

  Future<void> _run(Future<void> Function(int epoch) operation) async {
    if (busy || _disposed) return;
    error = null;
    notice = null;
    if (!configured) {
      phase = AuthPhase.configurationError;
      error = configurationError ?? 'Falta conectar el entorno para iniciar sesión.';
      _notify();
      return;
    }
    busy = true;
    final epoch = ++_epoch;
    _notify();
    try {
      await operation(epoch);
    } on LoginFailure catch (e) {
      if (epoch != _epoch || _disposed) return;
      error = e.message;
      if (e.emailUnconfirmed) phase = AuthPhase.emailVerification;
      if (e.sessionExpired) {
        _signedOutByUser = true;
        unawaited(repository!.signOut().catchError((_) {}));
        _forget(); phase = AuthPhase.signedOut;
      }
      if (phase == AuthPhase.checking) phase = AuthPhase.connectionError;
    } catch (_) {
      if (epoch != _epoch || _disposed) return;
      error = 'No pudimos verificar la conexión. Inténtalo nuevamente.';
      if (phase == AuthPhase.checking) phase = AuthPhase.connectionError;
    } finally {
      if (epoch == _epoch && !_disposed) { busy = false; _notify(); }
    }
  }

  Future<void> checkSession({bool background = false}) => _run((epoch) async {
    if (!background) { phase = AuthPhase.checking; _notify(); }
    try { await _inspect(epoch); }
    catch (_) {
      if (epoch == _epoch && !_disposed) { _forget(); phase = AuthPhase.connectionError; }
      rethrow;
    }
  });

  Future<void> signIn(String identifier, String password) => _run((epoch) async {
    if (_retryAfter != null && DateTime.now().isBefore(_retryAfter!)) {
      throw const LoginFailure('Espera unos segundos antes de volver a intentarlo.');
    }
    _lastIdentifier = identifier;
    _signedOutByUser = false;
    phase = AuthPhase.signedOut;
    try {
      await repository!.signIn(identifier, password);
    } on LoginFailure {
      _failedAttempts++;
      if (_failedAttempts >= 5) _retryAfter = DateTime.now().add(const Duration(seconds: 30));
      rethrow;
    }
    if (epoch != _epoch) return;
    _failedAttempts = 0;
    _retryAfter = null;
    await _inspect(epoch);
  });

  Future<void> _inspect(int epoch) async {
    final checked = await repository!.inspect();
    if (epoch != _epoch || _disposed) return;
    identity = checked;
    if (checked == null) { _forget(); phase = AuthPhase.signedOut; return; }
    if (_lastIdentifier.isNotEmpty && checked.email.toLowerCase() != config.emailFor(_lastIdentifier).toLowerCase()) {
      throw const LoginFailure('La sesión cambió. Inicia sesión nuevamente.', sessionExpired: true);
    }
    if (!checked.emailVerified) { phase = AuthPhase.emailVerification; return; }
    if (checked.needsMfa) {
      organization = null;
      if (checked.verifiedFactorId != null) {
        enrollment = null;
        phase = AuthPhase.mfaChallenge;
      } else {
        final value = await repository!.enrollMfa();
        if (epoch != _epoch || _disposed) return;
        enrollment = value;
        phase = AuthPhase.mfaSetup;
      }
      return;
    }
    if (passwordRecoveryActive) { phase = AuthPhase.recovery; return; }
    if (checked.organizations.isEmpty) { organization = null; phase = AuthPhase.noMembership; return; }
    final previous = organization;
    if (previous != null && checked.organizations.any((e) => e.id == previous.id)) {
      await _authorize(checked.organizations.firstWhere((e) => e.id == previous.id), epoch);
      return;
    }
    if (checked.organizations.length > 1) { organization = null; phase = AuthPhase.chooseOrganization; return; }
    await _authorize(checked.organizations.single, epoch);
  }

  Future<void> _authorize(OrganizationAccess value, int epoch) async {
    await _clearing;
    if (epoch != _epoch || _disposed) return;
    await repository!.verifyBackend(value);
    if (epoch != _epoch || _disposed) return;
    organization = value;
    enrollment = null;
    phase = AuthPhase.ready;
  }

  Future<void> chooseOrganization(OrganizationAccess value) => _run((epoch) async {
    if (!(identity?.organizations.any((e) => e.id == value.id) ?? false)) {
      throw const LoginFailure('Esta organización no está disponible para tu cuenta.');
    }
    phase = AuthPhase.checking;
    await _authorize(value, epoch);
  });

  Future<void> verifyMfa(String code) => _run((epoch) async {
    final factor = enrollment?.factorId ?? identity?.verifiedFactorId;
    if (factor == null || !RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const LoginFailure('Escribe el código de seis dígitos de tu autenticador.');
    }
    await repository!.verifyMfa(factor, code);
    if (epoch != _epoch) return;
    await _inspect(epoch);
  });

  void showReset() { error = null; notice = null; passwordRecoveryActive = false; phase = AuthPhase.recovery; _notify(); }
  void backToLogin() { unawaited(signOut()); }

  Future<void> requestPasswordReset(String email) => _run((_) async {
    await repository!.requestPasswordReset(email.trim());
    notice = 'Si existe una cuenta con ese correo, recibirás las instrucciones para recuperar el acceso.';
  });

  Future<void> changePassword(String password) => _run((epoch) async {
    if (!passwordRecoveryActive) throw const LoginFailure('Abre primero el enlace de recuperación de tu correo.');
    await repository!.changePassword(password);
    await repository!.signOut();
    if (_disposed) return;
    _forget();
    phase = AuthPhase.signedOut;
    notice = 'Contraseña actualizada. Inicia sesión con tu nueva contraseña.';
  });

  Future<void> resendConfirmation() => _run((_) async {
    await repository!.resendConfirmation(identity?.email ?? config.emailFor(_lastIdentifier));
    notice = 'Si corresponde, recibirás un nuevo correo de confirmación.';
  });

  Future<void> signOut() async {
    _signedOutByUser = true;
    ++_epoch;
    _forget();
    phase = AuthPhase.signedOut;
    busy = false;
    error = null;
    _notify();
    try { await repository?.signOut().timeout(const Duration(seconds: 10)); } catch (_) {
      if (!_disposed) { notice = 'La sesión se cerró en este dispositivo. No se pudo confirmar la revocación remota.'; }
    } finally {
      await _clearing;
      _notify();
    }
  }

  void sessionRejected() {
    unawaited(signOut());
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _subscription?.cancel();
    repository?.dispose();
    super.dispose();
  }
}
