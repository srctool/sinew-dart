import 'dart:async';

import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:test/test.dart';

import '../example/main.dart';

/// The usage docs' app service: catches up in init, then listens, and a failing step reports an SV code.
final class _Codes implements CrashReporter {
  final codes = <String>[];

  @override
  void recordNonFatal(SinewException error, StackTrace? stackTrace) =>
      codes.add(error.code);
}

final class _Store implements PurchaseStore {
  _Store(this.pending);

  final List<Purchase> pending;
  final controller = StreamController<Purchase>();

  @override
  Future<List<Purchase>> unacknowledged() async => pending;

  @override
  Stream<Purchase> get arrivals => controller.stream;
}

void main() {
  late _Codes reporter;
  setUp(() {
    reporter = _Codes();
    CrashReporter.install(reporter);
  });
  tearDown(() => CrashReporter.install(CrashReporter.none));

  test(
    'init acknowledges what arrived while the app was not running',
    () async {
      final seen = <String>[];
      final service = BillingService(
        _Store([const Purchase('a'), const Purchase('b')]),
        (p) async => seen.add(p.id),
      );
      await service.init();
      expect(seen, ['a', 'b']);
    },
  );

  test(
    'listen acknowledges each new purchase, and destroy stops listening',
    () async {
      final seen = <String>[];
      final store = _Store([]);
      final service = BillingService(store, (p) async => seen.add(p.id));
      service.listen();
      store.controller.add(const Purchase('c'));
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['c']);
      await service.destroy();
      expect(store.controller.hasListener, isFalse);
    },
  );

  test('a bug in init is reported with the service layer', () async {
    final service = BillingService(
      _Store([const Purchase('a')]),
      (_) async => throw StateError('store down'),
    );
    await service.init();
    expect(reporter.codes, ['BIL-SV-INIT-GEN']);
  });

  test('the lifecycle starts the app services and stops the session', () async {
    final seen = <String>[];
    final lifecycle = AppLifecycle(
      appServices(_Store([const Purchase('a')]), (p) async => seen.add(p.id)),
    );
    await lifecycle.launched();
    expect(seen, ['a']);
    await lifecycle.signedIn();
    await lifecycle.signedOut();
  });
}
