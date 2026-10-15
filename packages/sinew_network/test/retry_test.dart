import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_network/src/retry.dart';

/// Always the longest wait the jitter allows.
final class Longest implements Random {
  @override
  int nextInt(int max) => max - 1;
  @override
  double nextDouble() => throw UnimplementedError();
  @override
  bool nextBool() => throw UnimplementedError();
}

/// Always no jitter at all.
final class Shortest implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => throw UnimplementedError();
  @override
  bool nextBool() => throw UnimplementedError();
}

const l = ExceptionLayer.repository;
const offline = NoInternetConnectionException('ORD', l, 'LIST');
const busy = ServiceUnavailableException('ORD', l, 'LIST', status: 503);

/// Answers each call from [answers] in turn, the last one repeated, and counts the calls.
final class Answers<T> {
  Answers(this.answers);

  final List<Result<T>> answers;
  var calls = 0;

  Future<Result<T>> next() async => answers[min(calls++, answers.length - 1)];
}

/// Runs [body] on a fake clock and returns its result with the time it took.
(R, Duration) timed<R>(Future<R> Function() body) {
  late R value;
  late Duration took;
  fakeAsync((async) {
    var done = false;
    body().then((v) {
      value = v;
      done = true;
    });
    async.flushMicrotasks();
    while (true) {
      async.elapse(
        Duration.zero,
      ); // whatever is due now, zero-length waits included
      if (done) break;
      async.elapse(const Duration(milliseconds: 1));
    }
    took = async.elapsed;
  });
  return (value, took);
}

