@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs test_support/failing_helpers_test.dart in its own `flutter test`:
/// a test that fails on purpose can't be checked from inside its own run.
void main() {
  test(
    'a pending call fails its test, and a failed test restores the reporter',
    () async {
      final run = await Process.run('flutter', [
        'test',
        'test_support/failing_helpers_test.dart',
        '--no-pub',
      ]);
      final output = '${run.stdout}${run.stderr}';
      expect(run.exitCode, isNot(0), reason: output);
      expect(output, contains('Calls [0] were never answered'));
      expect(output, contains('on purpose'));
      expect(output, contains('REPORTER_RESTORED=true'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
