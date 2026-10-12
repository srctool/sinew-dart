import 'package:sinew_models/sinew_models.dart';

/// Where a client's tokens live and how they refresh. Sinew's
/// `SessionTokenSource` is the ready implementation; an app that writes its
/// own must keep the [clear] contract.
abstract interface class TokenSource {
  /// The current access token, held in memory, or `null` when signed out.
  String? accessToken();

  /// Gets a new token pair from the backend and stores it. Called by the auth
  /// layer once for any number of concurrent 401s. The call must not go
  /// through a client with the auth layer, so a refresh never refreshes
  /// itself. On a rejection, the source ends the session itself (see
  /// [Rejected]).
  Future<RefreshOutcome> refresh();

  /// The session ended: drop the tokens, void any refresh still running, and
  /// tell the app's session service.
  ///
  /// Contract: once [clear] completes, a refresh that started before it must
  /// not store its tokens, and must return [Rejected]. Otherwise a refresh
  /// finishing after sign-out would silently sign the user, or the next user,
  /// back in. Check and write under one lock, with a counter [clear]
  /// increments.
  Future<void> clear();
}

/// What a refresh attempt concluded.
sealed class RefreshOutcome {
  const RefreshOutcome();
}

/// New tokens are stored: replay the waiting requests once.
final class Refreshed extends RefreshOutcome {
  /// The outcome.
  const Refreshed();

  @override
  bool operator ==(Object other) => other is Refreshed;

  @override
  int get hashCode => (Refreshed).hashCode;
}

/// The backend refused the refresh token, or the session ended while
/// refreshing. Waiting requests fail with `UnauthorizedException`.
///
/// The source ends the session itself, as [TokenSource.clear] would, but only
/// if it's still the session the refresh started in: the auth layer never
/// clears on this outcome, because a refresh voided by another user's sign-in
/// must not sign them out.
final class Rejected extends RefreshOutcome {
  /// The outcome.
  const Rejected();

  @override
  bool operator ==(Object other) => other is Rejected;

  @override
  int get hashCode => (Rejected).hashCode;
}

/// The refresh couldn't be completed: offline, a timeout, a 5xx. The session
/// is **kept**, and waiting requests fail with [cause], so the page shows a
/// retryable error instead of signing the user out.
final class Unavailable extends RefreshOutcome {
  /// The outcome, with its [cause].
  const Unavailable(this.cause);

  /// Why the refresh couldn't be completed.
  final SinewException cause;

  @override
  bool operator ==(Object other) =>
      other is Unavailable && identical(other.cause, cause);

  @override
  int get hashCode => identityHashCode(cause);
}
