enum AuthPhase { checking, signedOut, emailVerification, mfaSetup, mfaChallenge, chooseOrganization, noMembership, ready, recovery, connectionError, configurationError }
enum AuthSignal { signedOut, sessionAvailable, passwordRecovery }

class OrganizationAccess {
  const OrganizationAccess({required this.id, required this.name, required this.role});
  final String id, name, role;
  bool get privileged => role != 'director';
}

class IdentityCheck {
  const IdentityCheck({required this.userId, required this.email, this.emailVerified = true,
    this.needsMfa = false, this.verifiedFactorId, this.organizations = const []});
  final String userId, email;
  final bool emailVerified, needsMfa;
  final String? verifiedFactorId;
  final List<OrganizationAccess> organizations;
}

class MfaEnrollment {
  const MfaEnrollment(this.factorId, this.uri, this.secret);
  final String factorId, uri, secret;
}

class LoginFailure implements Exception {
  const LoginFailure(this.message, {this.emailUnconfirmed = false, this.sessionExpired = false});
  final String message;
  final bool emailUnconfirmed, sessionExpired;
  @override
  String toString() => message;
}

/// Implementación real en SupabaseAuthRepository. Las pruebas inyectan un doble
/// mediante constructor; no hay una bandera de producto que omita autenticación.
abstract class AuthRepository {
  Stream<AuthSignal> get events;
  Future<void> signIn(String identifier, String password);
  Future<IdentityCheck?> inspect();
  Future<void> verifyBackend(OrganizationAccess organization);
  Future<MfaEnrollment> enrollMfa();
  Future<void> verifyMfa(String factorId, String code);
  Future<void> requestPasswordReset(String email);
  Future<void> changePassword(String password);
  Future<void> resendConfirmation(String email);
  Future<void> signOut();
  Future<String> accessToken();
  void dispose();
}
