import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_network/src/network_checker.dart';

/// A platform a test drives: [check] answers `checkConnectivity`, and [emit]
/// reports a change.
final class FakePlatform extends ConnectivityPlatform {
  final _events = StreamController<List<ConnectivityResult>>.broadcast();

  Future<List<ConnectivityResult>> Function() check = () async => const [
    ConnectivityResult.wifi,
  ];

  bool get listened => _events.hasListener;

  void emit(List<ConnectivityResult> results) => _events.add(results);

  void fail() => _events.addError(StateError('platform'));

  @override
  Future<List<ConnectivityResult>> checkConnectivity() => check();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _events.stream;
}

/// A platform without an implementation, as in a plain Dart test.
final class MissingPlatform extends ConnectivityPlatform {}

const none = [ConnectivityResult.none];
const wifi = [ConnectivityResult.wifi];

void main() {
  late FakePlatform platform;
  final original = ConnectivityPlatform.instance;

  setUp(() => ConnectivityPlatform.instance = platform = FakePlatform());
  tearDown(() => ConnectivityPlatform.instance = original);

  /// Lets the platform's futures and events land.
  Future<void> settle() => pumpEventQueue();

  group('status', () {
    test('starts online until the platform first reports', () async {
      final answer = Completer<List<ConnectivityResult>>();
      platform.check = () => answer.future;
      final checker = NetworkChecker() as ConnectivityNetworkChecker;
      await settle();
      expect(checker.status, NetworkStatus.online);
      expect(checker.isOnline, isTrue);
      expect(checker.reported, isFalse);
      answer.complete(none);
      await settle();
      expect(checker.status, NetworkStatus.offline);
      expect(checker.reported, isTrue);
      await checker.dispose();
    });

    test('the starting check reports offline as a change', () async {
      platform.check = () async => none;
      final checker = NetworkChecker();
      final changes = <NetworkStatus>[];
      checker.changes.listen(changes.add);
      await settle();
      expect(checker.isOnline, isFalse);
      expect(changes, [NetworkStatus.offline]);
      await checker.dispose();
    });

    test('follows the platform changes', () async {
      final checker = NetworkChecker();
      final changes = <NetworkStatus>[];
      checker.changes.listen(changes.add);
      await settle();
      platform.emit(none);
      await settle();
      expect(checker.isOnline, isFalse);
      platform.emit(const [ConnectivityResult.mobile]);
      await settle();
      expect(checker.isOnline, isTrue);
      expect(changes, [NetworkStatus.offline, NetworkStatus.online]);
      await checker.dispose();
    });

    test('a change of interface that stays online is not a change', () async {
      final checker = NetworkChecker() as ConnectivityNetworkChecker;
      final changes = <NetworkStatus>[];
      checker.changes.listen(changes.add);
      platform
        ..emit(wifi)
        ..emit(const [ConnectivityResult.mobile])
        ..emit(const [ConnectivityResult.ethernet, ConnectivityResult.vpn]);
      await settle();
      expect(changes, isEmpty);
      expect(checker.reported, isTrue);
      await checker.dispose();
    });

    test('a check answering after the stream reported is ignored', () async {
      final answer = Completer<List<ConnectivityResult>>();
      platform.check = () => answer.future;
      final checker = NetworkChecker();
      await settle();
      platform.emit(none);
      await settle();
      answer.complete(wifi);
      await settle();
      expect(checker.status, NetworkStatus.offline);
      await checker.dispose();
    });
  });

  group('platform failures', () {
    test('a failed check stays online', () async {
      platform.check = () async => throw StateError('platform');
      final checker = NetworkChecker() as ConnectivityNetworkChecker;
      await settle();
      expect(checker.isOnline, isTrue);
      expect(checker.reported, isFalse);
      await checker.dispose();
    });

    test('a stream error keeps the last status and keeps listening', () async {
      final checker = NetworkChecker();
      platform.emit(none);
      await settle();
      platform.fail();
      await settle();
      expect(checker.isOnline, isFalse);
      platform.emit(wifi);
      await settle();
      expect(checker.isOnline, isTrue);
      await checker.dispose();
    });

    test('no platform implementation: created, and stays online', () async {
      ConnectivityPlatform.instance = MissingPlatform();
      final checker = NetworkChecker();
      await settle();
      expect(checker.isOnline, isTrue);
      await checker.dispose();
    });
  });

  group('dispose', () {
    test('stops listening and closes changes', () async {
      final checker = NetworkChecker();
      await settle();
      expect(platform.listened, isTrue);
      final done = expectLater(checker.changes, emitsDone);
      await checker.dispose();
      await done;
      expect(platform.listened, isFalse);
    });

    test(
      'keeps the last status, and ignores a check answering later',
      () async {
        final answer = Completer<List<ConnectivityResult>>();
        platform.check = () => answer.future;
        final checker = NetworkChecker();
        platform.emit(none);
        await settle();
        await checker.dispose();
        answer.complete(wifi);
        await settle();
        expect(checker.status, NetworkStatus.offline);
      },
    );

    test('a starting check answering after dispose changes nothing', () async {
      final answer = Completer<List<ConnectivityResult>>();
      platform.check = () => answer.future;
      final checker = NetworkChecker() as ConnectivityNetworkChecker;
      await checker.dispose();
      answer.complete(none);
      await settle();
      expect(checker.status, NetworkStatus.online);
      expect(checker.reported, isFalse);
    });

    test('can be called twice', () async {
      final checker = NetworkChecker();
      await checker.dispose();
      await checker.dispose();
    });
  });

  group('statusOf', () {
    test('online for any interface but none', () {
      for (final result in ConnectivityResult.values) {
        expect(
          statusOf([result]),
          result == ConnectivityResult.none
              ? NetworkStatus.offline
              : NetworkStatus.online,
          reason: '$result',
        );
      }
    });

    test('online when one of several interfaces is connected', () {
      expect(
        statusOf(const [ConnectivityResult.none, ConnectivityResult.vpn]),
        NetworkStatus.online,
      );
    });

    test('offline for an empty list', () {
      expect(statusOf(const []), NetworkStatus.offline);
    });
  });
}
