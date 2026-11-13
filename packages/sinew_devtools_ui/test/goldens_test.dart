import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_devtools/sinew_devtools.dart';
import 'package:sinew_devtools_ui/sinew_devtools_ui.dart';
import 'package:sinew_devtools_ui/src/dashboard.dart';
import 'package:sinew_devtools_ui/src/pages.dart';
import 'package:sinew_devtools_ui/src/sinew_dev_tools.dart' show sinewSection;
import 'package:sinew_testing/sinew_testing.dart';

/// The pages the golden tests capture, the same as Kotlin's screenshots, with
/// fixed values so the images don't change between runs.
void main() {
  final at = DateTime.utc(2026, 11, 8, 10);
  final secure = FakeSecureStore(name: 'session');
  late NetworkRecord get;
  late NetworkRecord otp;

  setUpAll(() => debugDevToolsDark = false);
  tearDownAll(() => debugDevToolsDark = null);

  setUp(() async {
    DevTools.close();
    DevTools.network.clear();
    DevTools.exceptions.clear();
    DevTools.faults.clear();
    otp = DevTools.network.record(
      NetworkExchange(
        method: 'POST',
        url: 'https://api.shop.test/v1/auth/otp',
        startedAt: at,
        requestHeaders: const {
          'Content-Type': ['application/json'],
        },
        requestBody: '{"phone":"0812","otp":"123456"}'.codeUnits,
        status: 200,
        responseHeaders: const {
          'Content-Type': ['application/json'],
        },
        responseBody: '{"refreshToken":"r-1","name":"Ana"}'.codeUnits,
        duration: const Duration(milliseconds: 310),
      ),
    );
    get = DevTools.network.record(
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
    DevTools.exceptions.record(StateError('Order 7 has no address'), null);
    await secure.clearUserData();
    await secure.write(
      'refresh_token',
      'eyJhbGciOiJIUzI1NiJ9.payload.signature-9f2c',
    );
    await secure.write('pin', '1234');
  });

  Future<void> capture(WidgetTester tester, String name, Widget scene) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(scene);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('$name.png'),
    );
  }

  Widget page(String title, WidgetBuilder builder) => Directionality(
    textDirection: TextDirection.ltr,
    child: Dashboard(
      sections: const [],
      onClose: () {},
      initial: DevToolPage(name: title, builder: builder),
    ),
  );

  const app = MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Color(0xFFF4F1EA),
      body: Center(child: Text('The app')),
    ),
  );

  testWidgets('home', (tester) async {
    final sections = [
      sinewSection(stores: [secure], changelog: '1.4.0', hasHosts: true),
      DevToolSection('Product', [
        DevToolPage(
          name: 'Remote copy',
          description: 'Strings from the backend',
          builder: (_) => const Text('copy'),
        ),
      ]),
    ];
    await capture(
      tester,
      'home',
      Directionality(
        textDirection: TextDirection.ltr,
        child: Dashboard(sections: sections, onClose: () {}),
      ),
    );
  });

  testWidgets('network-list', (tester) async {
    await capture(
      tester,
      'network-list',
      page('Network Monitor', (_) => const NetworkMonitorPage()),
    );
  });

  testWidgets('network-detail', (tester) async {
    await capture(
      tester,
      'network-detail',
      page('GET /v1/orders', (_) => NetworkDetailPage(get)),
    );
  });

  testWidgets('network-blocked', (tester) async {
    await capture(
      tester,
      'network-blocked',
      page('POST /v1/auth/otp', (_) => NetworkDetailPage(otp)),
    );
  });

  testWidgets('exceptions', (tester) async {
    await capture(
      tester,
      'exceptions',
      page('Exception Log', (_) => const ExceptionLogPage()),
    );
  });

  testWidgets('secure-store', (tester) async {
    await capture(
      tester,
      'secure-store',
      page('Secure Store', (_) => SecureStorePage(secure)),
    );
  });

  testWidgets('faults', (tester) async {
    DevTools.faults.add(FaultRule(pathPattern: '/orders', status: 503));
    await capture(
      tester,
      'faults',
      page('Fault Injection', (_) => const FaultInjectionPage()),
    );
  });

  testWidgets('overlay', (tester) async {
    DevTools.faults.add(FaultRule(pathPattern: '/orders', status: 503));
    await capture(
      tester,
      'overlay',
      const SinewDevTools(
        ribbon: BuildRibbon('1.4.0 (212) · staging'),
        showUncaughtErrors: true,
        child: app,
      ),
    );
  });

  testWidgets('uncaught', (tester) async {
    DevTools.exceptions.record(
      StateError('Checkout crashed'),
      null,
      source: ExceptionSource.uncaught,
    );
    await capture(
      tester,
      'uncaught',
      const SinewDevTools(
        ribbon: BuildRibbon('1.4.0 (212) · staging'),
        showUncaughtErrors: true,
        child: app,
      ),
    );
  });
}
