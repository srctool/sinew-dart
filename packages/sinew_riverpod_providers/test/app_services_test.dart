import 'package:riverpod/riverpod.dart';
import 'package:sinew_presentation/sinew_presentation.dart';
import 'package:sinew_riverpod_providers/sinew_riverpod_providers.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Service extends AppService {
  _Service(super.lifetime, this.name, this.log);

  final String name;
  final List<String> log;

  @override
  Future<void> init() async => log.add('$name.init');

  @override
  void listen() => log.add('$name.listen');

  @override
  Future<void> destroy() async => log.add('$name.destroy');
}

void main() {
  late List<String> log;
  setUp(() => log = []);

  ProviderContainer containerWith(List<AppService> services) =>
      ProviderContainer(
        overrides: [appServicesProvider.overrideWithValue(services)],
      );

  test('reading the host starts the app services only', () async {
    final container = containerWith([
      _Service(ServiceLifetime.app, 'a', log),
      _Service(ServiceLifetime.session, 's', log),
    ]);
    addTearDown(container.dispose);
    container.read(appServiceHostProvider);
    await Future<void>.delayed(Duration.zero);
    expect(log, ['a.init', 'a.listen']);
  });

  test(
    'the host is one instance: a second read starts nothing again',
    () async {
      final container = containerWith([
        _Service(ServiceLifetime.app, 'a', log),
      ]);
      addTearDown(container.dispose);
      expect(
        container.read(appServiceHostProvider),
        same(container.read(appServiceHostProvider)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(log, ['a.init', 'a.listen']);
    },
  );

  test(
    'the session owner starts and stops the session services through it',
    () async {
      final container = containerWith([
        _Service(ServiceLifetime.session, 's', log),
      ]);
      addTearDown(container.dispose);
      final host = container.read(appServiceHostProvider);
      await host.startSession();
      await host.stopSession();
      expect(log, ['s.init', 's.listen', 's.destroy']);
    },
  );

  test(
    'disposing the container destroys every service in reverse order',
    () async {
      final container = containerWith([
        _Service(ServiceLifetime.app, 'a1', log),
        _Service(ServiceLifetime.app, 'a2', log),
      ]);
      container.read(appServiceHostProvider);
      await Future<void>.delayed(Duration.zero);
      log.clear();
      container.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(log, ['a2.destroy', 'a1.destroy']);
    },
  );

  test('without an override it says what to do', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(appServicesProvider),
      throwsA(predicate((e) => e.toString().contains('override it'))),
    );
  });
}
