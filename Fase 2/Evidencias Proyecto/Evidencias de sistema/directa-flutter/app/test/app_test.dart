import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:directa_gg_app/core/api.dart';
import 'package:directa_gg_app/core/sev.dart';
import 'package:directa_gg_app/core/store.dart';
import 'package:directa_gg_app/main.dart';
import 'package:directa_gg_app/screens/indicadores_screen.dart' show semaforo;
import 'package:directa_gg_app/state/app_state.dart';

/// Respuestas guardadas del backend real (main.py en modo demo).
String fx(String n) => File('test/fixtures/$n').readAsStringSync();

http.Response _json(String n) => http.Response.bytes(utf8.encode(fx(n)), 200, headers: {'content-type': 'application/json'});

MockClient backendSimulado() => MockClient((req) async {
      final p = req.url.path;
      if (p == '/api/agentes') return _json('agentes.json');
      if (p == '/api/documentos') return _json('documentos.json');
      if (p.startsWith('/api/analisis-completos/')) return _json('analisis.json');
      if (p.startsWith('/api/dashboard-comparar/')) return _json('comparar.json');
      if (p.startsWith('/api/dashboard/')) return _json('dashboard.json');
      if (p == '/api/memoria/cobertura') return _json('memoria.json');
      if (p.startsWith('/api/indicadores/sugeridos/')) return _json('indicadores.json');
      if (p == '/api/sugerencias/') return _json('sug.json');
      if (p == '/api/guia/preguntar') return _json('guia.json');
      if (p == '/api/consultar-stream/') {
        return http.Response.bytes(utf8.encode(fx('stream.txt')), 200, headers: {'content-type': 'text/event-stream'});
      }
      return http.Response('{"ok":false,"error":"no simulado"}', 404);
    });

void main() {
  test('severidad y semáforo siguen las reglas del backend', () {
    expect(normSev('Crítica'), 'crítica');
    expect(normSev('ALTA'), 'alta');
    expect(normSev('crítica|alta|media|baja'), 'media');
    expect(semaforo(90, 75, 55, 'mayor'), 'verde');
    expect(semaforo(60, 75, 55, 'mayor'), 'amarillo');
    expect(semaforo(3, 0, 2, 'menor'), 'rojo');
    expect(semaforo(null, 1, 2, 'mayor'), 'sin_dato');
  });

  test('el chat lee el streaming SSE del backend', () async {
    final api = Api('http://x', client: backendSimulado());
    final partes = await api.sse('/api/consultar-stream/', {'pregunta': 'p', 'document_id': 'd'}).toList();
    final texto = partes.where((m) => m['chunk'] != null).map((m) => m['chunk']).join();
    expect(texto, startsWith('**Modo demo**'));
    expect(partes.any((m) => m['fuentes'] is List), isTrue);
  });

  testWidgets('recorre todas las pantallas con datos del backend', (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Cualquier error de dibujo (por ejemplo, un texto que no cabe) hace fallar la prueba.
    final errores = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) => errores.add(d.toString().split('\n').take(12).join('\n'));
    addTearDown(() => FlutterError.onError = original);
    SharedPreferences.setMockInitialValues({});
    final store = await Store.open();

    await tester.pumpWidget(DirectaApp(store: store, client: backendSimulado()));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Bienvenido al módulo de Gerencia General'), findsOneWidget);
    expect(find.text('Memoria_Anual_2024_Andes_Demo.pdf'), findsWidgets);

    Future<void> tab(String label) async {
      await tester.tap(find.text(label).last);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tab('Documentos');
    expect(find.textContaining('DOCUMENTOS CARGADOS (2)'), findsOneWidget);
    await tab('Resultados');
    expect(find.text('Resultados del análisis'), findsOneWidget);
    await tester.tap(find.textContaining('Señales (10)'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Dependencia de proveedor único'), findsWidgets);

    await tab('Preguntar');
    await tester.enterText(find.byType(TextField).last, '¿Qué riesgo tiene TechniPart?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('Modo demo', findRichText: true), findsWidgets);
    expect(find.text('En el informe'), findsOneWidget);

    final st = tester.element(find.byType(Scaffold).first).read<AppState>();
    for (final (id, titulo) in [
      ('informe', 'Contenidos (1 / 1)'),
      ('dashboard', 'Semáforo por agente'),
      ('memoria', 'TEMAS QUE PIDE LA NORMA'),
      ('indicadores', 'KPI — ¿Cómo vamos?'),
      ('guia', 'Guía de uso'),
      ('ajustes', 'DIRECCIÓN DEL BACKEND'),
    ]) {
      st.go(id);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.textContaining(titulo, findRichText: true), findsWidgets, reason: id);
      expect(errores, isEmpty, reason: 'errores en $id');
      Navigator.of(tester.element(find.textContaining(titulo, findRichText: true).first)).pop();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
  });
}
