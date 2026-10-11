import 'package:sinew_models/sinew_models.dart';

/// Where the guards report bugs (unexpected and parse failures).
///
/// The one documented global in Sinew: installed once at the app's
/// composition root, [none] by default. Reports use the exception's code and
/// English text, never a translated text.
abstract interface class CrashReporter {
  /// Records a failure that was handled but points at a bug.
  void recordNonFatal(SinewException error, StackTrace? stackTrace);

  /// Records nothing. The default.
  static const CrashReporter none = _NoCrashReporter();

  static CrashReporter _current = none;

  /// What the guards call.
  static CrashReporter get current => _current;

  /// Installs [reporter], replacing any earlier one. Tests reset with
  /// `CrashReporter.install(CrashReporter.none)`.
  static void install(CrashReporter reporter) => _current = reporter;
}

class _NoCrashReporter implements CrashReporter {
  const _NoCrashReporter();

  @override
  void recordNonFatal(SinewException error, StackTrace? stackTrace) {}
}
