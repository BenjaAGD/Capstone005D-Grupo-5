// Ejercita el SDK real con respuestas HTTP simuladas. No verifica firmas ni
// sustituye una prueba end-to-end contra GoTrue y un autenticador real.
import 'dart:convert';

import 'package:directa_gg_app/auth/auth_config.dart';
import 'package:directa_gg_app/auth/auth_repository.dart';
import 'package:directa_gg_app/auth/supabase_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_auth.dart' show testUser, testTenant, testOrganization;

const config = AuthConfig(supabaseUrl: 'https://auth.example.invalid',
  publicKey: 'sb_publishable_test', apiUrl: 'https://directa.example.invalid');
const factor = '30000000-0000-4000-8000-000000000001';

class AuthProtocol {
  AuthProtocol({required this.verified});
  bool verified;
  int organizationReads = 0;
  Map<String, dynamic> get user => {
    'id': testUser, 'aud': 'authenticated', 'email': 'admin@directa.local',
    'email_confirmed_at': '2026-01-01T00:00:00Z', 'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': {'provider': 'email'}, 'user_metadata': {},
    'factors': <Object>[],
  };
  String get jwt {
    String encode(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${encode({'alg': 'HS256'})}.${encode({'sub': testUser, 'aud': 'authenticated',
      'role': 'authenticated', 'aal': verified ? 'aal2' : 'aal1',
      'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.test_signature';
  }
  Map<String, dynamic> get session => {'access_token': jwt, 'refresh_token': 'mock-refresh-token',
    'token_type': 'bearer', 'expires_in': 3600, 'user': user};
  http.Response json(Object data, [int status = 200, http.BaseRequest? request]) => http.Response(jsonEncode(data), status,
    headers: {'content-type': 'application/json'}, request: request);
  Future<http.Response> respond(http.Request request) async {
    http.Response reply(Object data, [int status = 200]) => json(data, status, request);
    final path = request.url.path;
    if (path == '/auth/v1/user') return reply(user);
    if (path == '/auth/v1/token') return reply(session);
    if (path == '/rest/v1/memberships') {
      expect(request.headers['Authorization'], startsWith('Bearer '));
      expect(request.url.queryParameters['user_id'], 'eq.$testUser');
      return reply([{'tenant_id': testTenant, 'role': 'admin'}]);
    }
    if (path == '/rest/v1/organizations') {
      organizationReads++;
      expect(verified, isTrue, reason: 'No consultar datos de organización antes de MFA.');
      return reply([{'id': testTenant, 'name': testOrganization.name}]);
    }
    if (path == '/auth/v1/factors' && request.method == 'POST') {
      return reply({'id': factor, 'type': 'totp', 'totp': {
        'qr_code': '<svg/>', 'secret': 'JBSWY3DPEHPK3PXP',
        'uri': 'otpauth://totp/DIRECTA:demo?secret=JBSWY3DPEHPK3PXP&issuer=DIRECTA',
      }});
    }
    if (path == '/auth/v1/factors/$factor/challenge') {
      return reply({'id': '40000000-0000-4000-8000-000000000001',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60});
    }
    if (path == '/auth/v1/factors/$factor/verify') {
      final payload = jsonDecode(request.body) as Map;
      if (payload['code'] != '123456') return reply({'code': 'mfa_verification_failed', 'msg': 'Código incorrecto'}, 422);
      verified = true;
      return reply(session);
    }
    throw StateError('Ruta HTTP simulada no prevista: ${request.method} $path');
  }
}

void main() {
  for (final verified in [true, false]) {
    test('SDK Supabase real: ${verified ? 'sesión AAL2' : 'enrolamiento y desafío MFA'} y verificación del backend', () async {
      final protocol = AuthProtocol(verified: verified);
      final sdk = SupabaseClient(config.supabaseUrl, config.publicKey,
        httpClient: MockClient(protocol.respond), authOptions: const AuthClientOptions(autoRefreshToken: false));
      await sdk.auth.setInitialSession(jsonEncode(protocol.session));
      var backendStatus = 200;
      final backend = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer ${protocol.jwt}');
        expect(request.headers['X-Directa-Tenant'], testTenant);
        expect(request.followRedirects, isFalse);
        return protocol.json({'verified': true, 'user_id': testUser, 'tenant_id': testTenant}, backendStatus);
      });
      final repository = SupabaseAuthRepository(sdk, config, httpClient: backend);
      try {
        var identity = (await repository.inspect())!;
        if (!verified) {
          expect(identity.needsMfa, isTrue); expect(protocol.organizationReads, 0);
          final enrollment = await repository.enrollMfa();
          expect(enrollment.factorId, factor);
          await expectLater(repository.verifyMfa(factor, '999999'), throwsA(isA<LoginFailure>()));
          expect(protocol.verified, isFalse);
          await repository.verifyMfa(factor, '123456');
          identity = (await repository.inspect())!;
        }
        expect(identity.needsMfa, isFalse);
        expect(identity.organizations.single.id, testTenant);
        await repository.verifyBackend(identity.organizations.single);
        backendStatus = 302;
        await expectLater(repository.verifyBackend(identity.organizations.single), throwsA(isA<LoginFailure>()));
      } finally {
        repository.dispose();
        await sdk.dispose();
      }
    });
  }
}
