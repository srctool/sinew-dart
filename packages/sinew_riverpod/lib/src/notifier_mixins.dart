import 'dart:async';

import 'package:meta/meta.dart';
import 'package:riverpod/misc.dart' show WhenComplete;
import 'package:riverpod/riverpod.dart';
import 'package:sinew_presentation/sinew_presentation.dart';

/// `StateEffectHandler` for a Riverpod `Notifier`: state is the notifier's
/// own, and one-time effects go through an [EffectEmitter].
///
/// Mixed into a `Notifier<S>` or a generated `_$X` class; both are
/// `AnyNotifier<S, S>`, the base Riverpod names for notifier mixins. An
/// `AsyncNotifier` keeps its `AsyncValue` and converts with `toViewState`.
///
/// ```dart
/// @riverpod
/// class OrderList extends _$OrderList
///     with StateEffectNotifier<OrderListState, OrderListEffect> { … }
/// ```
///
/// The emitter lives as long as the notifier: a rebuild (`ref.invalidateSelf()`
/// or a watched provider changing) keeps it, so the page's subscription keeps
/// receiving effects, and it's disposed only when the provider is. After that,
/// [setState] and [emitEffect] do nothing, so a late `await` in running work
/// can't touch a disposed notifier.
mixin StateEffectNotifier<S, F> on AnyNotifier<S, S> {
  final _emitter = EffectEmitter<F>();

  /// The page's one-time effects, each delivered once, to one listener. The
  /// same stream across rebuilds.
  Stream<F> get effects => _emitter.stream;

  @override
  WhenComplete runBuild() {
    // onDispose also runs before a rebuild; only a real dispose unmounts.
    ref.onDispose(() {
      if (!ref.mounted) _emitter.dispose();
    });
    return super.runBuild();
  }

  /// Replaces the state with [reduce] applied to it. Does nothing once the
  /// provider is disposed.
  @protected
  void setState(S Function(S state) reduce) {
    if (!ref.mounted) return;
    state = reduce(state);
  }

  /// Emits a one-time [effect]. Does nothing once the provider is disposed.
  @protected
  void emitEffect(F effect) => _emitter.emit(effect);
}

/// `EventActionHandler` for a Riverpod `Notifier`: events in, state and
/// effects out. Mixed in after [StateEffectNotifier], which it builds on.
///
/// ```dart
/// class OrderList extends _$OrderList
///     with
///         StateEffectNotifier<OrderListState, OrderListEffect>,
///         EventActionNotifier<OrderListState, OrderListEvent, OrderListAction, OrderListEffect> { … }
/// ```
///
/// [mapEventToAction] is pure: it reads the state and returns the work to
/// run, or `null` for none right now. [onAction] isn't awaited by [onEvent],
/// so actions may run concurrently; work that must not overlap is guarded in
/// [mapEventToAction] by reading state. A throw in [onAction] is a bug: it
/// reaches the zone's error handler.
mixin EventActionNotifier<S, E, A, F> on StateEffectNotifier<S, F> {
  /// Reports an event from the page. Ignored once the provider is disposed:
  /// no action runs and no state changes.
  void onEvent(E event) {
    if (!ref.mounted) return;
    final action = mapEventToAction(event);
    if (action != null) unawaited(onAction(action));
  }

  /// The action [event] means right now, or `null` for none. Pure: it reads
  /// `state` and changes no state.
  @protected
  A? mapEventToAction(E event);

  /// Does the work for [action].
  @protected
  Future<void> onAction(A action);
}
