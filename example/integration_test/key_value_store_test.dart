import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// The same suite the unit tests run in memory, here on the platform's storage.
// ignore: avoid_relative_lib_imports
import '../../packages/sinew_storage/test/key_value_store_contract.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('KeyValueStore on this platform', keyValueStoreContract);
}
