import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether devtools exist in this build, decided by the compiler.
///
/// | Build | `enabled` |
/// |---|---|
/// | debug, any flavor | `true` |
/// | release or profile, a non-production `SINEW_FLAVOR` | `true` |
/// | release or profile, `SINEW_FLAVOR=production` | `false` |
/// | release or profile, no `SINEW_FLAVOR` | `false`: a forgotten define fails safe |
///
/// [enabled] is a `const`, so every branch behind it is removed from a build
/// where it's `false`: put each devtools entry point behind it in `main`.
///
/// ```dart
/// void main() {
///   DevToolsGate.assertMatchesFlavor();
///   runApp(DevToolsGate.enabled ? SinewDevTools(child: const App()) : const App());
/// }
/// ```
///
/// A profile build is release-signed and installable, so `kDebugMode` alone is
/// never the gate.
abstract final class DevToolsGate {
  /// The flavor this build was compiled for:
  /// `--dart-define=SINEW_FLAVOR=staging`. Empty when it wasn't defined.
  static const flavor = String.fromEnvironment('SINEW_FLAVOR');

  /// Whether devtools are compiled into this build.
  static const enabled = kDebugMode || (flavor != '' && flavor != 'production');

  /// Throws a [StateError] when `SINEW_FLAVOR` names another flavor than the
  /// one being run (`flutter run --flavor`, Flutter's `appFlavor`), in every
  /// build mode, so a build can't run the production flavor with a staging
  /// define, or the reverse. A missing define, or an app without flavors,
  /// passes: devtools are then off, or follow the define alone.
  static void assertMatchesFlavor() =>
      checkFlavor(define: flavor, appFlavor: appFlavor);

  /// [assertMatchesFlavor]'s rule, for tests.
  @visibleForTesting
  static void checkFlavor({
    required String define,
    required String? appFlavor,
  }) {
    if (define.isEmpty || appFlavor == null || define == appFlavor) return;
    throw StateError(
      'SINEW_FLAVOR is "$define" but the app runs the "$appFlavor" flavor: '
      'build with --dart-define=SINEW_FLAVOR=$appFlavor.',
    );
  }
}
