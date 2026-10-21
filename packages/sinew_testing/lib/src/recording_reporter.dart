import 'package:sinew_exception/sinew_exception.dart';
import 'package:test_api/scaffolding.dart';

import 'recording_crash_reporter.dart';

/// Installs a [RecordingCrashReporter] for the rest of the test and puts the
/// previous reporter back when the test ends, passed or failed. Call it
/// inside a test or a `setUp`.
///
/// ```dart
/// test('a bug is reported', () async {
///   final reporter = installRecordingReporter();
///   await repository.load();
///   expect(reporter.codes, ['ORD-R-LOAD-GEN']);
/// });
/// ```
///
/// The reporter is global: tests that use it run one at a time, as tests in
/// a file do.
RecordingCrashReporter installRecordingReporter() {
  final previous = CrashReporter.current;
  final reporter = RecordingCrashReporter();
  CrashReporter.install(reporter);
  addTearDown(() => CrashReporter.install(previous));
  return reporter;
}
