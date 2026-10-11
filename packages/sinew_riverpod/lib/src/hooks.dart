import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Sends [event] to [onEvent] once per page instance, in a microtask after
/// the first build: Riverpod forbids changing a provider during build. A
/// rebuild doesn't send it again, and nothing is sent if the page is gone by
/// then.
void useOnOpened<E>(void Function(E event) onEvent, E event) {
  final context = useContext();
  useEffect(() {
    scheduleMicrotask(() {
      // Defensive: a page unmounted within its first microtask.
      if (context.mounted) onEvent(event);
    });
    return null;
  }, const []);
}

/// Listens to [effects] while the page is mounted and calls [onEffect] for
/// each one with the page's context.
///
/// Subscribes once per stream (a notifier's `effects` is the same stream
/// across rebuilds) and cancels on unmount, so an effect emitted while the
/// page is away waits in the notifier's buffer for the next page. The latest
/// [onEffect] is always the one called.
void useEffects<F>(
  Stream<F> effects,
  void Function(BuildContext context, F effect) onEffect,
) {
  final context = useContext();
  final latest = useRef(onEffect)..value = onEffect;
  useEffect(() {
    final subscription = effects.listen((effect) {
      if (context.mounted) latest.value(context, effect);
    });
    return subscription.cancel;
  }, [effects]);
}
