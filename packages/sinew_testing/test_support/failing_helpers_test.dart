// Run by test/helpers_failing_test.dart in a separate `flutter test`: both
// tests fail on purpose, and the output shows what the helpers did about it.
// Outside test/, so the suite never runs it directly.
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_testing/sinew_testing.dart';

void main() {
  tearDownAll(() {
    // ignore: avoid_print
    print(
      'REPORTER_RESTORED=${identical(CrashReporter.current, CrashReporter.none)}',
    );
  });

  test('a call left pending fails the test', () {
    final fetch = controlledFetch<String>();
    fetch.call(1, '');
  });

  test('a failing test still gets the reporter put back', () {
    installRecordingReporter();
    fail('on purpose');
  });
}
