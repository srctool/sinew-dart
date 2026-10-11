import 'dart:async';

import 'package:meta/meta.dart';

import 'effect_emitter.dart';

/// A page with one or two actions: state and effects, with direct methods
/// (`submit()`, `resend()`) and no event or action types. A page that grows a
/// third intent becomes an [EventActionHandler], a change of superclass.
///
/// State is one immutable value changed only through [setState]; one-time
/// outcomes go through [emitEffect]. Never trigger a side effect from a state
/// change. After [dispose], [setState] and [emitEffect] do nothing, so a late
/// `await` in running work can't touch a disposed handler.
abstract class StateEffectHandler<S, F> {
  /// Creates the handler with its [initial] state.
  StateEffectHandler(S initial) : _state = initial;

  S _state;
  final _states = StreamController<S>.broadcast();
  final _emitter = EffectEmitter<F>();
  bool _disposed = false;

  /// The page's current state.
  S get state => _state;

  /// Each new state, as it's set. A state equal to the current one isn't
  /// emitted. Done after [dispose].
  Stream<S> get states => _states.stream;

  /// The page's one-time effects, each delivered once, to one listener.
  Stream<F> get effects => _emitter.stream;

  /// Whether [dispose] was called.
  @protected
  bool get isDisposed => _disposed;

  /// Replaces the state with [reduce] applied to it. Does nothing after
  /// [dispose].
  @protected
  void setState(S Function(S state) reduce) {
    if (_disposed) return;
    final next = reduce(_state);
    if (next == _state) return;
    _state = next;
    _states.add(next);
  }

  /// Emits a one-time [effect]. Does nothing after [dispose].
  @protected
  void emitEffect(F effect) => _emitter.emit(effect);

  /// Closes [states] and [effects]. Later calls do nothing.
  @mustCallSuper
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _emitter.dispose();
    _states.close();
  }
}

/// A page with three or more intents, or intents that mean the same work:
/// events in, state and effects out.
///
/// The page only sends events. [mapEventToAction] is pure: it reads the state
/// and returns the work to run, or `null` for none right now, so every "should
/// this run" decision is in one testable function. [onAction] does the work
/// and isn't awaited by [onEvent], so actions may run concurrently; work that
/// must not overlap is guarded in [mapEventToAction] by reading state. A throw
/// in [onAction] is a bug: it reaches the zone's error handler.
abstract class EventActionHandler<S, E, A, F> extends StateEffectHandler<S, F> {
  /// Creates the handler with its [initial] state.
  EventActionHandler(super.initial);

  /// Reports an event from the page. Ignored after [dispose]: no action runs
  /// and no state changes.
  void onEvent(E event) {
    if (isDisposed) return;
    final action = mapEventToAction(event);
    if (action != null) unawaited(onAction(action));
  }

  /// The action [event] means right now, or `null` for none. Pure: it reads
  /// [state] and changes no state.
  @protected
  A? mapEventToAction(E event);

  /// Does the work for [action].
  @protected
  Future<void> onAction(A action);
}
