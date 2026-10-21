import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_storage/sinew_storage.dart';

/// The stores' real calls through the guard on this platform: each works, or
/// fails with a typed storage exception, never an unexpected one. On an
/// ad-hoc signed macOS build the Keychain refuses `FieldCipher`'s key
/// (-34018), which must come back as a `StorageReadException`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Result<T>> guard<T>(
    StorageAccess access,
    Future<T> Function() block,
  ) => processStorageCall('EX', 'STORE', access, block);

  void expectTyped(Result<Object?> result) {
    if (result case Failure(:final error)) {
      // ignore: avoid_print
      print('storage guard: ${error.code} (${error.cause})');
      expect(
        error,
        anyOf(
          isA<StorageReadException>(),
          isA<StorageWriteException>(),
          isA<StorageFullException>(),
          isA<LocalStorageCorruptionException>(),
        ),
      );
    }
  }

  testWidgets('the stores never fail with an unexpected exception', (_) async {
    final prefs = KeyValueStore.create(name: 'sinew_guard');
    expectTyped(
      await guard(StorageAccess.write, () => prefs.setString('k', 'v')),
    );
    expectTyped(await guard(StorageAccess.read, () => prefs.getString('k')));
    expectTyped(await guard(StorageAccess.write, prefs.clear));

    final opened = await guard(
      StorageAccess.read,
      () => SecureStore.create(namespace: 'guard'),
    );
    expectTyped(opened);
    if (opened case Success(data: final secrets)) {
      expectTyped(
        await guard(StorageAccess.write, () => secrets.write('t', 's')),
      );
      expectTyped(await guard(StorageAccess.read, () => secrets.read('t')));
      expectTyped(await guard(StorageAccess.write, secrets.clearUserData));
    }
  });
}
