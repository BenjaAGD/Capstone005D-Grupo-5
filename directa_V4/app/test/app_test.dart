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
      if (p == '/api/consultar/') return _json('consultar.json');
      if (p.startsWith('/api/ruta-preguntas/')) return _json('ruta.json');
      if (p.startsWith('/api/preparar-reunion/') && p.endsWith('/respuestas')) return _json('preparar_resp.json');
      if (p.startsWith('/api/preparar-reunion/')) return _json('preparar.json');
      if (p == '/api/valoraciones') return _json('ok.json');
      if (p == '/api/valoraciones/resumen') return _json('valoraciones.json');
      if (p == '/api/lecciones') return _json('lecciones.json');
      if (p == '/api/memoria/perfil-tono') return _json('perfil_tono.json');
      if (p == '/api/memoria/anios') return _json('anios.json');
      if (p == '/api/memoria/sugerir') return _json('memsug.json');
      if (p == '/api/estado') return _json('estado.json');
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
    // El sello del verificador llega después de la respuesta, sin hacer esperar al gerente.
    final iVerif = partes.indexWhere((m) => m['verificacion'] is Map);
    expect(partes.indexWhere((m) => m['verificando'] == true), lessThan(iVerif));
    expect((partes[iVerif]['verificacion'] as Map)['estado'], 'verificada');
  });

  test('las 14 rutas de preguntas guía tienen 6 preguntas en tres niveles', () {
    final d = jsonDecode(fx('agentes.json')) as Map;
    final agentes = [for (final a in d['agentes'] as List) if (a['tipo'] != 'general') a];
    expect(agentes.length, 14);
    var total = 0;
    for (final a in agentes) {
      final guia = a['preguntas_guia'] as List;
      total += guia.length;
      for (final n in ['situacion', 'profundizacion', 'directorio']) {
        expect(guia.where((q) => q['nivel'] == n).length, 2, reason: '${a['clave']} $n');
      }
    }
    expect(total, 84);
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

    try {
      await _recorrido(tester, store, errores);
    } catch (e, pila) {
      // Se restaura el manejador antes de fallar, para que el mensaje real de la prueba se vea.
      FlutterError.onError = original;
      fail('$e\n${pila.toString().split('\n').take(6).join('\n')}\nErrores de dibujo: $errores');
    }
  });
}

Future<void> _recorrido(WidgetTester tester, Store store, List<String> errores) async {
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
    expect(find.textContaining('señales graves revisadas por el verificador'), findsOneWidget);
    final pestanaSenales = find.textContaining('Señales (');
    await tester.ensureVisible(pestanaSenales);
    await tester.tap(pestanaSenales);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Dependencia de proveedor único'), findsWidgets);
    expect(find.text('Sin respaldo'), findsWidgets); // la señal financiera con la cifra de otro año

    await tab('Preguntar');
    await tester.enterText(find.byType(TextField).last, '¿Qué riesgo tiene TechniPart?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('Modo demo', findRichText: true), findsWidgets);
    expect(find.text('Verificada'), findsOneWidget);
    expect(find.text('En el informe'), findsOneWidget);
    expect(find.byTooltip('Buena respuesta'), findsOneWidget);
    await tester.tap(find.text('Verificada'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('No comprueba que el documento sea cierto'), findsOneWidget);
    Navigator.of(tester.element(find.textContaining('No comprueba que el documento sea cierto'))).pop();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final st = tester.element(find.byType(Scaffold).first).read<AppState>();
    // Ruta de preguntas guía del agente: la que aborda la señal grave sube primero.
    st.cambiarAgente('operaciones');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('Ruta de Operaciones · 1 de 6'), findsOneWidget);
    expect(find.text('¿De qué proveedores o insumos críticos dependemos?'), findsOneWidget);
    expect(errores, isEmpty, reason: 'errores en el chat');

    // Asistente flotante desde Inicio
    await tab('Inicio');
    expect(find.text('Preparar mi reunión'), findsWidgets);
    await tester.tap(find.byTooltip('Asistente: ayuda y preguntas al documento'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Preguntar al documento'), findsOneWidget);
    await tester.tap(find.text('¿De qué trata el documento?').last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Llevar al chat'), findsOneWidget);
    await tester.tap(find.text('Ayuda de la app'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.text('¿Cómo preparo mi reunión?'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('verificador distinto', findRichText: true), findsOneWidget);
    expect(errores, isEmpty, reason: 'errores en el asistente');
    await tester.tap(find.byTooltip('Cerrar'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    for (final (id, titulo) in [
      ('preparar', 'PREGUNTAS PROBABLES DEL DIRECTORIO'),
      ('informe', 'Contenidos (1 / 1)'),
      ('dashboard', 'Semáforo por agente'),
      ('memoria', 'AÑO DE LA MEMORIA'),
      ('indicadores', 'KPI — ¿Cómo vamos?'),
      ('aprendizaje', 'POR REVISAR'),
      ('ajustes', 'SERVIDOR CONECTADO'),
    ]) {
      st.go(id);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.textContaining(titulo, findRichText: true), findsWidgets, reason: id);
      if (id == 'memoria') {
        for (final (pestana, texto) in [('Perfil de tono', 'MEMORIAS ANTERIORES PARA APRENDER EL TONO'), ('Capítulos', 'TEMAS QUE PIDE LA NORMA')]) {
          await tester.ensureVisible(find.text(pestana));
          await tester.tap(find.text(pestana));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          expect(find.textContaining(texto, findRichText: true), findsWidgets, reason: pestana);
        }
      }
      if (id == 'preparar') {
        await tester.tap(find.textContaining('Sugerir respuestas (').first);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(find.text('RESPUESTA SUGERIDA'), findsWidgets);
      }
      expect(errores, isEmpty, reason: 'errores en $id');
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
}
