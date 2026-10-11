import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:test/test.dart';

class _RecordingReporter implements CrashReporter {
  final reports = <SinewException>[];
  final traces = <StackTrace?>[];

  @override
  void recordNonFatal(SinewException error, StackTrace? stackTrace) {
    reports.add(error);
    traces.add(stackTrace);
  }
}

class _ThrowingReporter implements CrashReporter {
  @override
  void recordNonFatal(SinewException error, StackTrace? stackTrace) =>
      throw StateError('reporter down');
}

class _OutOfStockException extends SinewException {
  const _OutOfStockException() : super('ORD', ExceptionLayer.useCase, 'PO');

  @override
  String get typeCode => 'OOS';

  @override
  ErrorMessage get message =>
      const LocalMessage('orders.error.outOfStock', fallback: 'Out of stock.');
}

void main() {
  late _RecordingReporter reporter;
  final timeoutHandler = ExceptionHandler(
    (e) => e is StateError && e.message == 'timeout',
    (e) => RequestTimeOutException(
      'ORD',
      ExceptionLayer.repository,
      'GO',
      cause: e,
    ),
  );

  setUp(() {
    expect(
      CrashReporter.current,
      same(CrashReporter.none),
      reason: 'a reporter leaked from another test',
    );
    reporter = _RecordingReporter();
    CrashReporter.install(reporter);
  });

  tearDown(() => CrashReporter.install(CrashReporter.none));

  Future<Result<T>> guard<T>(
    Future<T> Function() block, [
    List<ExceptionHandler> handlers = const [],
  ]) => processCall('ORD', 'GO', ExceptionLayer.repository, handlers, block);

  SinewException? errorOf(Result<Object?> result) =>
      result.fold((_) => null, (e) => e);

  group('processCall', () {
    test('success returns the value', () async {
      expect(await guard(() async => 42), const Result.success(42));
    });

    test('a lower-layer SinewException passes through unchanged', () async {
      const lower = NotFoundException(
        'ORD',
        ExceptionLayer.repository,
        'GET',
        message: ServerMessage('Gone.'),
      );
      final result = await guard<int>(() async => throw lower, [
        timeoutHandler,
      ]);
      expect(errorOf(result), same(lower));
      expect(errorOf(result)?.code, 'ORD-R-GET-NTF');
      expect(reporter.reports, isEmpty);
    });

    test('a matched error is transformed and not reported', () async {
      final result = await guard<int>(() async => throw StateError('timeout'), [
        timeoutHandler,
      ]);
      expect(errorOf(result), isA<RequestTimeOutException>());
      expect(errorOf(result)?.code, 'ORD-R-GO-RTO');
      expect(reporter.reports, isEmpty);
    });

    test('the first match wins', () async {
      final general = ExceptionHandler(
        (_) => true,
        (e) => UnexpectedException(
          'ORD',
          ExceptionLayer.repository,
          'GO',
          cause: e,
        ),
      );
      final result = await guard<int>(() async => throw StateError('timeout'), [
        timeoutHandler,
        general,
      ]);
      expect(errorOf(result), isA<RequestTimeOutException>());
    });

    test('an unmatched error becomes unexpected and is reported once, with its stack trace', () async {
      final bug = ArgumentError('bug');
      final result = await guard<int>(() async => throw bug, [timeoutHandler]);
      final error = errorOf(result);
      expect(error, isA<UnexpectedException>());
      expect(error?.code, 'ORD-R-GO-GEN');
      expect(error?.cause, same(bug));
      expect(reporter.reports, [same(error)]);
      expect(reporter.traces.single, isNotNull);
      expect(
        result.when(success: (_, _) => null, failure: (_, s) => s),
        isNotNull,
      );
    });

    test('a parse failure is reported once', () async {
      final handlers = [
        timeoutHandler,
        envelopeDataMissing('ORD', 'GO', ExceptionLayer.repository),
      ];
      final result = await guard<int>(
        () async => throw const EnvelopeDataMissing(),
        handlers,
      );
      final error = errorOf(result);
      expect(error, isA<ParseException>());
      expect(error?.code, 'ORD-R-GO-DF');
      expect(reporter.reports, [same(error)]);
    });

    test(
      'a TypeError inside the block becomes a reported failure, not a crash',
      () async {
        Object value = 1;
        final result = await guard(() async => value as String);
        expect(errorOf(result), isA<UnexpectedException>());
        expect(errorOf(result)?.cause, isA<TypeError>());
        expect(reporter.reports, hasLength(1));
      },
    );

    test('a handler that throws counts as unmatched', () async {
      final brokenTransform = ExceptionHandler(
        (_) => true,
        (_) => throw StateError('broken'),
      );
      final brokenMatches = ExceptionHandler(
        (_) => throw StateError('broken'),
        (_) => const RequestTimeOutException(
          'ORD',
          ExceptionLayer.repository,
          'GO',
        ),
      );
      final result = await guard<int>(() async => throw StateError('timeout'), [
        brokenTransform,
        brokenMatches,
        timeoutHandler,
      ]);
      expect(errorOf(result), isA<RequestTimeOutException>());
      expect(
        errorOf(
          await guard<int>(() async => throw StateError('x'), [
            brokenTransform,
          ]),
        ),
        isA<UnexpectedException>(),
      );
    });

    test('a reporter that throws does not break the guard', () async {
      CrashReporter.install(_ThrowingReporter());
      expect(
        errorOf(await guard<int>(() async => throw ArgumentError('bug'))),
        isA<UnexpectedException>(),
      );
    });

    test('a cancellation passes through and is never reported', () async {
      const cancel = CancelException('ORD', ExceptionLayer.repository, 'GO');
      final result = await guard<int>(() async => throw cancel);
      expect(errorOf(result), same(cancel));
      expect(reporter.reports, isEmpty);
    });
  });

  group('processUseCase', () {
    test('passes a domain exception through', () async {
      const domain = _OutOfStockException();
      final result = await processUseCase<int>(
        'ORD',
        'PO',
        () async => throw domain,
      );
      expect(errorOf(result), same(domain));
      expect(reporter.reports, isEmpty);
    });

    test('keeps the repository code from requireData', () async {
      const Result<int> repository = Result.failure(
        NotFoundException('ORD', ExceptionLayer.repository, 'GET'),
      );
      final result = await processUseCase(
        'ORD',
        'PO',
        () async => repository.requireData(),
      );
      expect(errorOf(result)?.code, 'ORD-R-GET-NTF');
    });

    test('turns a bug into a reported use-case failure', () async {
      final result = await processUseCase(
        'ORD',
        'PO',
        () async => <int>[].first,
      );
      final error = errorOf(result);
      expect(error, isA<UnexpectedException>());
      expect(error?.code, 'ORD-UC-PO-GEN');
      expect(reporter.reports, [same(error)]);
    });
  });

  test('install replaces the current reporter', () {
    final second = _RecordingReporter();
    CrashReporter.install(second);
    expect(CrashReporter.current, same(second));
  });
}
