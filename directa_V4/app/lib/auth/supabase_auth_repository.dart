import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_config.dart';
import 'auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client, this.config, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();
  final SupabaseClient client;
  final AuthConfig config;
  final http.Client _http;
  static const _roles = {'owner', 'admin', 'gerente_general', 'secretaria', 'director'};

  @override
  Stream<AuthSignal> get events => client.auth.onAuthStateChange.expand((change) {
    switch (change.event) {
      case AuthChangeEvent.signedOut: return const [AuthSignal.signedOut];
      case AuthChangeEvent.passwordRecovery: return const [AuthSignal.passwordRecovery];
      case AuthChangeEvent.signedIn: return const [AuthSignal.sessionAvailable];
      default: return const <AuthSignal>[];
    }
  });

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 25));
    } on AuthException catch (e) {
      switch (e.code) {
        case 'email_not_confirmed':
          throw const LoginFailure('Confirma tu correo antes de continuar.', emailUnconfirmed: true);
        case 'user_banned': case 'user_disabled':
          throw const LoginFailure('Esta cuenta no tiene el acceso habilitado. Contacta al administrador.');
        case 'mfa_verification_failed': case 'mfa_challenge_expired':
          throw const LoginFailure('El código no es válido o ya expiró. Intenta con uno nuevo.');
        case 'over_request_rate_limit': case 'over_email_send_rate_limit': case 'over_sms_send_rate_limit':
          throw const LoginFailure('Demasiados intentos. Espera un momento y vuelve a intentarlo.');
        case 'refresh_token_not_found': case 'refresh_token_already_used': case 'session_not_found': case 'session_expired': case 'bad_jwt':
          throw const LoginFailure('Tu sesión terminó. Inicia sesión nuevamente.', sessionExpired: true);
        default:
          throw const LoginFailure('No pudimos completar la verificación. Revisa tus datos e inténtalo nuevamente.');
      }
    } on PostgrestException {
      throw const LoginFailure('No pudimos comprobar los permisos de la cuenta. Contacta al administrador.');
    } on TimeoutException {
      throw const LoginFailure('La verificación tardó demasiado. Comprueba tu conexión e inténtalo nuevamente.');
    } on http.ClientException {
      throw const LoginFailure('No se pudo conectar para verificar tu acceso.');
    }
  }

  @override
  Future<void> signIn(String identifier, String password) => _guard(() async {
    final error = config.validate();
    if (error != null) throw LoginFailure(error);
    try {
      await client.auth.signInWithPassword(
        email: config.emailFor(identifier), password: config.passwordFor(identifier, password));
    } on AuthException catch (e) {
      if (e.code == 'invalid_credentials' || e.code == 'user_not_found' || e.code == 'invalid_grant') {
        throw const LoginFailure('El correo o la contraseña no son correctos.');
      }
      rethrow;
    }
  });

  @override
  Future<String> accessToken() => _guard(() async {
    var session = client.auth.currentSession;
    if (session == null) throw const LoginFailure('Inicia sesión para continuar.', sessionExpired: true);
    if ((session.expiresAt ?? 0) <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30) {
      session = (await client.auth.refreshSession()).session;
    }
    if (session == null || session.isExpired) {
      throw const LoginFailure('Tu sesión terminó. Inicia sesión nuevamente.', sessionExpired: true);
    }
    return session.accessToken;
  });

  @override
  Future<IdentityCheck?> inspect() => _guard(() async {
    if (client.auth.currentSession == null) return null;
    final token = await accessToken();
    // getUser consulta Auth: no autorizar usando solo la sesión del disco.
    final user = (await client.auth.getUser(token)).user;
    if (user == null || user.email == null) {
      throw const LoginFailure('No se pudo verificar tu identidad.', sessionExpired: true);
    }
    if (user.emailConfirmedAt == null) {
      return IdentityCheck(userId: user.id, email: user.email!, emailVerified: false);
    }
    final rows = await client.from('memberships').select('tenant_id,role').eq('user_id', user.id).eq('active', true);
    if (rows.any((row) => !_roles.contains(row['role']))) {
      throw const LoginFailure('La cuenta tiene un permiso que debe revisar el administrador.');
    }
    final factors = await client.auth.mfa.listFactors();
    final level = client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel;
    final needMfa = level != AuthenticatorAssuranceLevels.aal2 &&
        (rows.any((row) => row['role'] != 'director') || factors.all.any((f) => f.status == FactorStatus.verified));
    if (needMfa) {
      if (factors.totp.isEmpty && factors.all.any((f) => f.status == FactorStatus.verified)) {
        throw const LoginFailure('Tu cuenta requiere un método de verificación que debe habilitar el administrador.');
      }
      return IdentityCheck(userId: user.id, email: user.email!, needsMfa: true,
        verifiedFactorId: factors.totp.isEmpty ? null : factors.totp.first.id);
    }
    if (rows.isEmpty) return IdentityCheck(userId: user.id, email: user.email!);
    final organizations = await client.from('organizations').select('id,name').eq('active', true)
        .inFilter('id', rows.map((r) => '${r['tenant_id']}').toList());
    return IdentityCheck(userId: user.id, email: user.email!, organizations: [
      for (final org in organizations)
        OrganizationAccess(id: '${org['id']}', name: '${org['name']}',
          role: '${rows.firstWhere((r) => r['tenant_id'] == org['id'])['role']}'),
    ]);
  });

  @override
  Future<void> verifyBackend(OrganizationAccess organization) => _guard(() async {
    final url = Uri.parse('${config.apiUrl.replaceAll(RegExp(r'/+$'), '')}/api/auth/session');
    if (!config.allowsApi(url)) throw const LoginFailure('El servidor configurado no está autorizado para esta sesión.');
    final request = http.Request('GET', url)..followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer ${await accessToken()}', 'X-Directa-Tenant': organization.id,
    });
    final response = await http.Response.fromStream(await _http.send(request));
    if (response.statusCode == 401) {
      throw const LoginFailure('El servidor no pudo verificar tu sesión.', sessionExpired: true);
    }
    if (response.statusCode == 403) throw const LoginFailure('Tu cuenta no tiene acceso activo a esta organización.');
    if (response.statusCode != 200) throw const LoginFailure('No se pudo conectar con Directa para completar el acceso.');
    final data = jsonDecode(response.body) as Map;
    if (data['user_id'] != client.auth.currentUser?.id || data['tenant_id'] != organization.id || data['verified'] != true) {
      throw const LoginFailure('La verificación del servidor no corresponde a esta sesión.');
    }
  });

  @override
  Future<MfaEnrollment> enrollMfa() => _guard(() async {
    final factors = await client.auth.mfa.listFactors();
    for (final factor in factors.all) {
      if (factor.status == FactorStatus.unverified && factor.friendlyName == 'DIRECTA acceso') {
        await client.auth.mfa.unenroll(factor.id);
      }
    }
    final result = await client.auth.mfa.enroll(issuer: 'DIRECTA', friendlyName: 'DIRECTA acceso');
    final totp = result.totp;
    if (totp == null) throw const LoginFailure('No se pudo preparar el autenticador. Inténtalo nuevamente.');
    return MfaEnrollment(result.id, totp.uri, totp.secret);
  });

  @override
  Future<void> verifyMfa(String factorId, String code) => _guard(() async {
    await client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  });

  @override
  Future<void> requestPasswordReset(String email) => _guard(() async {
    try { await client.auth.resetPasswordForEmail(email, redirectTo: config.redirectTo); }
    on AuthException catch (e) {
      if (!const {'user_not_found', 'email_not_found'}.contains(e.code)) rethrow;
    }
  });

  @override
  Future<void> changePassword(String password) => _guard(() async {
    if (password.length < 12) throw const LoginFailure('Usa una contraseña de al menos 12 caracteres.');
    await client.auth.updateUser(UserAttributes(password:
      config.passwordFor(client.auth.currentUser?.email ?? '', password)));
  });

  @override
  Future<void> resendConfirmation(String email) => _guard(() async {
    await client.auth.resend(type: OtpType.signup, email: email, emailRedirectTo: config.redirectTo);
  });

  @override
  Future<void> signOut() => client.auth.signOut(scope: SignOutScope.local);

  @override
  void dispose() => _http.close();
}
