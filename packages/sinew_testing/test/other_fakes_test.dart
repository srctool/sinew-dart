import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_testing/sinew_testing.dart';

void main() {
  const offline = NoInternetConnectionException(
    'ORD',
    ExceptionLayer.repository,
    'GO',
  );

  group('RecordingCrashReporter', () {
    test('records and clears', () {
      final reporter = RecordingCrashReporter()
        ..recordNonFatal(offline, StackTrace.empty);
      expect(reporter.reports, [offline]);
      expect(reporter.codes, [offline.code]);
      reporter.clear();
      expect(reporter.reports, isEmpty);
    });
  });

  group('FakeLocalizer', () {
    test('resolves, fills arguments and records keys', () {
      final localizer = FakeLocalizer(strings: {'greeting': 'Halo, {name}!'});
      expect(localizer.resolve('greeting', {'name': 'Ana'}), 'Halo, Ana!');
      expect(localizer.resolve('missing', {}), 'missing');
      expect(localizer.requested, ['greeting', 'missing']);
    });

    test('without echo, a missing key falls back to English', () {
      final localizer = FakeLocalizer(echoKeys: false);
      expect(localizer.resolve('sinew.error.noInternet', {}), isNull);
      expect(
        offline.displayMessage(localizer),
        '${offline.message.text} (${offline.code})',
      );
    });
  });
}
