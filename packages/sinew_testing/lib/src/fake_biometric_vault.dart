import 'dart:collection';

import 'package:sinew_security/sinew_security.dart';

/// A [BiometricVault] with no prompt: [availabilityNow] is what the test
/// sets, a store succeeds unless the test scripts a failure, and an unlock
/// releases the stored secret unless the test scripts one. [prompts] records
/// each prompt's reason. Like the real vault, nothing stored unlocks as
/// [BiometricFailure.invalidated], and anything but
/// [BiometricAvailability.available] fails as [BiometricFailure.unavailable].
final class FakeBiometricVault implements BiometricVault {
  /// A vault reporting [availabilityNow].
  FakeBiometricVault({this.availabilityNow = BiometricAvailability.available});

  /// What [availability] reports.
  BiometricAvailability availabilityNow;

  String? _secret;
  final _nextStores = Queue<BiometricFailure>();
  final _nextUnlocks = Queue<BiometricFailure>();
  final _prompts = <String>[];

  /// The reason of every prompt shown (each store and unlock), in order.
  List<String> get prompts => List.unmodifiable(_prompts);

  /// The stored secret, for assertions.
  String? get storedSecret => _secret;

  /// Makes the next store fail with [reason], storing nothing. Calls queue
  /// up.
  void nextStore(BiometricFailure reason) => _nextStores.add(reason);

  /// Makes the next unlock fail with [reason]. Calls queue up.
  void nextUnlock(BiometricFailure reason) => _nextUnlocks.add(reason);

  /// Invalidates the secret, as enrolling a new face or finger does.
  void invalidate() => _secret = null;

  @override
  Future<BiometricAvailability> availability() async => availabilityNow;

  @override
  Future<bool> isStored() async => _secret != null;

  @override
  Future<BiometricStore> store(String secret, {required String reason}) async {
    if (availabilityNow != BiometricAvailability.available) {
      return const BiometricFailed(BiometricFailure.unavailable);
    }
    _prompts.add(reason);
    if (_nextStores.isNotEmpty) {
      _secret = null;
      return BiometricFailed(_nextStores.removeFirst());
    }
    _secret = secret;
    return const Stored();
  }

  @override
  Future<BiometricUnlock> unlock({required String reason}) async {
    final stored = _secret;
    if (stored == null) {
      return const BiometricFailed(BiometricFailure.invalidated);
    }
    if (availabilityNow != BiometricAvailability.available) {
      return const BiometricFailed(BiometricFailure.unavailable);
    }
    _prompts.add(reason);
    if (_nextUnlocks.isNotEmpty) {
      return BiometricFailed(_nextUnlocks.removeFirst());
    }
    return Unlocked(stored);
  }

  @override
  Future<void> disable() async => _secret = null;
}
