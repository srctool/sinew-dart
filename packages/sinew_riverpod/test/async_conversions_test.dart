// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_riverpod/sinew_riverpod.dart';

const _offline = NoInternetConnectionException(
  'ORD',
  ExceptionLayer.repository,
  'GO',
);
final _trace = StackTrace.current;

// Riverpod attaches previous values only internally (copyWithPrevious), so
// the tests build those states the same way it does.
AsyncValue<int> _refreshing(AsyncValue<int> previous) =>
    const AsyncLoading<int>().copyWithPrevious(previous);

AsyncValue<int> _reloading(AsyncValue<int> previous) =>
    const AsyncLoading<int>().copyWithPrevious(previous, isRefresh: false);

void main() {
  group('toViewState', () {
    test('AsyncLoading → Loading', () {
      expect(
        const AsyncLoading<int>().toViewState('ORD', 'GO'),
        const Loading<int>(),
      );
    });

    test('a refresh (AsyncData, loading) → Loading(previous)', () {
      final refresh = _refreshing(const AsyncData(1));
      expect(refresh, isA<AsyncData<int>>());
      expect(refresh.toViewState('ORD', 'GO'), const Loading(1));
    });

    test('a reload (AsyncLoading with a value) → Loading(previous)', () {
      final reload = _reloading(const AsyncData(1));
      expect(reload, isA<AsyncLoading<int>>());
      expect(reload.toViewState('ORD', 'GO'), const Loading(1));
    });

    test('a retry (AsyncError, loading) → Loading', () {
      final retry = _refreshing(AsyncError<int>(_offline, _trace));
      expect(retry, isA<AsyncError<int>>());
      expect(retry.toViewState('ORD', 'GO'), const Loading<int>());
    });

    test('AsyncData → Done', () {
      expect(const AsyncData(1).toViewState('ORD', 'GO'), const Done(1));
    });

    test('AsyncError with a SinewException → Failed with it', () {
      final view = AsyncError<int>(_offline, _trace).toViewState('ORD', 'GO');
      expect(view, isA<Failed<int>>());
      view as Failed<int>;
      expect(identical(view.error, _offline), isTrue);
      expect(view.stackTrace, _trace);
      expect(view.data, isNull);
    });

    test('AsyncError with a previous value → Failed keeps it', () {
      final error = AsyncError<int>(
        _offline,
        _trace,
      ).copyWithPrevious(const AsyncData(1));
      expect((error.toViewState('ORD', 'GO') as Failed<int>).data, 1);
    });

    test('AsyncError with any other error → Failed(UnexpectedException)', () {
      final cause = StateError('a bug');
      final view = AsyncError<int>(
        cause,
        _trace,
      ).toViewState('ORD', 'LOAD') as Failed<int>;
      expect(view.error, isA<UnexpectedException>());
      expect(view.error.code, 'ORD-VM-LOAD-GEN');
      expect(view.error.cause, same(cause));
      expect(view.stackTrace, _trace);
    });
  });

  group('toAsyncValue', () {
    test('Loading → AsyncLoading', () {
      expect(const Loading<int>().toAsyncValue(), const AsyncLoading<int>());
    });

    test('Loading(previous) → AsyncLoading, the previous data dropped', () {
      final value = const Loading(1).toAsyncValue();
      expect(value, isA<AsyncLoading<int>>());
      expect(value.hasValue, isFalse);
    });

    test('Done → AsyncData', () {
      expect(const Done(1).toAsyncValue(), const AsyncData(1));
    });

    test('Failed → AsyncError with its error and stack trace', () {
      final value = Failed<int>(
        _offline,
        data: 1,
        stackTrace: _trace,
      ).toAsyncValue();
      expect(value, isA<AsyncError<int>>());
      expect(value.error, same(_offline));
      expect(value.stackTrace, _trace);
      expect(value.hasValue, isFalse);
    });

    test('Failed without a stack trace → an empty one', () {
      expect(
        const Failed<int>(_offline).toAsyncValue().stackTrace,
        StackTrace.empty,
      );
    });
  });
}
