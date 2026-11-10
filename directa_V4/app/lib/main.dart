import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'core/store.dart';
import 'core/theme.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  runApp(DirectaApp(store: store));
}

class DirectaApp extends StatelessWidget {
  const DirectaApp({super.key, required this.store, this.client});
  final Store store;

  /// Solo para pruebas: cliente HTTP simulado.
  final http.Client? client;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(store, client: client)..init(),
      child: Consumer<AppState>(
        builder: (context, st, _) => MaterialApp(
          title: 'DIRECTA · Gerencia General',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: st.themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(st.textScale)),
            child: child!,
          ),
          home: st.iniciado ? const Shell() : const _Cargando(),
        ),
      ),
    );
  }
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
