import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/config.dart';

/// Solo configuración pública. Ninguna service_role ni contraseña se compila.
class AuthConfig {
  const AuthConfig({
    required this.supabaseUrl,
    required this.publicKey,
    required this.apiUrl,
    this.environment = 'production',
    this.testAccount = false,
    this.testAlias = '',
    this.testEmail = '',
    this.recoveryUrl = '',
  });

  factory AuthConfig.fromEnvironment() => AuthConfig(
        supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
        publicKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
        apiUrl: Config.apiPorDefecto(),
        environment: const String.fromEnvironment('DIRECTA_ENV', defaultValue: 'production'),
        testAccount: const bool.fromEnvironment('DIRECTA_LOCAL_TEST_ACCOUNT'),
        testAlias: const String.fromEnvironment('DIRECTA_LOCAL_LOGIN'),
        testEmail: const String.fromEnvironment('DIRECTA_LOCAL_EMAIL'),
        recoveryUrl: const String.fromEnvironment('AUTH_REDIRECT_URL'),
      );

  final String supabaseUrl, publicKey, apiUrl, environment;
  final bool testAccount;
  final String testAlias, testEmail, recoveryUrl;

  static bool loopback(Uri uri) =>
      const {'localhost', '127.0.0.1', '::1', '[::1]', '10.0.2.2'}.contains(uri.host.toLowerCase());

  /// La excepción de prueba exige simultáneamente debug, localhost y Auth local.
  String? validate({bool? debugBuild, Uri? pageOrigin}) {
    if (supabaseUrl.isEmpty || publicKey.isEmpty) return 'Falta conectar Supabase para habilitar el acceso.';
    final auth = Uri.tryParse(supabaseUrl);
    final api = Uri.tryParse(apiUrl);
    if (auth == null || api == null || !auth.hasAuthority || !api.hasAuthority ||
        auth.userInfo.isNotEmpty || api.userInfo.isNotEmpty || auth.hasQuery || auth.hasFragment) {
      return 'La configuración del entorno no es válida.';
    }
    final local = environment == 'local' && (debugBuild ?? kDebugMode);
    if ((auth.scheme != 'https' && !(local && loopback(auth))) ||
        (api.scheme != 'https' && !(local && loopback(api)))) {
      return 'Este entorno requiere conexiones HTTPS.';
    }
    if (publicKey.startsWith('sb_secret_')) return 'Configura la clave pública de Supabase.';
    if (publicKey.split('.').length == 3) {
      try {
        final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(publicKey.split('.')[1])))) as Map;
        if (claims['role'] != 'anon') return 'Configura la clave pública de Supabase.';
      } catch (_) {
        return 'La clave pública de Supabase no es válida.';
      }
    } else if (!publicKey.startsWith('sb_publishable_')) {
      return 'La clave pública de Supabase no es válida.';
    }
    if (testAccount) {
      final origin = pageOrigin ?? (kIsWeb ? Uri.base : null);
      if (!local || !loopback(auth) || !loopback(api) ||
          (origin != null && !loopback(origin)) || testAlias.isEmpty || !testEmail.contains('@')) {
        return 'La cuenta de pruebas solo está disponible en el entorno local de desarrollo.';
      }
    }
    if (recoveryUrl.isNotEmpty) {
      final redirect = Uri.tryParse(recoveryUrl);
      if (redirect == null || (kIsWeb && (!redirect.hasAuthority ||
          !const {'http', 'https'}.contains(redirect.scheme) || redirect.origin != (pageOrigin ?? Uri.base).origin))) {
        return 'La dirección de recuperación no pertenece a este entorno.';
      }
    }
    return null;
  }

  bool isTestIdentifier(String input) => testAccount &&
      (input.trim().toLowerCase() == testAlias.toLowerCase() || input.trim().toLowerCase() == testEmail.toLowerCase());

  String emailFor(String input) => isTestIdentifier(input) ? testEmail : input.trim().toLowerCase();

  String passwordFor(String input, String password) => isTestIdentifier(input)
      ? localTestPassword(password)
      : password;

  /// Adaptación EXCLUSIVA de pruebas: GoTrue exige al menos seis caracteres.
  /// El bootstrap registra exactamente esta derivación; Auth sigue validándola.
  /// No se acepta ninguna contraseña sin consultar a Supabase, ni se omite MFA.
  static String localTestPassword(String input) =>
      sha256.convert(utf8.encode('DIRECTA_LOCAL_PASSWORD_V1\u0000$input')).toString();

  String get redirectTo => recoveryUrl.isNotEmpty
      ? recoveryUrl
      : (kIsWeb ? '${Uri.base.origin}/' : 'directa://auth-callback');

  bool allowsApi(Uri uri) {
    final allowed = Uri.tryParse(apiUrl);
    return allowed != null && allowed.hasAuthority && uri.hasAuthority &&
        uri.origin == allowed.origin && uri.userInfo.isEmpty;
  }
}
