import 'dart:ui' show ErrorCallback;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_devtools/sinew_devtools.dart';
import 'package:sinew_devtools/src/dev_tools.dart' show installUncaughtHooks;

void main() {
  late FlutterExceptionHandler? flutterOriginal;
  late ErrorCallback? platformOriginal;

  setUp(() {
    flutterOriginal = FlutterError.onError;
    platformOriginal = PlatformDispatcher.instance.onError;
  });
  tearDown(() {
    FlutterError.onError = flutterOriginal;
    PlatformDispatcher.instance.onError = platformOriginal;
    DevTools.exceptions.clear();
  });

  FlutterErrorDetails details(String message) =>
      FlutterErrorDetails(exception: StateError(message));

  test('the Flutter hook runs the previous handler first', () {
    final seen = <String>[];
    FlutterError.onError = (d) => seen.add('previous ${d.exception}');
    installUncaughtHooks((e, _) => seen.add('devtools $e'));
    FlutterError.onError!(details('boom'));
    expect(seen, ['previous Bad state: boom', 'devtools Bad state: boom']);
  });

  test('the platform hook keeps the previous handler\'s answer', () {
    final seen = <String>[];
    PlatformDispatcher.instance.onError = (e, _) {
      seen.add('previous $e');
      return true;
    };
    installUncaughtHooks((e, _) => seen.add('devtools $e'));
    expect(
      PlatformDispatcher.instance.onError!(
        StateError('boom'),
        StackTrace.empty,
      ),
      isTrue,
    );
    expect(seen, ['previous Bad state: boom', 'devtools Bad state: boom']);
  });

  test('without a previous handler the platform error stays unhandled', () {
    PlatformDispatcher.instance.onError = null;
    final seen = <Object>[];
    installUncaughtHooks((e, _) => seen.add(e));
    expect(
      PlatformDispatcher.instance.onError!(
        StateError('boom'),
        StackTrace.empty,
      ),
      isFalse,
    );
    expect(seen, hasLength(1));
  });

  test('a previous handler that throws is still recorded', () {
    final seen = <Object>[];
    FlutterError.onError = (_) => throw StateError('previous failed');
    installUncaughtHooks((e, _) => seen.add(e));
    expect(() => FlutterError.onError!(details('boom')), throwsStateError);
    expect(seen, hasLength(1));
  });

  test('a failure while recording never reaches the app', () {
    final seen = <String>[];
    FlutterError.onError = (d) => seen.add('previous');
    PlatformDispatcher.instance.onError = (e, _) {
      seen.add('previous platform');
      return true;
    };
    installUncaughtHooks((_, _) => throw StateError('recording failed'));
    FlutterError.onError!(details('boom'));
    expect(
      PlatformDispatcher.instance.onError!(StateError('x'), StackTrace.empty),
      isTrue,
    );
    expect(seen, ['previous', 'previous platform']);
  });

  test('captureUncaughtErrors records into the Exception Log once', () {
    FlutterError.onError = null;
    DevTools.captureUncaughtErrors();
    DevTools.captureUncaughtErrors(); // a second call doesn't stack another hook
    FlutterError.onError!(details('crash'));
    final row = DevTools.exceptions.records.value.single;
    expect(row.count, 1);
    expect(row.source, ExceptionSource.uncaught);
    expect(row.type, 'StateError');
  });
}
