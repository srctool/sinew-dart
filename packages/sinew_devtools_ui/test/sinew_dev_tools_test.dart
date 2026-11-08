import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_devtools/sinew_devtools.dart';
import 'package:sinew_devtools_ui/sinew_devtools_ui.dart';
import 'package:sinew_testing/sinew_testing.dart';

void main() {
  final copied = <String>[];
  final at = DateTime.utc(2026, 11, 8, 10);

  setUp(() {
    copied.clear();
    DevTools.close();
    DevTools.network.clear();
    DevTools.exceptions.clear();
    DevTools.faults.clear();
    DevTools.network.redaction = Redaction.standard;
  });

  Future<void> show(
    WidgetTester tester, {
    DevToolsLauncher launcher = const FloatingLauncher(),
    List<DevToolSection> sections = const [],
    List<InspectableStore> stores = const [],
    List<String> hosts = const [],
    String? changelog,
    BuildRibbon? ribbon,
    bool showUncaughtErrors = false,
    KeyValueStore? preferences,
    Redaction? redaction,
    Widget app = const MaterialApp(home: Scaffold(body: Text('The app'))),
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    await tester.pumpWidget(
      SinewDevTools(
        launcher: launcher,
        sections: sections,
        stores: stores,
        hosts: hosts,
        changelog: changelog,
        ribbon: ribbon,
        showUncaughtErrors: showUncaughtErrors,
        preferences: preferences,
        redaction: redaction,
        child: app,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPage(WidgetTester tester, String name) async {
    if (!DevTools.isOpen.value) DevTools.open();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('entry:$name')));
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  group('the dashboard', () {
    testWidgets('an app section appears after the Sinew section', (
      tester,
    ) async {
      await show(
        tester,
        sections: [
          DevToolSection('Product', [
            DevToolPage(
              name: 'Remote copy',
              builder: (_) => const Text('copy'),
            ),
          ]),
        ],
      );
      DevTools.open();
      await tester.pumpAndSettle();
      final sinew = tester.getTopLeft(key('section:Sinew')).dy;
      final product = tester.getTopLeft(key('section:Product')).dy;
      expect(sinew, lessThan(product));
      await tester.tap(key('entry:Remote copy'));
      await tester.pumpAndSettle();
      expect(find.text('copy'), findsOneWidget);
    });

    testWidgets('the floating button opens it and hides while it is open', (
      tester,
    ) async {
      await show(tester);
      expect(find.text('The app'), findsOneWidget);
      await tester.tap(key('sinew-devtools-button'));
      await tester.pumpAndSettle();
      expect(DevTools.isOpen.value, isTrue);
      expect(key('sinew-devtools-button'), findsNothing);
      await tester.tap(key('sinew-devtools-back')); // "Close"
      await tester.pumpAndSettle();
      expect(DevTools.isOpen.value, isFalse);
      expect(key('sinew-devtools-button'), findsOneWidget);
    });

    testWidgets('a drag never opens it, and the position is remembered', (
      tester,
    ) async {
      final preferences = FakeKeyValueStore();
      await show(tester, preferences: preferences);
      final before = tester.getCenter(key('sinew-devtools-button'));
      await tester.drag(key('sinew-devtools-button'), const Offset(-120, -200));
      await tester.pumpAndSettle();
      expect(DevTools.isOpen.value, isFalse);
      final after = tester.getCenter(key('sinew-devtools-button'));
      expect(after.dx, lessThan(before.dx));
      expect(after.dy, lessThan(before.dy));
      expect(
        await preferences.getDouble('sinew.devtools.button.x'),
        lessThan(0),
      );
      expect(
        await preferences.getDouble('sinew.devtools.button.y'),
        lessThan(0),
      );
    });

    testWidgets(
      'the menu launcher has no button; its row opens the dashboard',
      (tester) async {
        await show(
          tester,
          launcher: const MenuLauncher(),
          app: const MaterialApp(home: Scaffold(body: DevToolsMenuItem())),
        );
        expect(key('sinew-devtools-button'), findsNothing);
        await tester.tap(key('sinew-devtools-menu-item'));
        await tester.pumpAndSettle();
        expect(key('section:Sinew'), findsOneWidget);
      },
    );

    testWidgets('the custom launcher opens only when the app asks', (
      tester,
    ) async {
      await show(tester, launcher: const CustomLauncher());
      expect(key('sinew-devtools-button'), findsNothing);
      expect(key('sinew-devtools-dashboard'), findsNothing);
      DevTools.open();
      await tester.pumpAndSettle();
      expect(key('section:Sinew'), findsOneWidget);
      DevTools.close();
      await tester.pumpAndSettle();
      expect(key('sinew-devtools-dashboard'), findsNothing);
    });

    testWidgets('back walks the dashboard\'s own navigator', (tester) async {
      await show(tester);
      await openPage(tester, 'Network Monitor');
      expect(find.text('No requests yet'), findsOneWidget);
      await tester.tap(key('sinew-devtools-back'));
      await tester.pumpAndSettle();
      expect(key('sinew-devtools-home'), findsOneWidget);
      expect(DevTools.isOpen.value, isTrue);
    });

    testWidgets('the optional pages appear only when given', (tester) async {
      await show(tester);
      DevTools.open();
      await tester.pumpAndSettle();
      expect(key('entry:API Host'), findsNothing);
      expect(key('entry:Changelog'), findsNothing);
    });

    testWidgets('the marker is in the tree', (tester) async {
      await show(tester);
      expect(key(devToolsMarker), findsOneWidget);
    });
  });

  group('app entries', () {
    testWidgets('an action with a confirmation asks first', (tester) async {
      var ran = 0;
      await show(
        tester,
        sections: [
          DevToolSection('Product', [
            DevToolAction(
              name: 'Reset onboarding',
              confirm: 'Show it again?',
              run: () async => ran++,
            ),
          ]),
        ],
      );
      await openPage(tester, 'Reset onboarding');
      expect(find.text('Show it again?'), findsOneWidget);
      await tester.tap(key('sinew-devtools-dismiss'));
      await tester.pumpAndSettle();
      expect(ran, 0);
      await tester.tap(key('entry:Reset onboarding'));
      await tester.pumpAndSettle();
      await tester.tap(key('sinew-devtools-confirm'));
      await tester.pumpAndSettle();
      expect(ran, 1);
    });

    testWidgets('a toggle flips and redraws', (tester) async {
      var on = false;
      await show(
        tester,
        sections: [
          DevToolSection('Product', [
            DevToolToggle(
              name: 'New checkout',
              value: () => on,
              onChanged: (v) => on = v,
            ),
          ]),
        ],
      );
      DevTools.open();
      await tester.pumpAndSettle();
      await tester.tap(key('entry:New checkout'));
      await tester.pumpAndSettle();
      expect(on, isTrue);
      expect(
        tester.widget<SwitchListTile>(key('entry:New checkout')).value,
        isTrue,
      );
    });

    testWidgets('a group opens its children', (tester) async {
      await show(
        tester,
        sections: [
          DevToolSection('Product', [
            DevToolGroup(
              name: 'Playgrounds',
              children: [
                DevToolPage(
                  name: 'Forms',
                  builder: (_) => const Text('form playground'),
                ),
              ],
            ),
          ]),
        ],
      );
      await openPage(tester, 'Playgrounds');
      await tester.tap(key('entry:Forms'));
      await tester.pumpAndSettle();
      expect(find.text('form playground'), findsOneWidget);
    });
  });

  group('the Network Monitor', () {
    NetworkRecord recordGet() => DevTools.network.record(
      NetworkExchange(
        method: 'GET',
        url: 'https://api.test/v1/orders?token=abc',
        startedAt: at,
        requestHeaders: const {
          'Authorization': ['Bearer secret-token'],
        },
        status: 200,
      ),
    );

    testWidgets('lists records and copies them redacted', (tester) async {
      await show(tester);
      final record = recordGet();
      await openPage(tester, 'Network Monitor');
      await tester.tap(key('network-record:${record.id}'));
      await tester.pumpAndSettle();
      await tester.tap(key('network-copy'));
      await tester.tap(key('network-curl'));
      await tester.pumpAndSettle();
      expect(copied, [record.asText(), record.asCurl()]);
      expect(
        copied.any((c) => c.contains('secret-token') || c.contains('abc')),
        isFalse,
      );
      expect(find.textContaining('secret-token'), findsNothing);
    });

    testWidgets('clear empties it', (tester) async {
      await show(tester);
      recordGet();
      await openPage(tester, 'Network Monitor');
      await tester.tap(key('network-clear'));
      await tester.pumpAndSettle();
      expect(find.text('No requests yet'), findsOneWidget);
    });

    testWidgets('a GET replays on tap', (tester) async {
      final http = mockHttp(
        (r) => r.on('GET', '/v1/orders').respond(200, body: '{}'),
        hooks: DevTools.httpHooks,
      );
      await show(tester);
      await tester.runAsync(() => http.dio.get<dynamic>('orders'));
      final record = DevTools.network.records.value.single;
      await openPage(tester, 'Network Monitor');
      await tester.tap(key('network-record:${record.id}'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(key('network-replay'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(DevTools.network.records.value.first.isReplay, isTrue);
    });

    testWidgets('any other method asks before it replays', (tester) async {
      final http = mockHttp(
        (r) => r.on('POST', '/v1/orders').respond(201),
        hooks: DevTools.httpHooks,
      );
      await show(tester);
      await tester.runAsync(
        () => http.dio.post<dynamic>('orders', data: {'item': 7}),
      );
      final record = DevTools.network.records.value.single;
      await openPage(tester, 'Network Monitor');
      await tester.tap(key('network-record:${record.id}'));
      await tester.pumpAndSettle();
      await tester.tap(key('network-replay'));
      await tester.pumpAndSettle();
      expect(find.textContaining('It may repeat what it did'), findsOneWidget);
      await tester.tap(key('sinew-devtools-dismiss'));
      await tester.pumpAndSettle();
      expect(DevTools.network.records.value, hasLength(1));
      await tester.tap(key('network-replay'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(key('sinew-devtools-confirm'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(DevTools.network.records.value, hasLength(2));
      expect(DevTools.network.records.value.first.isReplay, isTrue);
    });

    testWidgets('a record that lost a secret cannot be replayed and says why', (
      tester,
    ) async {
      final http = mockHttp(
        (r) => r.on('POST', '/v1/auth/otp').respond(200),
        hooks: DevTools.httpHooks,
      );
      await show(tester);
      await tester.runAsync(
        () => http.dio.post<dynamic>('auth/otp', data: {'otp': '123456'}),
      );
      final record = DevTools.network.records.value.single;
      await openPage(tester, 'Network Monitor');
      await tester.tap(key('network-record:${record.id}'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<OutlinedButton>(key('network-replay')).onPressed,
        isNull,
      );
      expect(find.textContaining('a secret in it was hidden'), findsOneWidget);
    });

    testWidgets('the app\'s redaction reaches the recorders', (tester) async {
      await show(
        tester,
        redaction: Redaction.standard.extend(fieldParts: ['cardNumber']),
      );
      final record = DevTools.network.record(
        NetworkExchange(
          method: 'GET',
          url: 'https://api.test/pay?card_number=4111',
          startedAt: at,
        ),
      );
      expect(record.url, isNot(contains('4111')));
    });
  });

  group('the Exception Log', () {
    testWidgets('lists rows and copies them', (tester) async {
      await show(tester);
      DevTools.exceptions.record(StateError('boom'), null);
      final row = DevTools.exceptions.records.value.single;
      await openPage(tester, 'Exception Log');
      await tester.tap(key('exception-row:${row.id}'));
      await tester.pumpAndSettle();
      await tester.tap(key('exception-copy'));
      await tester.pumpAndSettle();
      expect(copied, [row.asText()]);
    });

    testWidgets('an uncaught error pops up a card only when asked to', (
      tester,
    ) async {
      await show(tester, showUncaughtErrors: true);
      DevTools.exceptions.record(
        StateError('crash'),
        null,
        source: ExceptionSource.uncaught,
      );
      await tester.pumpAndSettle();
      expect(key('sinew-devtools-uncaught'), findsOneWidget);
      expect(find.textContaining('crash'), findsOneWidget);
      await tester.tap(key('uncaught-dismiss'));
      await tester.pumpAndSettle();
      expect(key('sinew-devtools-uncaught'), findsNothing);
    });

    testWidgets('without the option no card pops up', (tester) async {
      await show(tester);
      DevTools.exceptions.record(
        StateError('crash'),
        null,
        source: ExceptionSource.uncaught,
      );
      await tester.pumpAndSettle();
      expect(key('sinew-devtools-uncaught'), findsNothing);
    });
  });

  group('stores', () {
    testWidgets('the Secure Store page shows only masked values', (
      tester,
    ) async {
      const token = 'eyJhbGciOiJIUzI1NiJ9.payload.sig-9f2c';
      final store = FakeSecureStore(name: 'session');
      await store.write('refresh_token', token);
      await store.write('pin', '1234');
      await show(tester, stores: [store]);
      await openPage(tester, 'Secure Store');
      expect(find.text(Redaction.maskSecret(token)), findsOneWidget);
      expect(find.text('•••• (4 chars)'), findsOneWidget);
      expect(find.textContaining('payload'), findsNothing);
      expect(find.textContaining('1234'), findsNothing);
      expect(key('network-copy'), findsNothing);
      expect(copied, isEmpty);
    });

    testWidgets('clearing the Secure Store asks first', (tester) async {
      final store = FakeSecureStore(name: 'session');
      await store.write('refresh_token', 'r');
      await show(tester, stores: [store]);
      await openPage(tester, 'Secure Store');
      await tester.tap(key('secure-clear'));
      await tester.pumpAndSettle();
      await tester.tap(key('sinew-devtools-dismiss'));
      await tester.pumpAndSettle();
      expect(store.snapshot, {'refresh_token': 'r'});
      await tester.tap(key('secure-clear'));
      await tester.pumpAndSettle();
      await tester.tap(key('sinew-devtools-confirm'));
      await tester.pumpAndSettle();
      expect(store.snapshot, isEmpty);
      expect(find.text('session is empty'), findsOneWidget);
    });

    testWidgets('the Key-Value Store edits by type and deletes after asking', (
      tester,
    ) async {
      final store = FakeKeyValueStore(name: 'prefs');
      await store.setInt('launches', 3);
      await store.setString('theme', 'dark');
      await show(tester, stores: [store]);
      await openPage(tester, 'Key-Value Store');
      await tester.tap(key('kv-row:launches'));
      await tester.pumpAndSettle();
      await tester.enterText(key('kv-edit-field'), 'many');
      await tester.tap(key('sinew-devtools-confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Not a whole number'), findsOneWidget);
      await tester.enterText(key('kv-edit-field'), '4');
      await tester.tap(key('sinew-devtools-confirm'));
      await tester.pumpAndSettle();
      expect(store.snapshot['launches'], 4);
      expect(key('kv-edit-field'), findsNothing);

      await tester.tap(key('kv-delete:theme'));
      await tester.pumpAndSettle();
      await tester.tap(key('sinew-devtools-dismiss'));
      await tester.pumpAndSettle();
      expect(store.snapshot['theme'], 'dark');
      await tester.tap(key('kv-delete:theme'));
      await tester.pumpAndSettle();
      await tester.tap(key('sinew-devtools-confirm'));
      await tester.pumpAndSettle();
      expect(store.snapshot.containsKey('theme'), isFalse);
    });
  });

  group('faults and hosts', () {
    testWidgets('a rule is added from the page and the ribbon says so', (
      tester,
    ) async {
      await show(tester, ribbon: const BuildRibbon('1.4.0 · staging'));
      expect(find.text('1.4.0 · staging'), findsOneWidget);
      await openPage(tester, 'Fault Injection');
      await tester.enterText(key('fault-path'), '/orders');
      await tester.tap(key('fault-add'));
      await tester.pumpAndSettle();
      expect(DevTools.faults.active.value.single.status, 503);
      expect(find.text('1.4.0 · staging · faults on'), findsOneWidget);
      await tester.tap(key('fault-remove:/orders'));
      await tester.pumpAndSettle();
      expect(DevTools.faults.active.value, isEmpty);
    });

    testWidgets('an invalid rule says why', (tester) async {
      await show(tester);
      await openPage(tester, 'Fault Injection');
      await tester.ensureVisible(key('fault-add'));
      await tester.tap(key('fault-add'));
      await tester.pumpAndSettle();
      expect(key('fault-error'), findsOneWidget);
      expect(DevTools.faults.active.value, isEmpty);
    });

    testWidgets('a host is chosen from the page', (tester) async {
      const staging = 'https://staging.local/v1';
      await show(tester, hosts: [staging]);
      await openPage(tester, 'API Host');
      await tester.tap(key('host:$staging'));
      await tester.pumpAndSettle();
      expect(DevTools.hosts.current.value, staging);
      expect(find.text('staging.local'), findsOneWidget); // in the ribbon
      await tester.tap(key('host:own'));
      await tester.pumpAndSettle();
      expect(DevTools.hosts.current.value, isNull);
    });

    testWidgets('a changelog has its page', (tester) async {
      await show(tester, changelog: '1.4.0: faster lists');
      await openPage(tester, 'Changelog');
      expect(find.text('1.4.0: faster lists'), findsOneWidget);
    });

    testWidgets('expiring the token asks first', (tester) async {
      await show(tester);
      await openPage(tester, 'Expire Access Token');
      expect(find.textContaining('the real refresh runs'), findsOneWidget);
      await tester.tap(key('sinew-devtools-dismiss'));
      await tester.pumpAndSettle();
    });
  });
}
