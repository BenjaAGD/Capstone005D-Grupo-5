import 'package:http/http.dart' as http;

import 'auth_controller.dart';
import 'auth_repository.dart';

/// Un único transporte para GET/JSON, multipart, binarios y streaming SSE.
/// Nunca añade el token a un servidor elegido arbitrariamente en Ajustes.
class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient(this.auth, {http.Client? inner}) : _inner = inner ?? http.Client();
  final AuthController auth;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!auth.ready || auth.repository == null) {
      throw const LoginFailure('Inicia sesión para continuar.', sessionExpired: true);
    }
    if (!auth.config.allowsApi(request.url)) {
      throw const LoginFailure('El servidor configurado no está autorizado para esta sesión.');
    }
    final scope = auth.sessionKey;
    final token = await auth.repository!.accessToken();
    if (!auth.ready || auth.sessionKey != scope) {
      throw const LoginFailure('La sesión cambió. Vuelve a intentarlo.', sessionExpired: true);
    }
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['X-Directa-Tenant'] = auth.organization!.id;
    request.followRedirects = false;
    final response = await _inner.send(request);
    if (response.statusCode == 401) auth.sessionRejected();
    return response;
  }

  @override
  void close() => _inner.close();
}

/// Evita incluso solicitudes accidentales mientras la puerta de acceso está cerrada.
class ClosedSessionClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(const LoginFailure('Inicia sesión para continuar.', sessionExpired: true));
}
