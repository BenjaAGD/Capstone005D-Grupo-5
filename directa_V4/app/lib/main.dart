import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_config.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_repository.dart';
import 'auth/authenticated_client.dart';
import 'auth/secure_session_storage.dart';
import 'auth/supabase_auth_repository.dart';
import 'core/store.dart';
import 'core/theme.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  final config = AuthConfig.fromEnvironment();
  var error = config.validate();
  AuthRepository? repository;
  if (error == null) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl, publishableKey: config.publicKey, debug: false,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce, autoRefreshToken: true,
          localStorage: SecureSessionStorage(config.supabaseUrl),
        ),
      );
      repository = SupabaseAuthRepository(Supabase.instance.client, config);
    } catch (_) { error = 'No se pudo iniciar la conexión de acceso. Comprueba la configuración del entorno.'; }
  }
  runApp(DirectaApp(store: store,
      auth: AuthController(config: config, repository: repository, configurationError: error)));
}

class DirectaApp extends StatelessWidget {
  const DirectaApp({super.key, required this.store, this.client, this.auth});
  final Store store;
  final http.Client? client;
  final AuthController? auth;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<AuthController>(
    create: (_) {
      final controller = auth ?? AuthController(config: AuthConfig.fromEnvironment(),
          configurationError: 'Falta conectar Supabase para habilitar el acceso.');
      controller.clearLocalSession = store.clearSession;
      unawaited(controller.checkSession());
      return controller;
    },
    child: Consumer<AuthController>(builder: (context, access, _) => ChangeNotifierProvider<AppState>(
      key: ValueKey(access.sessionKey),
      create: (_) {
        final state = AppState(
          access.ready ? store.scoped(access.identity!.userId, access.organization!.id) : store.publicOnly(),
          client: access.ready ? AuthenticatedClient(access, inner: client) : ClosedSessionClient(),
          isAllowedApiUrl: access.config.allowsApi,
        );
        if (access.ready) unawaited(state.init());
        return state;
      },
      child: Consumer<AppState>(builder: (context, st, _) => MaterialApp(
        title: 'DIRECTA · Gerencia General', debugShowCheckedModeBanner: false,
        theme: AppTheme.build(Brightness.light), darkTheme: AppTheme.build(Brightness.dark), themeMode: st.themeMode,
        builder: (context, child) => _SessionLifecycle(child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(st.textScale)), child: child!)),
        home: access.ready ? (st.iniciado ? const Shell() : const _Cargando()) : const LoginScreen(),
      )),
    )),
  );
}

class _SessionLifecycle extends StatefulWidget {
  const _SessionLifecycle({required this.child});
  final Widget child;
  @override
  State<_SessionLifecycle> createState() => _SessionLifecycleState();
}

class _SessionLifecycleState extends State<_SessionLifecycle> with WidgetsBindingObserver {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final auth = context.read<AuthController>();
      if (auth.ready && !auth.busy) unawaited(auth.checkSession(background: true));
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthController>();
    if (state == AppLifecycleState.resumed && auth.ready && !auth.busy) unawaited(auth.checkSession());
  }
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => widget.child;
}

class _Cargando extends StatelessWidget {
  const _Cargando();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [CircularProgressIndicator(), SizedBox(height: 14), Text('Preparando tu espacio de gestión…')],
  )));
}
