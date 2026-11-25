import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/registro_screen.dart';
import 'core/config.dart';
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
  const DirectaApp({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
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
          create: (_) => AppState(store.forUser(user.id))..init(),
          child: const AppConSesion(),
        );
      },
    );
  }
}

/// La app una vez iniciada la sesión. Necesita un [AppState] más arriba en el árbol
/// (las pruebas lo crean con un cliente HTTP simulado).
class AppConSesion extends StatelessWidget {
  const AppConSesion({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AppState>(
        builder: (context, st, _) => MaterialApp(
          title: 'DIRECTA · Gerencia General',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: st.themeMode,
          // Respeta el tamaño de texto del sistema y le aplica el ajuste propio de la app (Ajustes).
          builder: (context, child) {
            final sistema = MediaQuery.textScalerOf(context).scale(1);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear((sistema * st.textScale).clamp(0.8, 1.6)),
              ),
              child: child!,
            );
          },
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
