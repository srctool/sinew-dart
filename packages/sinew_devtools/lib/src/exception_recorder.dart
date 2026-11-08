import 'package:flutter/foundation.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

import 'dev_tools.dart';
import 'redaction.dart';

/// How an exception reached the Exception Log.
enum ExceptionSource {
  /// Through the `CrashReporter`: handled, but pointing at a bug.
  reported,

  /// Through `FlutterError.onError` or `PlatformDispatcher.onError`.
  uncaught,
}

/// A row in the Exception Log. Repeats within the recorder's window are merged
/// into one row: [count] says how many, [firstAt] and [lastAt] when. The
/// message and the stack trace went through [Redaction.redactText].
@immutable
final class ExceptionRecord {
  /// A row. Rows are made by [ExceptionRecorder].
  const ExceptionRecord({
    required this.id,
    required this.firstAt,
    required this.lastAt,
    required this.type,
    required this.code,
    required this.message,
    required this.stackTrace,
    required this.count,
    required this.source,
  });

  /// The row's number, rising with each new row.
  final int id;

  /// When it was first seen.
  final DateTime firstAt;

  /// When it was last seen.
  final DateTime lastAt;

  /// The exception's type, such as `ParseException`.
  final String type;

  /// The Sinew code (`ORD-R-list-DF`), when it's a [SinewException].
  final String? code;

  /// The message key of a local message, the server's text, or a plain
  /// error's text.
  final String message;

  /// The redacted stack trace, with the cause when there is one.
  final String stackTrace;

  /// How many times it was seen within the window.
  final int count;

  /// How it reached the log.
  final ExceptionSource source;

  /// The row as text, for a bug report: already redacted.
  String asText() {
    final out = StringBuffer(type);
    if (code != null) out.write(' $code');
    if (count > 1) out.write(' ×$count');
    out.writeln();
    if (message.isNotEmpty) out.writeln(message);
    out
      ..writeln(
        '${source.name} · first ${firstAt.toIso8601String()} '
        '· last ${lastAt.toIso8601String()}',
      )
      ..writeln()
      ..write(stackTrace);
    return out.toString().trimRight();
  }

  ExceptionRecord _repeated(DateTime at) => ExceptionRecord(
    id: id,
    firstAt: firstAt,
    lastAt: at,
    type: type,
    code: code,
    message: message,
    stackTrace: stackTrace,
    count: count + 1,
    source: source,
  );

  @override
  String toString() =>
      'ExceptionRecord(#$id $type $code ×$count, message: $message)';
}

/// The Exception Log's rows, in memory only, newest first. An exception that
/// repeats within [dedupeWindow] of the last time it was seen (same type,
/// code, message and source) is merged into that row, which moves to the top
/// with its count raised. Holds at most [capacity] rows and drops the oldest.
final class ExceptionRecorder {
  /// A recorder that keeps [capacity] rows.
  ExceptionRecorder({
    this.capacity = defaultCapacity,
    this.dedupeWindow = defaultDedupeWindow,
    Redaction? redaction,
    DateTime Function()? clock,
  }) : redaction = redaction ?? Redaction.standard,
       _clock = clock ?? DateTime.now {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  /// The default number of rows kept.
  static const defaultCapacity = 50;

  /// The default window within which a repeat is merged.
  static const defaultDedupeWindow = Duration(seconds: 2);

  /// How many rows are kept.
  final int capacity;

  /// How close to the last time a repeat must be to merge.
  final Duration dedupeWindow;

  /// What's hidden before a record is stored. `SinewDevTools(redaction:)`
  /// sets the app's rules.
  Redaction redaction;

  final DateTime Function() _clock;
  final _records = ValueNotifier<List<ExceptionRecord>>(const []);
  var _ids = 0;

  /// The rows, newest first.
  ValueListenable<List<ExceptionRecord>> get records => _records;

  /// Records [error], merging it into a recent identical row.
  void record(
    Object error,
    StackTrace? stackTrace, {
    ExceptionSource source = ExceptionSource.reported,
  }) {
    final now = _clock();
    final type = error.runtimeType.toString();
    final code = error is SinewException ? error.code : null;
    final message = redaction.redactText(switch (error) {
      SinewException(message: LocalMessage(:final key)) => key,
      SinewException(message: ServerMessage(:final text)) => text,
      _ => error.toString(),
    });
    final rows = _records.value;
    final repeat = rows.indexWhere(
      (row) =>
          row.type == type &&
          row.code == code &&
          row.message == message &&
          row.source == source &&
          now.difference(row.lastAt) <= dedupeWindow,
    );
    if (repeat >= 0) {
      _records.value = List.unmodifiable([
        rows[repeat]._repeated(now),
        ...rows.take(repeat),
        ...rows.skip(repeat + 1),
      ]);
      return;
    }
    final cause = error is SinewException ? error.cause : null;
    final trace = [
      if (stackTrace != null) '$stackTrace'.trimRight(),
      if (cause != null) 'Caused by: $cause',
    ].join('\n');
    _records.value = List.unmodifiable(
      [
        ExceptionRecord(
          id: ++_ids,
          firstAt: now,
          lastAt: now,
          type: type,
          code: code,
          message: message,
          stackTrace: redaction.redactText(trace),
          count: 1,
          source: source,
        ),
        ...rows,
      ].take(capacity),
    );
  }

  /// Forgets every row: on "Clear".
  void clear() => _records.value = const [];
}

/// Wraps the app's real [CrashReporter]: every report goes to the Exception
/// Log, then on to [wrapping] unchanged. Install it at the composition root:
/// `CrashReporter.install(DevToolsCrashReporter(wrapping: realReporter))`.
final class DevToolsCrashReporter implements CrashReporter {
  /// A reporter that records into [recorder] (`DevTools.exceptions` by
  /// default), then calls [wrapping].
  DevToolsCrashReporter({required this.wrapping, this.recorder});

  /// The app's real reporter.
  final CrashReporter wrapping;

  /// Where reports are recorded, or `null` for `DevTools.exceptions`.
  final ExceptionRecorder? recorder;

  @override
  void recordNonFatal(SinewException error, StackTrace? stackTrace) {
    try {
      (recorder ?? DevTools.exceptions).record(error, stackTrace);
    } finally {
      // The real reporter gets every report, whatever devtools does.
      wrapping.recordNonFatal(error, stackTrace);
    }
  }
}
