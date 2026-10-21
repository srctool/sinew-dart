// Every integration test in one app, for CI: one build and one install per
// device instead of one per file. Locally, run a file on its own, or the
// folder; this file would repeat the others in a folder run.
import 'biometric_vault_test.dart' as biometric_vault;
import 'key_value_store_test.dart' as key_value_store;
import 'network_checker_test.dart' as network_checker;
import 'secure_store_test.dart' as secure_store;
import 'storage_guard_test.dart' as storage_guard;

void main() {
  biometric_vault.main();
  key_value_store.main();
  network_checker.main();
  secure_store.main();
  storage_guard.main();
}