void main() {
  group('retryWithBackoff', () {
    Future<Result<int>> retry(
      Answers<int> answers, {
      int maxAttempts = 3,
      Random? random,
      bool Function(SinewException)? retryIf,
    }) => retryWithBackoffUsing(
      answers.next,
      random ?? Longest(),
      maxAttempts: maxAttempts,
      initialDelay: const Duration(milliseconds: 500),
      maxDelay: const Duration(seconds: 5),
      retryIf: retryIf,
    );

    test('a success is returned at once', () {
      final answers = Answers([const Success(1)]);
      final (result, took) = timed(() => retry(answers));
      expect(result, const Success(1));
      expect(answers.calls, 1);
      expect(took, Duration.zero);
    });

    test('retryable failures are retried with growing waits', () {
      final answers = Answers<int>([
        const Failure(offline),
        const Failure(busy),
        const Success(1),
      ]);
      final (result, took) = timed(() => retry(answers));
      expect(result, const Success(1));
      expect(answers.calls, 3);
      expect(took, const Duration(milliseconds: 500 + 1000));
    });

    test('giving up returns the last failure unchanged', () {
      const last = ServiceUnavailableException('ORD', l, 'LIST', status: 504);
      final answers = Answers<int>([
        const Failure(offline),
        const Failure(offline),
        const Failure(last),
      ]);
      final (result, _) = timed(() => retry(answers));
      expect(identical((result as Failure<int>).error, last), isTrue);
      expect(answers.calls, 3);
    });

    test('a non-retryable failure stops at once', () {
      const bug = ServerException('ORD', l, 'LIST', status: 500);
      final answers = Answers<int>([const Failure(bug)]);
      final (result, took) = timed(() => retry(answers));
      expect(identical((result as Failure<int>).error, bug), isTrue);
      expect(answers.calls, 1);
      expect(took, Duration.zero);
    });

    test('retryIf decides', () {
      final answers = Answers<int>([
        const Failure(ServerException('ORD', l, 'LIST', status: 500)),
        const Success(1),
      ]);
      final (result, _) = timed(
        () => retry(answers, retryIf: (e) => e is ServerException),
      );
      expect(result, const Success(1));
    });

    test('the wait is capped at maxDelay', () {
      final (_, took) = timed(
        () => retry(Answers<int>([const Failure(offline)]), maxAttempts: 6),
      );
      expect(
        took,
        const Duration(milliseconds: 500 + 1000 + 2000 + 4000 + 5000),
      );
    });

    test('full jitter can wait nothing', () {
      final (_, took) = timed(
        () => retry(Answers<int>([const Failure(offline)]), random: Shortest()),
      );
      expect(took, Duration.zero);
    });

    test('a 429 waits at least its retryAfter', () {
      final answers = Answers<int>([
        const Failure(
          RateLimitedException(
            'ORD',
            l,
            'LIST',
            retryAfter: Duration(seconds: 2),
          ),
        ),
        const Success(1),
      ]);
      final (result, took) = timed(() => retry(answers, random: Shortest()));
      expect(result, const Success(1));
      expect(took, const Duration(seconds: 2));
    });

    test('a 429 asking for longer than maxDelay is returned at once', () {
      const tooLong = RateLimitedException(
        'ORD',
        l,
        'LIST',
        retryAfter: Duration(seconds: 120),
      );
      final answers = Answers<int>([const Failure(tooLong)]);
      final (result, took) = timed(() => retry(answers));
      expect(identical((result as Failure<int>).error, tooLong), isTrue);
      expect(answers.calls, 1);
      expect(took, Duration.zero);
    });

    test('one attempt never waits', () {
      final (_, took) = timed(
        () => retry(Answers<int>([const Failure(offline)]), maxAttempts: 1),
      );
      expect(took, Duration.zero);
    });

    test('the settings are checked', () {
      Future<Result<int>> ok() async => const Success(1);
      expect(() => retryWithBackoff(ok, maxAttempts: 0), throwsArgumentError);
      expect(
        () => retryWithBackoff(ok, initialDelay: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => retryWithBackoff(
          ok,
          initialDelay: const Duration(seconds: 10),
          maxDelay: const Duration(seconds: 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('poll', () {
    Future<Result<bool>> run(
      Answers<bool> answers, {
      Random? random,
      Duration timeout = const Duration(seconds: 60),
    }) => pollUsing(
      'PAY',
      'STATUS',
      answers.next,
      random ?? Longest(),
      until: (done) => done,
      interval: const Duration(seconds: 2),
      maxInterval: const Duration(seconds: 10),
      timeout: timeout,
    );

    const pending = Success(false);
    const done = Success(true);

    test('a finished process is returned at once', () {
      final (result, took) = timed(() => run(Answers([done])));
      expect(result, done);
      expect(took, Duration.zero);
    });

    test('the interval grows by half each time', () {
      final answers = Answers([pending, pending, pending, done]);
      final (result, took) = timed(() => run(answers));
      expect(result, done);
      expect(answers.calls, 4);
      expect(took, const Duration(milliseconds: 2000 + 3000 + 4500));
    });

    test('jitter keeps at least half the interval', () {
      final (_, took) = timed(
        () => run(Answers([pending, pending, done]), random: Shortest()),
      );
      expect(took, const Duration(milliseconds: 1000 + 1500));
    });

    test('the interval is capped at maxInterval', () {
      final (_, took) = timed(
        () => run(
          Answers([pending, pending, pending, pending, pending, pending, done]),
        ),
      );
      expect(
        took,
        const Duration(milliseconds: 2000 + 3000 + 4500 + 6750 + 10000 + 10000),
      );
    });

    test('a retryable failure keeps polling', () {
      final answers = Answers<bool>([const Failure(offline), pending, done]);
      final (result, _) = timed(() => run(answers));
      expect(result, done);
      expect(answers.calls, 3);
    });

    test('a non-retryable failure stops at once', () {
      const bug = ServerException('PAY', l, 'STATUS', status: 500);
      final answers = Answers<bool>([pending, const Failure(bug)]);
      final (result, _) = timed(() => run(answers));
      expect(identical((result as Failure<bool>).error, bug), isTrue);
      expect(answers.calls, 2);
    });

    test('past the timeout it is a PollingTimeOutException', () {
      final (result, took) = timed(() => run(Answers([pending])));
      final error = (result as Failure<bool>).error;
      expect(error, isA<PollingTimeOutException>());
      expect(error.code, 'PAY-R-STATUS-PTO');
      expect(error.cause, isNull);
      expect(took, const Duration(seconds: 60));
    });

    test('the timeout carries the last failure', () {
      final (result, _) = timed(
        () => run(Answers<bool>([const Failure(offline)])),
      );
      final error = (result as Failure<bool>).error;
      expect(error, isA<PollingTimeOutException>());
      expect(identical(error.cause, offline), isTrue);
    });

    test('a slow call is cut at the timeout, and its late result ignored', () {
      var calls = 0;
      final (result, took) = timed(
        () => pollUsing<bool>(
          'PAY',
          'STATUS',
          () async {
            calls++;
            await Future<void>.delayed(const Duration(seconds: 30));
            return done;
          },
          Longest(),
          until: (d) => d,
          timeout: const Duration(seconds: 5),
        ),
      );
      expect((result as Failure<bool>).error, isA<PollingTimeOutException>());
      expect(took, const Duration(seconds: 5));
      expect(calls, 1);
    });

    test('the settings are checked', () {
      Future<Result<bool>> ok() async => done;
      expect(
        () => poll('P', 'S', ok, until: (d) => d, interval: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => poll(
          'P',
          'S',
          ok,
          until: (d) => d,
          interval: const Duration(seconds: 5),
          maxInterval: const Duration(seconds: 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => poll('P', 'S', ok, until: (d) => d, timeout: Duration.zero),
        throwsArgumentError,
      );
    });
  });
}
