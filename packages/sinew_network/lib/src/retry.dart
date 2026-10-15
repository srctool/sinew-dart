import 'dart:async';
import 'dart:math';

import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

/// Runs [block] again after a retryable failure, with exponential backoff and
/// full jitter: before attempt `n + 1` it waits a random time up to
/// `initialDelay × 2ⁿ`, capped at [maxDelay]. A 429 waits at least its
/// `retryAfter`; one asking for longer than [maxDelay] is returned at once,
/// so the page shows the wait instead of a spinner.
///
/// When it gives up, it returns the **last failure unchanged**, so the user
/// sees the real reason. A failure [retryIf] rejects (by default, one that
/// isn't `retryable`) is returned at once.
///
/// For idempotent requests only: reads, and writes carrying an
/// `Idempotency-Key`. Retry in one layer only, never around a call that's
/// already retried. The client itself never retries.
///
/// ```dart
/// retryWithBackoff(() => processApiCall('ORD', 'LIST', () => api.list(page)))
/// ```
Future<Result<T>> retryWithBackoff<T>(
  Future<Result<T>> Function() block, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 500),
  Duration maxDelay = const Duration(seconds: 5),
  bool Function(SinewException error)? retryIf,
}) => retryWithBackoffUsing(
  block,
  Random(),
  maxAttempts: maxAttempts,
  initialDelay: initialDelay,
  maxDelay: maxDelay,
  retryIf: retryIf,
);

/// [retryWithBackoff] with the [random] the jitter draws from: tests pass a
/// predictable one.
Future<Result<T>> retryWithBackoffUsing<T>(
  Future<Result<T>> Function() block,
  Random random, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 500),
  Duration maxDelay = const Duration(seconds: 5),
  bool Function(SinewException error)? retryIf,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be at least 1');
  }
  if (initialDelay <= Duration.zero || maxDelay < initialDelay) {
    throw ArgumentError('retryWithBackoff: 0 < initialDelay <= maxDelay');
  }
  final shouldRetry = retryIf ?? (SinewException e) => e.retryable;
  var attempt = 0;
  while (true) {
    final result = await block();
    if (result is! Failure<T>) return result;
    attempt++;
    if (attempt >= maxAttempts || !shouldRetry(result.error)) return result;
    final growth = initialDelay * (1 << min(attempt - 1, 30));
    final backoff = growth < maxDelay ? growth : maxDelay;
    final jittered = Duration(
      milliseconds: random.nextInt(backoff.inMilliseconds + 1),
    );
    final retryAfter = switch (result.error) {
      RateLimitedException(:final retryAfter) => retryAfter,
      _ => null,
    };
    if (retryAfter != null && retryAfter > maxDelay) return result;
    await Future<void>.delayed(
      retryAfter != null && retryAfter > jittered ? retryAfter : jittered,
    );
  }
}

/// Calls [block] until [until] accepts its data, for a backend process that
/// finishes later (a payment, an export). The wait between calls starts at
/// [interval] and grows by 1.5× up to [maxInterval], with jitter so many
/// clients don't call in step.
///
/// A retryable failure keeps polling; a non-retryable one is returned at
/// once. Past [timeout], the result is a [PollingTimeOutException] coded with
/// [module] and [function], with the last failure, if any, as its cause. A
/// call still in flight at the timeout can't be cancelled (a `Future` can't
/// be): it finishes in the background, and its result is ignored.
///
/// ```dart
/// poll('PAY', 'STATUS', () => processApiCall('PAY', 'STATUS', () => api.status(id)), until: (p) => !p.pending)
/// ```
Future<Result<T>> poll<T>(
  String module,
  String function,
  Future<Result<T>> Function() block, {
  required bool Function(T data) until,
  Duration interval = const Duration(seconds: 2),
  Duration maxInterval = const Duration(seconds: 10),
  Duration timeout = const Duration(seconds: 60),
}) => pollUsing(
  module,
  function,
  block,
  Random(),
  until: until,
  interval: interval,
  maxInterval: maxInterval,
  timeout: timeout,
);

/// [poll] with the [random] the jitter draws from: tests pass a predictable
/// one.
Future<Result<T>> pollUsing<T>(
  String module,
  String function,
  Future<Result<T>> Function() block,
  Random random, {
  required bool Function(T data) until,
  Duration interval = const Duration(seconds: 2),
  Duration maxInterval = const Duration(seconds: 10),
  Duration timeout = const Duration(seconds: 60),
}) {
  if (interval <= Duration.zero || maxInterval < interval) {
    throw ArgumentError('poll: 0 < interval <= maxInterval');
  }
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must be positive');
  }
  SinewException? lastFailure;
  var timedOut = false;

  Future<Result<T>> loop() async {
    var wait = interval;
    while (!timedOut) {
      final result = await block();
      if (timedOut) break;
      switch (result) {
        case Success(:final data) when until(data):
          return result;
        case Success():
          break;
        case Failure(:final error) when error.retryable:
          lastFailure = error;
        case Failure():
          return result;
      }
      // Equal jitter: half the wait fixed, half random, so the interval still grows.
      final half = wait.inMilliseconds ~/ 2;
      await Future<void>.delayed(
        Duration(milliseconds: half + random.nextInt(half + 1)),
      );
      final next = wait * 1.5;
      wait = next < maxInterval ? next : maxInterval;
    }
    return Failure(
      PollingTimeOutException(
        module,
        ExceptionLayer.repository,
        function,
        cause: lastFailure,
      ),
    );
  }

  return loop().timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      return Failure(
        PollingTimeOutException(
          module,
          ExceptionLayer.repository,
          function,
          cause: lastFailure,
        ),
      );
    },
  );
}
