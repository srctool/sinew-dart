import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_devtools/sinew_devtools.dart';

void main() {
  test('devtools are on in a debug build, whatever the flavor', () {
    expect(kDebugMode, isTrue);
    expect(DevToolsGate.enabled, isTrue);
    expect(DevToolsGate.flavor, ''); // tests define no SINEW_FLAVOR
  });

  group('assertMatchesFlavor', () {
    test('a define that names another flavor throws', () {
      expect(
        () => DevToolsGate.checkFlavor(define: 'staging', appFlavor: 'production'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('"staging"'), contains('"production"')),
          ),
        ),
      );
      expect(
        () => DevToolsGate.checkFlavor(define: 'production', appFlavor: 'staging'),
        throwsStateError,
      );
    });

    test('a matching define passes', () {
      DevToolsGate.checkFlavor(define: 'staging', appFlavor: 'staging');
      DevToolsGate.checkFlavor(define: 'production', appFlavor: 'production');
    });

    test('a missing define passes: devtools are off, which fails safe', () {
      DevToolsGate.checkFlavor(define: '', appFlavor: 'production');
    });

    test('an app without flavors follows the define alone', () {
      DevToolsGate.checkFlavor(define: 'staging', appFlavor: null);
    });

    test('this test run, with neither, passes', () {
      DevToolsGate.assertMatchesFlavor();
    });
  });
}
