import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

/// A [CrashReporter] that keeps every report, for assertions.
final class RecordingCrashReporter implements CrashReporter {
  final _reports = <SinewException>[];

  /// Every reported exception, in order.
  List<SinewException> get reports => List.unmodifiable(_reports);

  /// The codes of [reports], in order: the usual assertion.
  List<String> get codes => [for (final report in _reports) report.code];

  @override
  void recordNonFatal(SinewException error, StackTrace? stackTrace) =>
      _reports.add(error);

  /// Forgets every report.
  void clear() => _reports.clear();
}
