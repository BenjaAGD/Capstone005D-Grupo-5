import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/registro_screen.dart';
import 'core/config.dart';
import 'core/demo_modo.dart';
import 'core/servidor_estado.dart';
import 'core/store.dart';
import 'core/theme.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('SUPABASE_PUBLIC_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLIC_KEY');

  if (url.isEmpty || key.isEmpty) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Falta configurar SUPABASE_PUBLIC_URL y SUPABASE_PUBLIC_KEY.',
          ),
        ),
      ),
    ));
    return;
  }

  final recovery = isRecoveryLocation(Uri.base);

await Supabase.initialize(
  url: url,
  publishableKey: key,
);
  final store = await Store.open();
  // Despierta el servidor (Render) en segundo plano. SIN await: no demora la entrada a la app.
  ServidorEstado.instance.iniciar(Config.apiPorDefecto());
  runApp(
  AuthRecoveryGate(
    initialRecovery: recovery,
    child: DirectaApp(store: store),
  ),
);
}

class DirectaApp extends StatelessWidget {
  const DirectaApp({super.key, required this.store, this.client});
  final Store store;

  /// Solo para pruebas: cliente HTTP simulado.
  final http.Client? client;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: DemoModo.instance,
        builder: (context, _) => DemoModo.instance.activo ? _demo() : _conSesion(),
      );

  /// Acceso demo: entra sin sesión de Supabase, pero la app usa el servidor con normalidad.
  Widget _demo() => ChangeNotifierProvider(
        key: const ValueKey('demo'),
        create: (_) => AppState(store.forUser('demo'), client: client)..init(),
        child: _materialApp(),
      );

  Widget _conSesion() {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = auth.currentSession;
        final user = session?.user;

        if (snapshot.hasError ||
            session == null ||
            session.isExpired ||
            user?.emailConfirmedAt == null) {
          return MaterialApp(
            key: const ValueKey('login'),
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(Brightness.light),
            home: const LoginScreen(),
          );
        }

        return ChangeNotifierProvider(
          key: ValueKey(user!.id),
          create: (_) =>
              AppState(store.forUser(user.id), client: client)..init(),
          child: _materialApp(),
        );
      },
    );
  }

  Widget _materialApp() => Consumer<AppState>(
        builder: (context, st, _) => MaterialApp(
          title: 'DIRECTA · Gerencia General',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: st.themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(st.textScale),
            ),
            child: child!,
          ),
          home: st.iniciado ? const Shell() : const _Cargando(),
        ),
      );
}

class _Cargando extends StatelessWidget {
  const _Cargando();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Conectando con el servidor…'),
          ]),
        ),
      );
}
