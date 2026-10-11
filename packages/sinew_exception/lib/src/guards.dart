import 'package:sinew_models/sinew_models.dart';

import 'crash_reporter.dart';
import 'exceptions.dart';

/// One rule in a guard's handler list: "is this a timeout?" and "make a
/// RequestTimeOutException for this call".
class ExceptionHandler {
  /// Creates a handler.
  const ExceptionHandler(this.matches, this.transform);

  /// Whether this handler classifies [error].
  final bool Function(Object error) matches;

  /// The exception for [error], bound to the guard's module and function.
  final SinewException Function(Object error) transform;
}

/// The handler every list ends with: an envelope with no payload becomes a
/// [ParseException] for this call.
ExceptionHandler envelopeDataMissing(
  String module,
  String function,
  ExceptionLayer layer,
) => ExceptionHandler(
  (error) => error is EnvelopeDataMissing,
  (error) => ParseException(module, layer, function, cause: error),
);

/// The guard core every guard is built on, public so an app can guard calls
/// Sinew doesn't know about.
///
/// A [SinewException] from a lower layer passes through unchanged. Anything
/// else, Dart `Error`s included (a `TypeError` from a bad cast in
/// `toDomain()`), goes to the first matching handler or becomes an
/// [UnexpectedException]; unexpected and parse failures are reported.
/// The guarded block must await everything it starts: an un-awaited future's
/// error escapes the guard.
Future<Result<T>> processCall<T>(
  String module,
  String function,
  ExceptionLayer layer,
  List<ExceptionHandler> handlers,
  Future<T> Function() block,
) async {
  try {
    return Result.success(await block());
  } on SinewException catch (e, stackTrace) {
    return Result.failure(e, stackTrace);
  } catch (e, stackTrace) {
    final mapped =
        _runHandlers(handlers, e) ??
        UnexpectedException(module, layer, function, cause: e);
    if (mapped is UnexpectedException || mapped is ParseException) {
      _reportSafely(mapped, stackTrace);
    }
    return Result.failure(mapped, stackTrace);
  }
}

/// The use-case guard: no handlers, so repository failures and domain
/// exceptions pass through, and a bug becomes `…-UC-…-GEN`.
Future<Result<T>> processUseCase<T>(
  String module,
  String function,
  Future<T> Function() body,
) => processCall(module, function, ExceptionLayer.useCase, const [], body);

/// First match wins. A handler that throws counts as unmatched, so a broken
/// handler never crashes the app.
SinewException? _runHandlers(List<ExceptionHandler> handlers, Object error) {
  for (final handler in handlers) {
    try {
      if (handler.matches(error)) return handler.transform(error);
    } catch (_) {
      // a broken handler counts as unmatched
    }
  }
  return null;
}

/// Reporting never turns a handled failure into a crash.
void _reportSafely(SinewException error, StackTrace stackTrace) {
  try {
    CrashReporter.current.recordNonFatal(error, stackTrace);
  } catch (_) {
    // reporting never crashes the app
  }
}
