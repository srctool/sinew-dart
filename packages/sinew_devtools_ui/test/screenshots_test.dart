import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_devtools/sinew_devtools.dart';
import 'package:sinew_devtools_ui/sinew_devtools_ui.dart';
import 'package:sinew_devtools_ui/src/dashboard.dart';
import 'package:sinew_devtools_ui/src/pages.dart';
import 'package:sinew_devtools_ui/src/sinew_dev_tools.dart' show sinewSection;
import 'package:sinew_testing/sinew_testing.dart';

// The pub.dev screenshots of the package. Not a test of anything: it renders the dashboard and the Network Monitor with
// a real font (Roboto, from the Flutter SDK), with the same fixed data as the golden tests, and writes the PNGs into the
// package's `screenshots/` folder. It does nothing unless asked:
//   SINEW_SCREENSHOTS=1 flutter test test/screenshots_test.dart
final _enabled = Platform.environment.containsKey('SINEW_SCREENSHOTS');

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  final fonts = '$root/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final name in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(
      Future.value(
        ByteData.sublistView(File('$fonts/Roboto-$name.ttf').readAsBytesSync()),
      ),
    );
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('$fonts/MaterialIcons-Regular.otf').readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

void main() {
  final at = DateTime.utc(2026, 11, 8, 10);
  final secure = FakeSecureStore(name: 'session');

  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });
  tearDown(() => debugDevToolsDark = null);

  setUp(() async {
    DevTools.close();
    DevTools.network.clear();
    DevTools.exceptions.clear();
    DevTools.faults.clear();
    DevTools.network.record(
      NetworkExchange(
        method: 'POST',
        url: 'https://api.shop.test/v1/auth/otp',
        startedAt: at,
        requestBody: '{"phone":"0812","otp":"123456"}'.codeUnits,
        requestHeaders: const {
          'Content-Type': ['application/json'],
        },
        status: 200,
        responseHeaders: const {
          'Content-Type': ['application/json'],
        },
        responseBody: '{"refreshToken":"r-1","name":"Ana"}'.codeUnits,
        duration: const Duration(milliseconds: 310),
      ),
    );
    DevTools.network.record(
      NetworkExchange(
        method: 'GET',
        url: 'https://api.shop.test/v1/orders?page=2',
        startedAt: at,
        requestHeaders: const {
          'Authorization': ['Bearer token-1'],
        },
        status: 200,
        responseHeaders: const {
          'Content-Type': ['application/json'],
        },
        responseBody:
            '{"items":[{"id":7,"status":"shipped"}],"page":2}'.codeUnits,
        duration: const Duration(milliseconds: 245),
      ),
    );
    DevTools.network.record(
      NetworkExchange(
        method: 'GET',
        url: 'https://api.shop.test/v1/orders/7',
        startedAt: at,
        status: 503,
        duration: const Duration(milliseconds: 1200),
      ),
    );
    DevTools.exceptions.record(StateError('Order 7 has no address'), null);
    await secure.clearUserData();
    await secure.write('refresh_token', 'eyJhbGciOiJIUzI1NiJ9.signature-9f2c');
  });

  Future<void> shoot(WidgetTester tester, String name, Widget scene) async {
    tester.view
      ..physicalSize = const Size(800, 1600)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: scene));
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      return (await image.toByteData(format: ui.ImageByteFormat.png))!;
    });
    File('screenshots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  Widget dashboard() => Directionality(
    textDirection: TextDirection.ltr,
    child: Dashboard(
      sections: [
        sinewSection(stores: [secure], changelog: '1.4.0', hasHosts: true),
        DevToolSection('Product', [
          DevToolPage(
            name: 'Remote copy',
            description: 'Strings from the backend',
            builder: (_) => const Text('copy'),
          ),
        ]),
      ],
      onClose: () {},
    ),
  );

  Widget page(String title, WidgetBuilder builder) => Directionality(
    textDirection: TextDirection.ltr,
    child: Dashboard(
      sections: const [],
      onClose: () {},
      initial: DevToolPage(name: title, builder: builder),
    ),
  );

  testWidgets('home, light', skip: !_enabled, (tester) async {
    debugDevToolsDark = false;
    await shoot(tester, 'home-light', dashboard());
  });

  testWidgets('home, dark', skip: !_enabled, (tester) async {
    debugDevToolsDark = true;
    await shoot(tester, 'home-dark', dashboard());
  });

  testWidgets('network monitor', skip: !_enabled, (tester) async {
    debugDevToolsDark = false;
    await shoot(
      tester,
      'network-monitor',
      page('Network Monitor', (_) => const NetworkMonitorPage()),
    );
  });
}
