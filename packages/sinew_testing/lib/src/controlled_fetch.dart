import 'dart:async';

import 'package:sinew_models/sinew_models.dart';
import 'package:test_api/scaffolding.dart';

/// One call to a [ControlledFetch]: the page, cursor or last ID it asked for,
/// and its query.
final class FetchCall<T> {
  FetchCall._(this.key, this.query);

  /// The page number, cursor or last ID the call asked for.
  final Object? key;

  /// The call's query.
  final String query;

  final _answer = Completer<Result<PagingDomain<T>>>();

  /// Whether the test answered this call.
  bool get isAnswered => _answer.isCompleted;
}

/// A paging `fetch` the test completes by hand, so every race (a late
/// response, a refresh during `more`, a search during a load) can be written
/// in order.
///
/// Each call returns a future that completes when the test answers it with
/// [complete], [succeed] or [fail], by its index in call order. Dart futures
/// can't be cancelled from outside, so a superseded call stays pending until
/// the test answers it, which is also how a test proves a late answer is
/// dropped. Create it with [controlledFetch] inside a test, so a call left
/// pending fails the test.
///
/// ```dart
/// final fetch = controlledFetch<Order>();
/// final pager = Pager<Order>.offset(fetch.call);
/// ```
final class ControlledFetch<T> {
  final _calls = <FetchCall<T>>[];

  /// Every call so far, in order.
  List<FetchCall<T>> get calls => List.unmodifiable(_calls);

  /// The fetch function: completes when the test answers this call.
  Future<Result<PagingDomain<T>>> call(Object? key, String query) {
    final call = FetchCall<T>._(key, query);
    _calls.add(call);
    return call._answer.future;
  }

  /// Answers call number [call] with [result].
  void complete(int call, Result<PagingDomain<T>> result) {
    if (call < 0 || call >= _calls.length) {
      throw StateError(
        "There's no call $call yet; ${_calls.length} call(s) were made",
      );
    }
    final answer = _calls[call]._answer;
    if (answer.isCompleted) throw StateError('Call $call was already answered');
    answer.complete(result);
  }

  /// Answers call number [call] with a page of [items].
  void succeed(
    int call,
    List<T> items, {
    PagingMetaDomain meta = const PagingMetaDomain(),
  }) => complete(call, Result.success(PagingDomain(items: items, meta: meta)));

  /// Answers call number [call] with [error].
  void fail(int call, SinewException error) =>
      complete(call, Result.failure(error));

  /// Fails the test if a call is still waiting for an answer.
  void assertAllCompleted() {
    final pending = [
      for (var i = 0; i < _calls.length; i++)
        if (!_calls[i].isAnswered) i,
    ];
    if (pending.isNotEmpty) {
      throw StateError('Calls $pending were never answered');
    }
  }
}

/// A [ControlledFetch] whose [ControlledFetch.assertAllCompleted] runs when
/// the test ends, so a race left unanswered fails the test instead of passing
/// silently. Call it inside a test or a `setUp`.
ControlledFetch<T> controlledFetch<T>() {
  final fetch = ControlledFetch<T>();
  addTearDown(fetch.assertAllCompleted);
  return fetch;
}
