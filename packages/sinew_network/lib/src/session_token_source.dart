import 'dart:async';

import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

import 'token_source.dart';

/// Where [SessionTokenSource] keeps the refresh token: the app adapts its
/// secure store in a few lines.
abstract interface class RefreshTokenStore {
  /// The stored refresh token, or `null` when there's none.
  Future<String?> read();

  /// Stores [token], replacing the previous one.
  Future<void> write(String token);

  /// Deletes the stored token.
  Future<void> delete();
}

/// The app's backend call that trades a refresh token for a new pair. It
/// must use a `Dio` **without** the auth interceptor, so a refresh never
/// refreshes itself. A thrown failure counts as [RefreshUnavailable].
typedef RefreshCall = Future<RefreshResult> Function(String refreshToken);

/// What the backend answered to a refresh.
sealed class RefreshResult {
  const RefreshResult();
}

/// A new pair. With rotating refresh tokens, [refresh] replaces the stored
/// one.
final class RefreshTokens extends RefreshResult {
  /// The pair.
  const RefreshTokens({required this.access, required this.refresh});

  /// The new access token.
  final String access;

  /// The new refresh token.
  final String refresh;
}

/// The backend refused the refresh token: the session is over.
final class RefreshRejected extends RefreshResult {
  /// The answer.
  const RefreshRejected();
}

/// The refresh couldn't be completed (offline, a timeout, a 5xx): the session
/// is kept.
final class RefreshUnavailable extends RefreshResult {
  /// The answer, with its [cause].
  const RefreshUnavailable(this.cause);

  /// Why the refresh couldn't be completed.
  final SinewException cause;
}

/// Sinew's ready [TokenSource]: the access token in memory, the refresh token
/// in a [RefreshTokenStore], and a refresh through a [RefreshCall].
///
/// A **session epoch** keeps a sign-out final. [clear] increments it, and a
/// refresh stores its tokens only if the epoch is the one it started in,
/// checked and written in one critical section. So a refresh that finishes
/// after sign-out stores nothing and returns [Rejected], whatever the order.
///
/// A refresh the backend rejects ends the session here, in the same critical
/// section, and only if it's still the session the refresh started in: a
/// refresh voided by sign-out, or by another user's sign-in, never touches
/// the new state.
final class SessionTokenSource implements TokenSource {
  /// Creates the source. `onSessionEnded` runs when a session ends: on
  /// [clear], and when the backend rejects the refresh token (or none is
  /// stored), which the app learns only here. Route to sign-in from it, and
  /// keep it idempotent.
  SessionTokenSource(this._store, this._call, {this._onSessionEnded});

  final RefreshTokenStore _store;
  final RefreshCall _call;
  final Future<void> Function()? _onSessionEnded;
  final _lock = _AsyncLock();
  int _epoch = 0;
  String? _access;

  @override
  String? accessToken() => _access;

  /// Starts a session after sign-in: stores [refreshToken] and holds
  /// [accessToken]. Voids any refresh still running.
  Future<void> start({
    required String accessToken,
    required String refreshToken,
  }) => _lock.run(() async {
    _epoch++;
    await _store.write(refreshToken);
    _access = accessToken;
  });

  @override
  Future<RefreshOutcome> refresh() async {
    final (started, refreshToken) = await _lock.run(
      () async => (_epoch, await _store.read()),
    );
    if (refreshToken == null) return _endIfStill(started);
    final result = await processCall(
      'AUTH',
      'REFRESH',
      ExceptionLayer.repository,
      const [],
      () => _call(refreshToken),
    );
    final RefreshResult answer;
    switch (result) {
      case Failure(:final error):
        return Unavailable(error);
      case Success(:final data):
        answer = data;
    }
    return switch (answer) {
      RefreshUnavailable(:final cause) => Unavailable(cause),
      RefreshRejected() => _endIfStill(started),
      RefreshTokens(:final access, :final refresh) => _lock.run(() async {
        if (_epoch != started) {
          return const Rejected(); // signed out or in meanwhile: store nothing
        }
        await _store.write(refresh);
        _access = access;
        return const Refreshed();
      }),
    };
  }

  /// The backend refused, or there's no refresh token: ends the session,
  /// unless the app already ended it or started another one since [started].
  Future<RefreshOutcome> _endIfStill(int started) async {
    final ended = await _lock.run(() async {
      if (_epoch != started) return false;
      await _drop();
      return true;
    });
    if (ended) await _onSessionEnded?.call();
    return const Rejected();
  }

  Future<void> _drop() async {
    _epoch++;
    _access = null;
    await _store.delete();
  }

  @override
  Future<void> clear() async {
    await _lock.run(_drop);
    await _onSessionEnded?.call();
  }
}

/// One critical section at a time, across `await`s: each waits for the one
/// before it.
final class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() section) {
    final result = _tail.then((_) => section());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
