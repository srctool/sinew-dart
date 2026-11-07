import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_devtools/sinew_devtools.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_testing/sinew_testing.dart';

void main() {
  late DateTime now;
  late ExceptionRecorder recorder;

  NoInternetConnectionException offline([String function = 'list']) =>
      NoInternetConnectionException('ORD', ExceptionLayer.repository, function);

  setUp(() {
    now = DateTime.utc(2026, 11, 7, 10);
    recorder = ExceptionRecorder(clock: () => now);
  });
  tearDown(DevTools.exceptions.clear);

  test('repeats within the window are merged with a count', () {
    final start = now;
    recorder.record(offline(), null);
    now = now.add(const Duration(seconds: 1));
    recorder.record(offline(), null);
    final row = recorder.records.value.single;
    expect(row.count, 2);
    expect(row.firstAt, start);
    expect(row.lastAt, start.add(const Duration(seconds: 1)));
  });

  test('the window runs from the last repeat', () {
    recorder.record(offline(), null);
    now = now.add(const Duration(milliseconds: 1500));
    recorder.record(offline(), null);
    now = now.add(const Duration(milliseconds: 1500));
    recorder.record(
      offline(),
      null,
    ); // 3 s after the first, 1.5 s after the last
    expect(recorder.records.value.single.count, 3);
  });

  test('a repeat after the window is a new row', () {
    recorder.record(offline(), null);
    now = now.add(const Duration(milliseconds: 2001));
    recorder.record(offline(), null);
    expect([for (final r in recorder.records.value) r.count], [1, 1]);
    now = now.add(const Duration(seconds: 2));
    recorder.record(offline(), null); // exactly at the window: still a repeat
    expect([for (final r in recorder.records.value) r.count], [2, 1]);
  });

  test('different failures are separate rows', () {
    recorder
      ..record(offline('list'), null)
      ..record(offline('detail'), null)
      ..record(offline('list'), null, source: ExceptionSource.uncaught);
    expect(recorder.records.value, hasLength(3));
  });

  test('a merged row moves to the top', () {
    recorder
      ..record(offline('list'), null)
      ..record(offline('detail'), null)
      ..record(offline('list'), null);
    expect(
      [for (final r in recorder.records.value) r.code],
      [offline('list').code, offline('detail').code],
    );
  });

  test('the capacity drops the oldest row', () {
    final small = ExceptionRecorder(capacity: 2, clock: () => now);
    for (final f in ['a', 'b', 'c']) {
      small.record(offline(f), null);
    }
    expect(
      [for (final r in small.records.value) r.code],
      [offline('c').code, offline('b').code],
    );
  });

  test('the defaults are as designed', () {
    expect(ExceptionRecorder.defaultCapacity, 50);
    expect(ExceptionRecorder.defaultDedupeWindow, const Duration(seconds: 2));
    expect(() => ExceptionRecorder(capacity: 0), throwsArgumentError);
  });

  test('a row keeps the key, the server text or the error text', () {
    final local = offline();
    recorder.record(local, null);
    final row = recorder.records.value.single;
    expect(row.message, (local.message as LocalMessage).key);
    expect(row.type, 'NoInternetConnectionException');
    expect(row.code, local.code);
    expect(row.source, ExceptionSource.reported);

    recorder.record(
      const ApiErrorException(
        'ORD',
        ExceptionLayer.repository,
        'create',
        message: ServerMessage('Stok habis'),
      ),
      null,
    );
    expect(recorder.records.value.first.message, 'Stok habis');

    recorder.record(StateError('plain'), null);
    expect(recorder.records.value.first.message, 'Bad state: plain');
    expect(recorder.records.value.first.code, isNull);
  });

  test('the message and stack trace are redacted', () {
    recorder.record(
      Exception(
        'GET https://api.test/me?token=abc123 failed, '
        'Authorization: Bearer xyz789',
      ),
      StackTrace.fromString('#0 main (file:///app.dart:1)\nfetch?token=abc123'),
    );
    final row = recorder.records.value.single;
    for (final stored in [
      row.message,
      row.stackTrace,
      row.asText(),
      row.toString(),
    ]) {
      expect(stored, isNot(contains('abc123')));
      expect(stored, isNot(contains('xyz789')));
    }
    expect(row.message, contains('https://api.test/me'));
    expect(row.stackTrace, contains('#0 main'));
  });

  test('a cause is kept, redacted', () {
    recorder.record(
      const ParseException(
        'ORD',
        ExceptionLayer.repository,
        'list',
        cause: FormatException('{"password":"hunter2"}'),
      ),
      null,
    );
    final trace = recorder.records.value.single.stackTrace;
    expect(trace, startsWith('Caused by: FormatException'));
    expect(trace, isNot(contains('hunter2')));
  });

  test('asText is a bug report', () {
    final error = offline();
    recorder
      ..record(error, null)
      ..record(error, null);
    final text = recorder.records.value.single.asText();
    expect(
      text,
      startsWith('NoInternetConnectionException ${error.code} ×2\n'),
    );
    expect(
      text,
      contains(
        'reported · first 2026-11-07T10:00:00.000Z '
        '· last 2026-11-07T10:00:00.000Z',
      ),
    );
  });

  test('the rows notify their listeners and cannot be changed', () {
    var calls = 0;
    recorder.records.addListener(() => calls++);
    recorder
      ..record(offline(), null)
      ..record(offline(), null)
      ..clear();
    expect(calls, 3);
    recorder.record(offline(), null);
    expect(() => recorder.records.value.clear(), throwsUnsupportedError);
  });

  test('the wrapped reporter receives every report', () {
    final real = RecordingCrashReporter();
    final reporter = DevToolsCrashReporter(wrapping: real, recorder: recorder);
    final error = offline();
    reporter
      ..recordNonFatal(error, null)
      ..recordNonFatal(error, null);
    expect(real.reports, [error, error]); // unchanged, and every one of them
    expect(recorder.records.value.single.count, 2); // while the log merges them
  });

  test('the crash reporter uses DevTools by default', () {
    DevToolsCrashReporter(wrapping: RecordingCrashReporter())
        .recordNonFatal(offline(), StackTrace.current);
    expect(DevTools.exceptions.records.value, hasLength(1));
  });
}
