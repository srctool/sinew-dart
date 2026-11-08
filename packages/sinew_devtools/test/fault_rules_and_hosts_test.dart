import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_devtools/sinew_devtools.dart';
import 'package:sinew_testing/sinew_testing.dart';

void main() {
  group('fault rules', () {
    test('a pattern matches the end of the path at a slash', () {
      final rule = FaultRule(pathPattern: '/orders', status: 500);
      expect(rule.matches('GET', '/v1/orders'), isTrue);
      expect(rule.matches('GET', '/orders'), isTrue);
      expect(rule.matches('GET', '/v1/myorders'), isFalse);
      expect(rule.matches('GET', '/v1/orders/7'), isFalse);
      expect(
        FaultRule(
          pathPattern: 'orders',
          status: 500,
        ).matches('GET', '/v1/orders'),
        isTrue,
      );
    });

    test('a star matches any run', () {
      final rule = FaultRule(pathPattern: '/orders/*', status: 500);
      expect(rule.matches('GET', '/v1/orders/7'), isTrue);
      expect(rule.matches('GET', '/v1/orders/7/items'), isTrue);
      expect(rule.matches('GET', '/v1/orders'), isFalse);
      expect(
        FaultRule(pathPattern: '*', status: 500).matches('GET', '/any/thing'),
        isTrue,
      );
      final dot = FaultRule(pathPattern: '/a.b', status: 500);
      expect(dot.matches('GET', '/a.b'), isTrue);
      expect(dot.matches('GET', '/axb'), isFalse); // a dot is a dot
    });

    test('a method narrows the rule', () {
      final rule = FaultRule(
        method: 'post',
        pathPattern: '/orders',
        status: 500,
      );
      expect(rule.matches('POST', '/v1/orders'), isTrue);
      expect(rule.matches('GET', '/v1/orders'), isFalse);
    });

    test('the newest matching rule wins', () {
      final rules = FaultRules();
      final old = FaultRule(pathPattern: '*', status: 500);
      final newer = FaultRule(pathPattern: '/orders', status: 503);
      rules
        ..add(old)
        ..add(newer);
      expect(rules.match('GET', '/v1/orders'), newer);
      expect(rules.match('GET', '/v1/me'), old);
      rules.remove(newer);
      expect(rules.match('GET', '/v1/orders'), old);
      rules.clear();
      expect(rules.match('GET', '/v1/orders'), isNull);
    });

    test('the active rules notify and cannot be changed in place', () {
      final rules = FaultRules();
      var calls = 0;
      rules.active.addListener(() => calls++);
      rules
        ..add(FaultRule(pathPattern: '/a', status: 500))
        ..clear();
      expect(calls, 2);
      rules.add(FaultRule(pathPattern: '/a', status: 500));
      expect(() => rules.active.value.clear(), throwsUnsupportedError);
    });

    test('a rule is validated', () {
      expect(() => FaultRule(pathPattern: '/a'), throwsArgumentError);
      expect(
        () => FaultRule(pathPattern: ' ', status: 500),
        throwsArgumentError,
      );
      expect(
        () => FaultRule(pathPattern: '/a', status: 500, drop: true),
        throwsArgumentError,
      );
      expect(
        () => FaultRule(pathPattern: '/a', status: 600),
        throwsArgumentError,
      );
      expect(
        () => FaultRule(pathPattern: '/a', delay: Duration.zero),
        throwsArgumentError,
      );
      FaultRule(pathPattern: '/a', delay: const Duration(seconds: 1));
      FaultRule(pathPattern: '/a', drop: true);
    });

    test('a rule becomes the network\'s decision', () {
      final decision = FaultRule(
        pathPattern: '/a',
        status: 503,
        delay: const Duration(seconds: 2),
        body: '{}',
      ).decision();
      expect(decision.status, 503);
      expect(decision.delay, const Duration(seconds: 2));
      expect(decision.body, '{}');
      expect(decision.drop, isFalse);
      expect(FaultRule(pathPattern: '/a', drop: true).decision().drop, isTrue);
    });
  });

  group('host override', () {
    const staging = 'https://staging.local/v2';
    const local = 'http://10.0.2.2:8080/v1';

    test('the chosen host is remembered across restarts', () async {
      final store = FakeKeyValueStore();
      final first = HostOverride();
      await first.configure([staging, local], store: store);
      expect(first.current.value, isNull);
      await first.select(local);
      expect(first.current.value, local);
      expect(await store.getString(HostOverride.key), local);

      final restarted = HostOverride();
      await restarted.configure([staging, local], store: store);
      expect(restarted.current.value, local);
      await restarted.select(null); // the reset button
      expect(restarted.current.value, isNull);
      expect(await store.getString(HostOverride.key), isNull);
    });

    test('a host the app no longer lists is forgotten', () async {
      final store = FakeKeyValueStore();
      await store.setString(HostOverride.key, 'https://old.local/v1');
      final hosts = HostOverride();
      await hosts.configure([staging], store: store);
      expect(hosts.current.value, isNull);
      expect(await store.getString(HostOverride.key), isNull);
    });

    test('only a listed host can be chosen', () async {
      final hosts = HostOverride();
      await hosts.configure([staging]);
      expect(() => hosts.select('https://evil.local'), throwsArgumentError);
      await hosts.select(staging); // without a store, only kept in memory
      expect(hosts.current.value, staging);
      expect(hosts.hosts.value, [staging]);
    });

    test('a host must be an http base URL', () async {
      expect(
        () => HostOverride().configure(['ftp://x.local']),
        throwsArgumentError,
      );
      expect(
        () => HostOverride().configure(['not a url']),
        throwsArgumentError,
      );
    });
  });
}
