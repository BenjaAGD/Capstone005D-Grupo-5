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
import 'package:directa_gg_app/core/theme.dart';
import 'package:directa_gg_app/main.dart';
import 'package:directa_gg_app/screens/bloqueo_screen.dart';
import 'package:directa_gg_app/screens/indicadores_screen.dart' show semaforo;
import 'package:directa_gg_app/screens/login_screen.dart';
import 'package:directa_gg_app/screens/registro_screen.dart';
import 'package:directa_gg_app/state/app_state.dart';

/// Respuestas guardadas del backend (test/fixtures).
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

/// Tamaños de celular en vertical que debe soportar la app (dp).
const tamanos = [Size(360, 640), Size(430, 932)];

/// Tamaño de texto del sistema más grande que debe soportar la app sin desbordes.
const textoSistema = 1.3;

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
    expect(texto, startsWith('**Respuesta**'));
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

  for (final tam in tamanos) {
    final nombre = '${tam.width.toInt()}x${tam.height.toInt()}';

    testWidgets('bloqueo con PIN cabe con letra grande y teclado abierto ($nombre, texto ${textoSistema}x)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _enCelular(tester, tam, () async {
        final pantallas = <Widget>[
          PantallaBloqueo(uid: 'u1', onAbierta: () {}),
          const CrearPinScreen(),
          const ConfirmarPinScreen(uid: 'u1'),
        ];
        for (final pantalla in pantallas) {
          _paso('${pantalla.runtimeType} $nombre');
          await tester.pumpWidget(MaterialApp(theme: AppTheme.build(Brightness.light), home: pantalla));
          await _esperar(tester, 2);
          tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
          await _esperar(tester, 2);
          tester.view.resetViewInsets();
          await _esperar(tester, 2);
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('login y registro caben con el teclado abierto ($nombre, texto ${textoSistema}x)', (tester) async {
      await _enCelular(tester, tam, () async {
        for (final pantalla in const [LoginScreen(), RegistroScreen()]) {
          _paso('${pantalla.runtimeType} $nombre');
          await tester.pumpWidget(MaterialApp(theme: AppTheme.build(Brightness.light), home: pantalla));
          await _esperar(tester, 2);
          // Teclado abierto: unos 300 dp desde abajo.
          tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
          await _esperar(tester, 2);
          tester.view.resetViewInsets();
          await _esperar(tester, 2);
          expect(find.textContaining('demo'), findsNothing);
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('recorre todas las pantallas con datos del backend ($nombre, texto ${textoSistema}x)', (tester) async {
      SharedPreferences.setMockInitialValues({Store.kFont: 1.0});
      final store = await Store.open();
      await _enCelular(tester, tam, () => _recorrido(tester, store));
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}

/// Errores de dibujo de la prueba en curso (por ejemplo un "RenderFlex overflowed").
final _errores = <String>[];

void _paso(String texto) => debugPrint('· $texto');

void _sinErrores(String donde) {
  if (_errores.isNotEmpty) {
    final detalle = _errores.join('\n---\n');
    _errores.clear();
    fail('errores de dibujo en $donde:\n$detalle');
  }
}

/// Fija el tamaño del celular y el texto del sistema, junta los errores de dibujo y
/// deja todo como estaba antes de terminar (aunque la prueba falle).
Future<void> _enCelular(WidgetTester tester, Size tam, Future<void> Function() cuerpo) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = tam * 3;
  tester.platformDispatcher.textScaleFactorTestValue = textoSistema;
  _errores.clear();
  final original = FlutterError.onError;
  FlutterError.onError = (d) => _errores.add(d.toString().split('\n').take(14).join('\n'));
  try {
    await cuerpo();
    _sinErrores('el final');
  } finally {
    FlutterError.onError = original;
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  }
}

Future<void> _esperar(WidgetTester tester, [int veces = 6]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _recorrido(WidgetTester tester, Store store) async {
  await tester.pumpWidget(ChangeNotifierProvider(
    create: (_) => AppState(store, client: backendSimulado())..init(),
    child: const AppConSesion(),
  ));
  await _esperar(tester, 10);
  expect(find.text('Hola, Gerencia'), findsWidgets);
  expect(find.text('Memoria_Anual_2024_Andes.pdf'), findsWidgets);
  expect(find.byType(NavigationRail), findsNothing);
  expect(find.byType(NavigationBar), findsOneWidget);
  _sinErrores('errores en Inicio');

  Future<void> tab(String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await _esperar(tester);
  }

  final st = tester.element(find.byType(Scaffold).first).read<AppState>();

  // Análisis: hallazgos
  _paso('Análisis');
  await tab('Análisis');
  expect(find.textContaining('señales graves revisadas por el verificador'), findsOneWidget);
  final pestanaSenales = find.textContaining('Señales (');
  await tester.ensureVisible(pestanaSenales);
  await tester.tap(pestanaSenales);
  await _esperar(tester, 2);
  expect(find.textContaining('Dependencia de proveedor único'), findsWidgets);
  _sinErrores('errores en Hallazgos');

  // Análisis: chat con el teclado abierto
  _paso('Chat');
  // Barra de Análisis: Hallazgos · Guía · Chat.
  await tester.tap(find.widgetWithText(TextButton, 'Guía'));
  await _esperar(tester);
  await tester.tap(find.widgetWithText(TextButton, 'Chat'));
  await _esperar(tester, 2);
  await tester.enterText(find.byType(TextField).last, '¿Qué riesgo tiene TechniPart?');
  tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
  await _esperar(tester, 2);
  // El campo de texto y el botón de enviar quedan sobre el teclado.
  final tecladoArriba = tester.view.physicalSize.height / tester.view.devicePixelRatio - 300;
  expect(tester.getRect(find.byTooltip('Enviar pregunta')).bottom, lessThanOrEqualTo(tecladoArriba));
  expect(tester.getRect(find.byType(TextField).last).bottom, lessThanOrEqualTo(tecladoArriba));
  await tester.tap(find.byTooltip('Enviar pregunta'));
  await _esperar(tester, 10);
  tester.view.resetViewInsets();
  await _esperar(tester, 2);
  expect(find.textContaining('fragmentos revisados', findRichText: true), findsWidgets);
  expect(find.text('Verificada'), findsOneWidget);
  await tester.tap(find.text('Verificada'));
  await _esperar(tester, 4);
  expect(find.textContaining('No comprueba que el documento sea cierto'), findsOneWidget);
  Navigator.of(tester.element(find.textContaining('No comprueba que el documento sea cierto'))).pop();
  await _esperar(tester, 4);
  st.cambiarAgente('operaciones');
  await _esperar(tester);
  _sinErrores('errores en el chat');

  // Asistente flotante desde Inicio
  _paso('Asistente');
  await tab('Inicio');
  await tester.tap(find.byTooltip('Asistente: ayuda y preguntas al documento'));
  await _esperar(tester);
  expect(find.text('Preguntar al documento'), findsOneWidget);
  final hoja = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(find.text('¿De qué trata el documento?'), 120, scrollable: hoja);
  await tester.tap(find.text('¿De qué trata el documento?').last);
  await _esperar(tester, 8);
  expect(find.text('Llevar al chat'), findsOneWidget);
  await tester.tap(find.text('Ayuda de la app'));
  await _esperar(tester, 4);
  await tester.scrollUntilVisible(find.text('¿Cómo preparo mi reunión?'), 120,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
  await tester.tap(find.text('¿Cómo preparo mi reunión?'));
  await _esperar(tester);
  expect(find.textContaining('verificador distinto', findRichText: true), findsOneWidget);
  _sinErrores('errores en el asistente');
  await tester.tap(find.byTooltip('Cerrar'));
  await _esperar(tester);

  // Pestañas principales
  for (final (label, titulo) in const [
    ('Memoria', '¿Qué quieres hacer?'),
    ('Gestión', 'Informe del directorio'),
    ('Más', 'Ajustes y estado del sistema'),
  ]) {
    _paso(label);
    await tab(label);
    expect(find.textContaining(titulo, findRichText: true), findsWidgets, reason: label);
    _sinErrores('errores en $label');
  }
  await tab('Memoria');
  for (final (pestana, texto) in const [
    ('2 · Estilo', 'MEMORIAS ANTERIORES PARA APRENDER EL TONO'),
    ('3 · Crear memoria', '¿QUÉ MEMORIA QUIERES PREPARAR?'),
    ('1 · Fuentes y avance', 'COBERTURA NCG 461'),
  ]) {
    _paso('Memoria · $pestana');
    await tester.ensureVisible(find.text(pestana));
    await tester.tap(find.text(pestana));
    await _esperar(tester, 8);
    expect(find.textContaining(texto, findRichText: true), findsWidgets, reason: pestana);
    _sinErrores('errores en Memoria · $pestana');
  }

  // Pantallas secundarias (se abren desde Más y Gestión)
  for (final (id, titulo) in const [
    ('documentos', 'DOCUMENTOS CARGADOS (2)'),
    ('archivos', 'Archivos descargados'),
    ('preparar', 'Revisa las preguntas clave'),
    ('informe', 'Contenido del informe'),
    ('dashboard', 'PREPARACIÓN GLOBAL'),
    ('diagnosticos', 'Detalle del análisis'),
    ('indicadores', 'KPI — ¿Cómo vamos?'),
    ('aprendizaje', 'POR REVISAR'),
    ('competencia', 'Todavía no hay competidores'),
    ('ajustes', 'Servidor conectado'),
  ]) {
    _paso(id);
    st.go(id);
    await _esperar(tester, 10);
    expect(find.textContaining(titulo, findRichText: true), findsWidgets, reason: id);
    if (id == 'dashboard') {
      for (final (pestana, texto) in const [
        ('Señales', 'Semáforo por agente'),
        ('Plan de acción', 'Plan'),
        ('Comparar', 'Comparar'),
        ('Resumen', 'PREPARACIÓN GLOBAL'),
      ]) {
        _paso('dashboard · $pestana');
        await tester.ensureVisible(find.text(pestana).last);
        await _esperar(tester, 1);
        await tester.tap(find.text(pestana).last);
        await _esperar(tester, 6);
        expect(find.textContaining(texto, findRichText: true), findsWidgets, reason: 'dashboard · $pestana');
        _sinErrores('dashboard · $pestana');
      }
    }
    if (id == 'ajustes') {
      // Perfil de la cuenta: nombre, cargo y acciones de la cuenta (sin modo demo).
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(find.text('Cambiar contraseña'), findsOneWidget);
      expect(find.textContaining('demo', findRichText: true), findsNothing);
      await tester.tap(find.text('Agregar mi nombre'));
      await _esperar(tester, 4);
      expect(find.text('Tu nombre'), findsOneWidget);
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      await _esperar(tester, 2);
      _sinErrores('errores en el perfil con el teclado');
      tester.view.resetViewInsets();
      await tester.tap(find.text('Cancelar'));
      await _esperar(tester, 4);
    }
    if (id == 'preparar') {
      await tester.tap(find.text('Preguntas'));
      await _esperar(tester, 2);
      await tester.ensureVisible(find.textContaining('Sugerir respuestas (').first);
      await tester.tap(find.textContaining('Sugerir respuestas (').first);
      await _esperar(tester, 8);
      await tester.ensureVisible(find.text('Respuestas'));
      await _esperar(tester, 1);
      await tester.tap(find.text('Respuestas'));
      await _esperar(tester, 2);
      expect(find.textContaining('respuestas disponibles'), findsWidgets);
    }
    _sinErrores('errores en $id');
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await _esperar(tester, 4);
  }
}
