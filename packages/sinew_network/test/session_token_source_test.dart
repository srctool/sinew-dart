import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_network/sinew_network.dart';

import 'support/memory_store.dart';

const offline = NoInternetConnectionException(
  'AUTH',
  ExceptionLayer.repository,
  'REFRESH',
);

void main() {
  Never notCalled(String _) => throw StateError('not called');

  test('start holds the access token and stores the refresh token', () async {
    final store = MemoryStore();
    final tokens = SessionTokenSource(store, notCalled);
    await tokens.start(accessToken: 'a-1', refreshToken: 'r-1');
    expect(tokens.accessToken(), 'a-1');
    expect(store.token, 'r-1');
  });

  test('a refresh stores the new pair', () async {
    final store = MemoryStore('r-1');
    final asked = <String>[];
    final tokens = SessionTokenSource(store, (t) async {
      asked.add(t);
      return const RefreshTokens(access: 'a-2', refresh: 'r-2');
    });
    expect(await tokens.refresh(), const Refreshed());
    expect(asked, ['r-1']);
    expect(tokens.accessToken(), 'a-2');
    expect(store.token, 'r-2');
  });

  test('an unavailable backend keeps the session', () async {
    final store = MemoryStore('r-1');
    final tokens = SessionTokenSource(
      store,
      (_) async => const RefreshUnavailable(offline),
    );
    expect(await tokens.refresh(), const Unavailable(offline));
    expect(store.token, 'r-1');
  });

  test('a thrown failure is Unavailable and keeps the session', () async {
    final store = MemoryStore('r-1');
    final outcome = await SessionTokenSource(
      store,
      (_) async => throw StateError('socket closed'),
    ).refresh();
    final cause = (outcome as Unavailable).cause;
    expect(cause, isA<UnexpectedException>());
    expect(cause.code, 'AUTH-R-REFRESH-GEN');
    expect(store.token, 'r-1');

    final thrown = await SessionTokenSource(
      store,
      (_) async => throw offline,
    ).refresh();
    expect(
      identical((thrown as Unavailable).cause, offline),
      isTrue,
    ); // a SinewException passes through
  });

  test('a rejected refresh ends the session once', () async {
    final store = MemoryStore('r-1');
    var ended = 0;
    final tokens = SessionTokenSource(
      store,
      (_) async => const RefreshRejected(),
      onSessionEnded: () async => ended++,
    );
    expect(await tokens.refresh(), const Rejected());
    expect(store.token, isNull);
    expect(ended, 1);
  });

  test(
    'no stored refresh token ends the session without asking the backend',
    () async {
      var ended = 0;
      final tokens = SessionTokenSource(
        MemoryStore(),
        notCalled,
        onSessionEnded: () async => ended++,
      );
      expect(await tokens.refresh(), const Rejected());
      expect(ended, 1);
    },
  );

  test('clear drops the tokens and ends the session', () async {
    final store = MemoryStore();
    var ended = 0;
    final tokens = SessionTokenSource(
      store,
      notCalled,
      onSessionEnded: () async => ended++,
    );
    await tokens.start(accessToken: 'a-1', refreshToken: 'r-1');
    await tokens.clear();
    expect(tokens.accessToken(), isNull);
    expect(store.token, isNull);
    expect(ended, 1);
  });

  group('every ordering of refresh and clear leaves no token after clear', () {
    test('clear while the backend answers', () async {
      final store = MemoryStore('r-1');
      final answer = Completer<RefreshResult>();
      final tokens = SessionTokenSource(store, (_) => answer.future);
      final refresh = tokens.refresh();
      await pumpEventQueue();
      await tokens.clear();
      answer.complete(const RefreshTokens(access: 'a-2', refresh: 'r-2'));
      expect(await refresh, const Rejected());
      expect(tokens.accessToken(), isNull);
      expect(store.token, isNull);
    });

    test('clear before the refresh reads the store', () async {
      final store = MemoryStore('r-1');
      final tokens = SessionTokenSource(
        store,
        (_) async => const RefreshTokens(access: 'a-2', refresh: 'r-2'),
      );
      final cleared = tokens.clear(); // takes the lock first
      final refresh = tokens.refresh();
      await cleared;
      expect(await refresh, const Rejected()); // nothing left to refresh with
      expect(tokens.accessToken(), isNull);
      expect(store.token, isNull);
    });

    for (final clearFirst in [true, false]) {
      test(
        'clear racing the final write (clear queued ${clearFirst ? 'before' : 'after'} the answer)',
        () async {
          final store = MemoryStore('r-1');
          final answer = Completer<RefreshResult>();
          final tokens = SessionTokenSource(store, (_) => answer.future);
          final refresh = tokens.refresh();
          await pumpEventQueue();
          Future<void> cleared;
          if (clearFirst) {
            cleared = tokens.clear();
            answer.complete(const RefreshTokens(access: 'a-2', refresh: 'r-2'));
          } else {
            answer.complete(const RefreshTokens(access: 'a-2', refresh: 'r-2'));
            cleared = tokens.clear();
          }
          await refresh;
          await cleared;
          expect(tokens.accessToken(), isNull);
          expect(store.token, isNull);
        },
      );
    }

    test('clear after the refresh finished', () async {
      final store = MemoryStore('r-1');
      final tokens = SessionTokenSource(
        store,
        (_) async => const RefreshTokens(access: 'a-2', refresh: 'r-2'),
      );
      await tokens.refresh();
      await tokens.clear();
      expect(tokens.accessToken(), isNull);
      expect(store.token, isNull);
    });

    test('a clear that waits for a slow store write still wins', () async {
      final gate = Completer<void>();
      final store = _SlowWriteStore('r-1', gate.future);
      final tokens = SessionTokenSource(
        store,
        (_) async => const RefreshTokens(access: 'a-2', refresh: 'r-2'),
      );
      final refresh = tokens.refresh();
      await pumpEventQueue(); // the refresh holds the lock, writing
      final cleared = tokens.clear(); // queued behind the write
      gate.complete();
      await refresh;
      await cleared;
      expect(tokens.accessToken(), isNull);
      expect(store.token, isNull);
    });
  });

  test('a new session voids a refresh from the previous one', () async {
    final store = MemoryStore('r-1');
    final answer = Completer<RefreshResult>();
    var ended = 0;
    final tokens = SessionTokenSource(
      store,
      (_) => answer.future,
      onSessionEnded: () async => ended++,
    );
    final refresh = tokens.refresh();
    await pumpEventQueue();
    await tokens.start(
      accessToken: 'b-1',
      refreshToken: 's-1',
    ); // another user signs in meanwhile
    answer.complete(const RefreshTokens(access: 'a-2', refresh: 'r-2'));
    expect(await refresh, const Rejected());
    expect(tokens.accessToken(), 'b-1');
    expect(store.token, 's-1');
    expect(ended, 0);
  });

  test(
    'a rejection arriving after another user signed in leaves their session',
    () async {
      final store = MemoryStore('r-1');
      final answer = Completer<RefreshResult>();
      var ended = 0;
      final tokens = SessionTokenSource(
        store,
        (_) => answer.future,
        onSessionEnded: () async => ended++,
      );
      final refresh = tokens.refresh();
      await pumpEventQueue();
      await tokens.start(accessToken: 'b-1', refreshToken: 's-1');
      answer.complete(const RefreshRejected());
      expect(await refresh, const Rejected());
      expect(tokens.accessToken(), 'b-1');
      expect(store.token, 's-1');
      expect(ended, 0);
    },
  );
}

/// A store whose write waits for [gate], to hold the lock mid-write.
final class _SlowWriteStore extends MemoryStore {
  _SlowWriteStore(super.token, this.gate);

  final Future<void> gate;

  @override
  Future<void> write(String token) async {
    await gate;
    await super.write(token);
  }
}
