import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:directa_gg_app/auth/auth_config.dart';
import 'package:directa_gg_app/auth/auth_repository.dart';
import 'package:directa_gg_app/auth/authenticated_client.dart';
import 'package:directa_gg_app/core/api.dart';
import 'package:directa_gg_app/core/store.dart';
import 'package:directa_gg_app/main.dart';
import 'support/fake_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('la cuenta local no se habilita en release, producción ni un host público', () {
    final local = testConfig(account: true);
    expect(local.validate(debugBuild: true, pageOrigin: Uri.parse('http://localhost:8085')), isNull);
    expect(local.validate(debugBuild: false, pageOrigin: Uri.parse('http://localhost:8085')), isNotNull);
    expect(local.validate(debugBuild: true, pageOrigin: Uri.parse('https://directa.example')), isNotNull);
    const remote = AuthConfig(supabaseUrl: 'https://project.supabase.co', publicKey: 'sb_publishable_test',
      apiUrl: 'https://directa.example', environment: 'production', testAccount: true, testAlias: 'admin', testEmail: 'admin@directa.local');
    expect(remote.validate(debugBuild: true), isNotNull);
  });
  test('la clave de servicio se rechaza antes de iniciar el cliente', () {
    const config = AuthConfig(supabaseUrl: 'https://p.supabase.co', publicKey: 'sb_secret_prohibida', apiUrl: 'https://app.example');
    expect(config.validate(), contains('pública'));
  });
  test('el alias de prueba deriva la contraseña y no acepta cualquier texto', () {
    final local = testConfig(account: true);
    expect(local.emailFor('admin'), 'admin@directa.local');
    expect(local.passwordFor('admin', 'admin'), AuthConfig.localTestPassword('admin'));
    expect(local.passwordFor('admin', 'incorrecta'), isNot(local.passwordFor('admin', 'admin')));
    expect(local.passwordFor('otra@empresa.cl', 'otra contraseña'), 'otra contraseña');
    expect(local.passwordFor('admin', 'admin').length, greaterThanOrEqualTo(12));
  });
  test('una identidad sin membresía no abre la app', () async {
    final repo = FakeAuthRepository(signedIn: true, membership: false);
    final auth = testAuth(repository: repo);
    await auth.checkSession();
    expect(auth.phase, AuthPhase.noMembership); expect(auth.ready, isFalse);
    expect(repo.verifyBackendCalls, 0); auth.dispose();
  });
  test('el rechazo del backend impide entrar aunque la cuenta sea válida', () async {
    final repo = FakeAuthRepository(signedIn: true)..backendAllowed = false;
    final auth = testAuth(repository: repo);
    await auth.checkSession();
    expect(auth.ready, isFalse); expect(auth.phase, AuthPhase.connectionError); auth.dispose();
  });
  test('el administrador no entra hasta verificar el segundo factor', () async {
    final repo = FakeAuthRepository(signedIn: true, mfa: true);
    final auth = testAuth(repository: repo);
    await auth.checkSession();
    expect(auth.phase, AuthPhase.mfaSetup); expect(auth.ready, isFalse);
    await auth.verifyMfa('999999'); expect(auth.ready, isFalse);
    await auth.verifyMfa('123456'); expect(auth.ready, isTrue);
    expect(repo.verifyBackendCalls, 1); auth.dispose();
  });
  test('el correo sin confirmar no abre datos privados', () async {
    final repo = FakeAuthRepository(signedIn: true)..emailVerified = false;
    final auth = testAuth(repository: repo); await auth.checkSession();
    expect(auth.phase, AuthPhase.emailVerification); expect(repo.verifyBackendCalls, 0); auth.dispose();
  });
  test('una respuesta tardía de login no reabre la cuenta después de salir', () async {
    final repo = FakeAuthRepository()..signInDelay = Completer<void>();
    final auth = testAuth(repository: repo, localAccount: true);
    final pending = auth.signIn('admin', 'admin');
    await auth.signOut();
    repo.signInDelay!.complete(); await pending; await Future<void>.delayed(Duration.zero);
    expect(auth.ready, isFalse); expect(auth.phase, AuthPhase.signedOut); auth.dispose();
  });
  test('la organización enviada arbitrariamente no se autoriza', () async {
    final repo = FakeAuthRepository(signedIn: true);
    final auth = testAuth(repository: repo); await auth.checkSession();
    final before = repo.verifyBackendCalls;
    await auth.chooseOrganization(const OrganizationAccess(id: 'ajena', name: 'Ajena', role: 'admin'));
    expect(auth.organization!.id, testTenant); expect(repo.verifyBackendCalls, before); auth.dispose();
  });
  test('la recuperación informa el mismo mensaje sin revelar cuentas', () async {
    final repo = FakeAuthRepository(); final auth = testAuth(repository: repo);
    auth.showReset(); await auth.requestPasswordReset('persona@empresa.cl');
    final first = auth.notice;
    await auth.requestPasswordReset('noexiste@empresa.cl');
    expect(auth.notice, first); expect(repo.resetCalls, 2); auth.dispose();
  });
  test('las preferencias privadas se separan por usuario y tenant y se limpian al salir', () async {
    SharedPreferences.setMockInitialValues({Store.kChats: 'legado sin identidad'});
    final base = await Store.open();
    final a = base.scoped('a', 'empresa1'), b = base.scoped('b', 'empresa1'), a2 = base.scoped('a', 'empresa2');
    await a.setString(Store.kChats, 'privado A'); await b.setString(Store.kChats, 'privado B');
    expect(a2.getString(Store.kChats), isNull); expect(base.publicOnly().getString(Store.kChats), isNull);
    await base.clearSession('a', 'empresa1');
    await a.setString(Store.kChats, 'escritura tardía');
    expect(base.scoped('a', 'empresa1').getString(Store.kChats), isNull);
    expect(b.getString(Store.kChats), 'privado B'); expect(base.getString(Store.kChats), 'legado sin identidad');
  });
  test('JSON, archivos y SSE usan el mismo JWT y organización sin redirecciones', () async {
    final auth = testAuth(); await auth.checkSession(); final requests = <http.Request>[];
    final transport = MockClient((r) async {
      requests.add(r);
      return http.Response(r.url.path == '/stream' ? 'data: {"chunk":"ok"}\n\n' : '{}', 200);
    });
    final api = Api(auth.config.apiUrl, client: AuthenticatedClient(auth, inner: transport));
    await api.getJson('/get'); await api.postJson('/json', {'a': 1});
    await api.upload('/upload', {'x': 'y'}, 'file', 'demo.txt', utf8.encode('demo'));
    await api.download('/pdf'); await api.sse('/stream', {}).toList();
    expect(requests.length, 5);
    for (final r in requests) {
      expect(r.headers['Authorization'], startsWith('Bearer '));
      expect(r.headers['X-Directa-Tenant'], testTenant); expect(r.followRedirects, isFalse);
    }
    api.close(); auth.dispose();
  });
  test('el token no se envía a un servidor externo', () async {
    final auth = testAuth(); await auth.checkSession(); var contacted = false;
    final transport = AuthenticatedClient(auth, inner: MockClient((r) async { contacted = true; return http.Response('{}', 200); }));
    await expectLater(transport.get(Uri.parse('https://otro.example/api/documentos')), throwsA(isA<LoginFailure>()));
    expect(contacted, isFalse); transport.close(); auth.dispose();
  });
  test('un 401 desmonta la sesión', () async {
    final auth = testAuth(); await auth.checkSession();
    final transport = AuthenticatedClient(auth, inner: MockClient((r) async => http.Response('{}', 401)));
    await transport.get(Uri.parse('${auth.config.apiUrl}/api/documentos'));
    expect(auth.ready, isFalse); transport.close(); auth.dispose();
  });
  test('un error del stream de Auth bloquea el acceso y revoca la caché anterior', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.open();
    final repo = FakeAuthRepository(signedIn: true);
    final auth = testAuth(repository: repo)..clearLocalSession = store.clearSession;
    await auth.checkSession();
    final previous = store.scoped(testUser, testTenant);
    await previous.setString(Store.kChats, 'sesión anterior');
    repo.signals.addError(StateError('fallo de red'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    expect(auth.ready, isFalse); expect(auth.phase, AuthPhase.connectionError);
    await previous.setString(Store.kChats, 'respuesta tardía');
    await auth.checkSession();
    expect(auth.ready, isTrue);
    expect(store.scoped(testUser, testTenant).getString(Store.kChats), isNull);
    auth.dispose();
  });
  test('volver a entrar espera a que termine la limpieza de la sesión anterior', () async {
    final repo = FakeAuthRepository(signedIn: true);
    final auth = testAuth(repository: repo, localAccount: true);
    await auth.checkSession();
    final cleaning = Completer<void>();
    auth.clearLocalSession = (_, _) => cleaning.future;
    final leaving = auth.signOut();
    final entering = auth.signIn('admin', 'admin');
    await Future<void>.delayed(Duration.zero);
    expect(auth.ready, isFalse);
    cleaning.complete();
    await Future.wait([leaving, entering]);
    expect(auth.ready, isTrue); auth.dispose();
  });
  testWidgets('login visible y cero llamadas al backend antes de autenticarse', (tester) async {
    SharedPreferences.setMockInitialValues({}); final store = await Store.open(); var calls = 0;
    await tester.pumpWidget(DirectaApp(store: store, auth: testAuth(repository: FakeAuthRepository(), localAccount: true),
      client: MockClient((r) async { calls++; return http.Response('{}', 200); })));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenido a DIRECTA'), findsOneWidget); expect(calls, 0);
    expect(find.text('Bienvenido al módulo de Gerencia General'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('error de credenciales mantiene el formulario y no carga documentos', (tester) async {
    SharedPreferences.setMockInitialValues({}); final store = await Store.open(); var calls = 0;
    final repo = FakeAuthRepository()..loginError = const LoginFailure('El correo o la contraseña no son correctos.');
    await tester.pumpWidget(DirectaApp(store: store, auth: testAuth(repository: repo, localAccount: true),
      client: MockClient((r) async { calls++; return http.Response('{}', 200); })));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('login-identifier')), 'admin');
    await tester.enterText(find.byKey(const ValueKey('login-password')), 'incorrecta');
    await tester.ensureVisible(find.byKey(const ValueKey('login-submit')));
    await tester.tap(find.byKey(const ValueKey('login-submit'))); await tester.pumpAndSettle();
    expect(find.text('El correo o la contraseña no son correctos.'), findsOneWidget); expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
