import 'dart:async';

/// One-time outcomes for a page: a snackbar, a dialog, a navigation callback.
/// Not state, because each must happen once and must not replay on rebuild.
///
/// An effect emitted while nobody listens waits in a buffer and goes to the
/// next listener, exactly once, so a snackbar emitted while the page
/// re-subscribes is neither lost nor shown twice. A broadcast stream would
/// drop it.
///
/// [stream] accepts one listener at a time; a second `listen` while one is
/// active throws, as with any single-subscription stream. After the listener
/// cancels, a new one may listen and gets only what it hasn't been given. An
/// effect is handed over only while the listener is active and not paused,
/// so cancelling or pausing never loses one.
final class EffectEmitter<F> {
  /// Creates an emitter with an empty buffer.
  EffectEmitter();

  final _buffer = <F>[];
  StreamController<F>? _controller;
  bool _disposed = false;
  bool _drainScheduled = false;

  /// The effects, each delivered to one listener, once. Done after [dispose].
  late final Stream<F> stream = _EffectStream(this);

  /// Emits [effect]. Does nothing after [dispose].
  void emit(F effect) {
    if (_disposed) return;
    _buffer.add(effect);
    _scheduleDrain();
  }

  /// Drops the buffer and closes [stream]. Later calls do nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _buffer.clear();
    _controller?.close();
  }

  StreamSubscription<F> _listen(
    void Function(F effect)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_controller != null) {
      throw StateError('EffectEmitter.stream already has a listener');
    }
    // Synchronous, so an effect added below reaches the listener at once and
    // never sits in a subscription that might be cancelled before delivery.
    final controller = StreamController<F>(sync: true);
    controller
      ..onResume = _scheduleDrain
      ..onCancel = () {
        if (identical(_controller, controller)) _controller = null;
      };
    final subscription = controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    if (_disposed) {
      controller.close();
    } else {
      _controller = controller;
      _scheduleDrain();
    }
    return subscription;
  }

  // Delivery runs in a microtask: never inside `listen`, `resume` or a
  // listener's own callback, where a synchronous controller can't deliver.
  void _scheduleDrain() {
    if (_drainScheduled || _buffer.isEmpty) return;
    _drainScheduled = true;
    scheduleMicrotask(_drain);
  }

  void _drain() {
    _drainScheduled = false;
    while (_buffer.isNotEmpty) {
      final controller = _controller;
      if (controller == null ||
          !controller.hasListener ||
          controller.isPaused) {
        return;
      }
      controller.add(_buffer.removeAt(0));
    }
  }
}

final class _EffectStream<F> extends Stream<F> {
  _EffectStream(this._emitter);

  final EffectEmitter<F> _emitter;

  @override
  StreamSubscription<F> listen(
    void Function(F event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _emitter._listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
