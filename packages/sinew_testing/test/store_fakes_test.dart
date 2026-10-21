import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_storage/sinew_storage.dart';
import 'package:sinew_testing/sinew_testing.dart';

/// The store fakes, and their failures through the app's real storage guard.
void main() {
  Future<SinewException> guarded(
    StorageAccess access,
    Future<void> Function() block,
  ) async => ((await processStorageCall(
    'ORD',
    'SAVE',
    access,
    block,
  )) as Failure).error;

  test('platform storage errors are classified by the real guard', () async {
    final read = await guarded(
      StorageAccess.read,
      () async => throw platformStorageError(),
    );
    expect(read, isA<StorageReadException>());
    expect(read.code, 'ORD-R-SAVE-SR');
    expect(
      await guarded(
        StorageAccess.write,
        () async => throw platformStorageError(),
      ),
      isA<StorageWriteException>(),
    );
    expect(
      await guarded(StorageAccess.write, () async => throw diskFullError()),
      isA<StorageFullException>(),
    );
  });

  group('FakeKeyValueStore', () {
    test('round-trips each type', () async {
      final store = FakeKeyValueStore();
      await store.setString('theme', 'dark');
      await store.setInt('launches', 3);
      await store.setBool('onboarded', true);
      await store.setDouble('ratio', 1.5);
      expect(await store.getString('theme'), 'dark');
      expect(await store.getInt('launches'), 3);
      expect(await store.getBool('onboarded'), isTrue);
      expect(await store.getDouble('ratio'), 1.5);
      expect(store.snapshot, {
        'theme': 'dark',
        'launches': 3,
        'onboarded': true,
        'ratio': 1.5,
      });
    });

    test('reads another type as absent', () async {
      final store = FakeKeyValueStore();
      await store.setInt('key', 7);
      expect(await store.getString('key'), isNull);
      expect(await store.getBool('key'), isNull);
      expect(await store.getInt('missing'), isNull);
    });

    test('removes and clears', () async {
      final store = FakeKeyValueStore();
      await store.setString('a', '1');
      await store.setString('b', '2');
      await store.remove('a');
      expect(store.snapshot, {'b': '2'});
      await store.clear();
      expect(store.snapshot, isEmpty);
    });

    test('can be inspected', () async {
      final store = FakeKeyValueStore(name: 'orders');
      await store.setString('theme', 'dark');
      await store.setInt('launches', 3);
      expect(store.name, 'orders');
      expect(await store.keys(), ['launches', 'theme']);
      expect(await store.read('launches'), '3');
      expect(await store.read('missing'), isNull);
    });

    test('fails the next read once', () async {
      final store = FakeKeyValueStore();
      await store.setString('theme', 'dark');
      final error = StateError('custom');
      store.failNextRead(error);
      await expectLater(store.getString('theme'), throwsA(same(error)));
      expect(await store.getString('theme'), 'dark');
      store.failNextRead();
      expect(
        await guarded(StorageAccess.read, () => store.getString('theme')),
        isA<StorageReadException>(),
      );
    });

    test('fails the next write once, writing nothing', () async {
      final store = FakeKeyValueStore();
      store.failNextWrite();
      expect(
        await guarded(StorageAccess.write, () => store.setString('t', 'dark')),
        isA<StorageWriteException>(),
      );
      expect(store.snapshot, isEmpty);
      await store.setString('t', 'dark');
      expect(await store.getString('t'), 'dark');
    });

    test('fails the next write with a full disk', () async {
      final store = FakeKeyValueStore();
      store.failNextWriteWithDiskFull();
      expect(
        await guarded(StorageAccess.write, () => store.setInt('launches', 1)),
        isA<StorageFullException>(),
      );
      await store.setInt('launches', 1);
      expect(await store.getInt('launches'), 1);
    });
  });

  group('FakeSecureStore', () {
    test('round-trips, deletes and clears', () async {
      final store = FakeSecureStore();
      await store.write('a', '1');
      await store.write('b', '2');
      expect(await store.read('a'), '1');
      await store.delete('a');
      expect(await store.read('a'), isNull);
      expect(await store.keys(), ['b']);
      await store.clearUserData();
      expect(store.snapshot, isEmpty);
      expect(store.name, 'fake');
    });

    test('fails the next read and write once', () async {
      final store = FakeSecureStore();
      await store.write('token', 'refresh');
      store.failNextRead();
      expect(
        await guarded(StorageAccess.read, () => store.read('token')),
        isA<StorageReadException>(),
      );
      expect(await store.read('token'), 'refresh');
      store.failNextWrite();
      expect(
        await guarded(StorageAccess.write, () => store.write('token', 'new')),
        isA<StorageWriteException>(),
      );
      expect(await store.read('token'), 'refresh');
      store.failNextWrite();
      await expectLater(store.clearUserData(), throwsA(isA<Exception>()));
      expect(await store.read('token'), 'refresh');
    });

    test(
      'a lost key makes every stored secret absent, new ones work',
      () async {
        final store = FakeSecureStore();
        await store.write('a', '1');
        await store.write('b', '2');
        store.loseKey();
        expect(await store.read('a'), isNull);
        expect(await store.read('b'), isNull);
        expect(await store.keys(), isEmpty);
        await store.write('a', 'new');
        expect(await store.read('a'), 'new');
      },
    );

    test('a lost key leaves no keys to inspect', () async {
      final store = FakeSecureStore();
      await store.write('a', '1');
      store.loseKey();
      expect(await store.keys(), isEmpty);
    });
  });

  group('FakeRefreshTokenStore', () {
    test('holds, replaces and deletes', () async {
      final store = FakeRefreshTokenStore('first');
      expect(await store.read(), 'first');
      await store.write('second');
      expect(store.token, 'second');
      await store.delete();
      expect(await store.read(), isNull);
    });

    test('fails the next read and write once', () async {
      final store = FakeRefreshTokenStore('token');
      store.failNextRead();
      expect(
        await guarded(StorageAccess.read, store.read),
        isA<StorageReadException>(),
      );
      expect(await store.read(), 'token');
      store.failNextWrite();
      await expectLater(store.write('new'), throwsA(isA<Exception>()));
      expect(await store.read(), 'token');
      store.failNextWrite();
      await expectLater(store.delete(), throwsA(isA<Exception>()));
      expect(await store.read(), 'token');
    });
  });
}
