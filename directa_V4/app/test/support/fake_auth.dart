import 'dart:async';

import 'package:directa_gg_app/auth/auth_config.dart';
import 'package:directa_gg_app/auth/auth_controller.dart';
import 'package:directa_gg_app/auth/auth_repository.dart';
import 'package:directa_gg_app/core/config.dart';

const testUser = '10000000-0000-4000-8000-000000000001';
const testTenant = '20000000-0000-4000-8000-000000000001';
const testOrganization = OrganizationAccess(id: testTenant, name: 'Directa laboratorio local', role: 'admin');

AuthConfig testConfig({bool account = false}) => AuthConfig(
  supabaseUrl: 'http://127.0.0.1:55421', publicKey: 'sb_publishable_test',
  apiUrl: Config.apiPorDefecto(), environment: 'local', testAccount: account,
  testAlias: 'admin', testEmail: 'admin@directa.local',
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.signedIn = false, this.mfa = false, this.membership = true});
  final signals = StreamController<AuthSignal>.broadcast(sync: true);
  bool signedIn, mfa, membership;
  bool backendAllowed = true;
  bool emailVerified = true;
  String? factorId;
  LoginFailure? loginError;
  Completer<void>? signInDelay;
  int signInCalls = 0, verifyBackendCalls = 0, resetCalls = 0;
  String token = 'token-de-prueba-solo-para-mocks';
  @override
  Stream<AuthSignal> get events => signals.stream;
  @override
  Future<void> signIn(String identifier, String password) async {
    signInCalls++;
    if (loginError != null) throw loginError!;
    if (signInDelay != null) await signInDelay!.future;
    signedIn = true;
    signals.add(AuthSignal.sessionAvailable);
  }
  @override
  Future<IdentityCheck?> inspect() async => signedIn ? IdentityCheck(
    userId: testUser, email: 'admin@directa.local', emailVerified: emailVerified,
    needsMfa: mfa, verifiedFactorId: factorId,
    organizations: membership && !mfa ? [testOrganization] : [],
  ) : null;
  @override
  Future<void> verifyBackend(OrganizationAccess organization) async {
    verifyBackendCalls++;
    if (!backendAllowed) throw const LoginFailure('El servidor rechazó la sesión.');
  }
  @override
  Future<MfaEnrollment> enrollMfa() async => const MfaEnrollment('factor-ficticio',
    'otpauth://totp/DIRECTA:demo?secret=JBSWY3DPEHPK3PXP&issuer=DIRECTA', 'JBSWY3DPEHPK3PXP');
  @override
  Future<void> verifyMfa(String factorId, String code) async {
    if (code != '123456') throw const LoginFailure('Código incorrecto.');
    mfa = false;
  }
  @override
  Future<void> requestPasswordReset(String email) async { resetCalls++; }
  @override
  Future<void> changePassword(String password) async {}
  @override
  Future<void> resendConfirmation(String email) async {}
  @override
  Future<void> signOut() async {
    signedIn = false;
    if (!signals.isClosed) signals.add(AuthSignal.signedOut);
  }
  @override
  Future<String> accessToken() async => token;
  @override
  void dispose() { signals.close(); }
}

AuthController testAuth({FakeAuthRepository? repository, bool localAccount = false}) =>
    AuthController(config: testConfig(account: localAccount), repository: repository ?? FakeAuthRepository(signedIn: true));
