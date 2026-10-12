import 'package:sinew_network/sinew_network.dart';

/// A [TokenSource] a test drives by hand: it counts refreshes and clears, and
/// [onRefresh] decides each refresh.
///
/// By default a refresh rotates the token (`token-1` → `token-2` → …) and
/// returns [Refreshed]. Gate it on a `Completer` to hold a refresh open while
/// other requests pile up behind it:
///
/// ```dart
/// final gate = Completer<void>();
/// final tokens = FakeTokenSource()
///   ..onRefresh = (source) async { await gate.future; source.rotate(); return const Refreshed(); };
/// ```
final class FakeTokenSource implements TokenSource {
  /// Creates the source holding [accessToken].
  FakeTokenSource([String? accessToken = 'token-1'])
    : _token = accessToken,
      _generation =
          int.tryParse(accessToken?.replaceFirst('token-', '') ?? '') ?? 0;

  String? _token;
  int _generation;

  /// How many times [refresh] was called.
  int refreshes = 0;

  /// How many times [clear] was called.
  int clears = 0;

  /// Decides each refresh.
  Future<RefreshOutcome> Function(FakeTokenSource source) onRefresh = _rotate;

  static Future<RefreshOutcome> _rotate(FakeTokenSource source) async {
    source.rotate();
    return const Refreshed();
  }

  /// Replaces the access token with the next one, `token-<n + 1>`, and
  /// returns it.
  String rotate() => _token = 'token-${++_generation}';

  @override
  String? accessToken() => _token;

  /// Like a real source, a [Rejected] refresh ends the session itself,
  /// counted in [clears].
  @override
  Future<RefreshOutcome> refresh() async {
    refreshes++;
    final outcome = await onRefresh(this);
    if (outcome is Rejected) await clear();
    return outcome;
  }

  @override
  Future<void> clear() async {
    clears++;
    _token = null;
  }
}
