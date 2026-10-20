import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sinew_storage/sinew_storage.dart';

// The same suite the unit tests run over in-memory plugins, here on the
// platform's storage and key storage.
// ignore: avoid_relative_lib_imports
import '../../packages/sinew_storage/test/secure_store_contract.dart';

/// Set by `tool/secure_store_reinstall_test.sh`: `before` stores a secret,
/// the script uninstalls and reinstalls the app, and `after` finds none.
const reinstallPhase = String.fromEnvironment('SINEW_REINSTALL_PHASE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (reinstallPhase.isEmpty) {
    group('SecureStore on this platform', secureStoreContract);
    return;
  }

  testWidgets('a reinstall starts empty ($reinstallPhase)', (_) async {
    final store = await SecureStore.create(namespace: 'reinstall');
    if (reinstallPhase == 'before') {
      await store.write('token', 'refresh-token');
      expect(await store.read('token'), 'refresh-token');
    } else {
      expect(await store.read('token'), isNull);
    }
  });
}
