import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sinew_network/sinew_network.dart';
import 'package:sinew_riverpod_providers/sinew_riverpod_providers.dart';
import 'package:sinew_testing/sinew_testing.dart';

final config = SinewConfig(
  baseUrl: 'https://api.example.com/v1/',
  locale: () => 'en',
);

/// A backend that accepts only `token-2`: the first request gets a 401.
final class Backend implements HttpClientAdapter {
  final sent = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final auth = options.headers['Authorization'] as String?;
    sent.add(auth);
    return ResponseBody.fromString(
      auth == 'Bearer token-2' ? 'ok' : '',
      auth == 'Bearer token-2' ? 200 : 401,
    );
  }

  @override
  void close({bool force = false}) {}
}

final class FakePlatform extends ConnectivityPlatform {
  final events = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => const [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => events.stream;
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });

  Matcher namesProvider(String text) =>
      throwsA(predicate((e) => '$e'.contains(text), 'mentions "$text"'));

  group('a missing override fails, naming the provider', () {
    test('sinewConfigProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        () => container.read(sinewConfigProvider),
        namesProvider('sinewConfigProvider has no value: override it'),
      );
    });

    test('refreshCallProvider', () async {
      final container = ProviderContainer(
        overrides: [sinewConfigProvider.overrideWithValue(config)],
      );
      addTearDown(container.dispose);
      await container.read(secureStoreProvider.future);
      expect(
        () => container.read(sinewHttpProvider),
        namesProvider('refreshCallProvider has no value: override it'),
      );
    });

    test('a secure store not awaited at startup', () {
      final container = ProviderContainer(
        overrides: [
          sinewConfigProvider.overrideWithValue(config),
          refreshCallProvider.overrideWithValue(
            (_) async => const RefreshRejected(),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        () => container.read(tokenSourceProvider),
        namesProvider('await ref.read(secureStoreProvider.future)'),
      );
    });
  });

  test(
    'with the overrides, a 401 is refreshed through the app\'s call',
    () async {
      final refreshed = <String>[];
      final container = ProviderContainer(
        overrides: [
          sinewConfigProvider.overrideWithValue(config),
          refreshCallProvider.overrideWithValue((token) async {
            refreshed.add(token);
            return const RefreshTokens(access: 'token-2', refresh: 'refresh-2');
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(secureStoreProvider.future);
      await container
          .read(tokenSourceProvider)
          .start(accessToken: 'token-1', refreshToken: 'refresh-1');

      final backend = Backend();
      final dio = container.read(sinewHttpProvider)
        ..httpClientAdapter = backend;
      final response = await dio.get<String>('orders');

      expect(response.data, 'ok');
      expect(dio.options.baseUrl, 'https://api.example.com/v1/');
      expect(refreshed, ['refresh-1']);
      expect(backend.sent, ['Bearer token-1', 'Bearer token-2']);
      expect(
        await container.read(refreshTokenStoreProvider).read(),
        'refresh-2',
      );
      final secrets = await container.read(secureStoreProvider.future);
      expect(await secrets.read('session.refreshToken'), 'refresh-2');
    },
  );

  test('the key-value store is ready to use', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(keyValueStoreProvider);
    await store.setString('theme', 'dark');
    expect(await store.getString('theme'), 'dark');
  });

  test('the network checker is disposed with the container', () async {
    final original = ConnectivityPlatform.instance;
    final platform = FakePlatform();
    ConnectivityPlatform.instance = platform;
    addTearDown(() => ConnectivityPlatform.instance = original);
    final container = ProviderContainer();
    container.read(networkCheckerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(platform.events.hasListener, isTrue);
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(platform.events.hasListener, isFalse);
  });

  group('SecureRefreshTokenStore', () {
    test('keeps the token under its key', () async {
      final secrets = FakeSecureStore();
      final store = SecureRefreshTokenStore(secrets, key: 'auth.refresh');
      await store.write('refresh-1');
      expect(secrets.snapshot, {'auth.refresh': 'refresh-1'});
      expect(await store.read(), 'refresh-1');
      await store.delete();
      expect(await store.read(), isNull);
      expect(SecureRefreshTokenStore(secrets).key, 'session.refreshToken');
    });
  });

  testWidgets('useNetworkChecker rebuilds on each change', (tester) async {
    final checker = FakeNetworkChecker();
    await tester.pumpWidget(
      HookBuilder(
        builder: (context) => Text(
          useNetworkChecker(checker).name,
          textDirection: TextDirection.ltr,
        ),
      ),
    );
    expect(find.text('online'), findsOneWidget);
    checker.goOffline();
    await tester.pump();
    expect(find.text('offline'), findsOneWidget);
    checker.goOnline();
    await tester.pump();
    expect(find.text('online'), findsOneWidget);
  });
}
