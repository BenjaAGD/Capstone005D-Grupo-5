import 'dart:io';
import 'dart:ui' as ui;

import 'package:directa_gg_app/core/store.dart';
import 'package:directa_gg_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final entry in {'desktop': const Size(1440, 900), 'mobile': const Size(390, 844)}.entries) {
    testWidgets('Login ${entry.key}: layout real sin desbordamientos', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = entry.value;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final key = GlobalKey();
      final auth = testAuth(repository: FakeAuthRepository(), localAccount: true);
      await tester.pumpWidget(RepaintBoundary(key: key, child: DirectaApp(store: await Store.open(), auth: auth)));
      await tester.pumpAndSettle();
      expect(find.text('Bienvenido a DIRECTA'), findsOneWidget);
      expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['DIRECTA_PREVIEW_OUTPUT'];
      if (directory != null) {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
          await Directory(directory).create(recursive: true);
          await File('$directory/login-${entry.key}.png').writeAsBytes(bytes);
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
