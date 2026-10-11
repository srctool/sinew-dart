import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_testing/sinew_testing.dart';

void main() {
  test('a call waits until the test answers it', () async {
    final fetch = ControlledFetch<String>();
    var done = false;
    final result = fetch(1, 'q').then((r) {
      done = true;
      return r;
    });
    await pumpEventQueue();
    expect(fetch.calls.single.key, 1);
    expect(fetch.calls.single.query, 'q');
    expect(done, isFalse);
    fetch.succeed(0, ['a']);
    expect(await result, const Result.success(PagingDomain(items: ['a'])));
  });

  test('calls are answered by index, in any order', () async {
    final fetch = ControlledFetch<String>();
    final first = fetch(1, '');
    final second = fetch(2, '');
    const offline = NoInternetConnectionException(
      'ORD',
      ExceptionLayer.repository,
      'GO',
    );
    fetch.fail(1, offline);
    fetch.succeed(0, ['a']);
    expect(await second, const Result<PagingDomain<String>>.failure(offline));
    expect(await first, const Result.success(PagingDomain(items: ['a'])));
  });

  test('a pending call fails the test', () {
    final fetch = ControlledFetch<String>();
    fetch(1, '');
    expect(fetch.assertAllCompleted, throwsStateError);
    fetch.succeed(0, []);
    fetch.assertAllCompleted();
  });

  test('answering twice, or a call not made yet, is an error', () {
    final fetch = ControlledFetch<String>();
    expect(() => fetch.succeed(0, []), throwsStateError);
    fetch(1, '');
    fetch.succeed(0, []);
    expect(() => fetch.succeed(0, []), throwsStateError);
  });
}
