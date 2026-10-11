import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:sinew_riverpod/sinew_riverpod.dart';

/// Maps `'+N'` to an action of N and `'skip'` to none; each action adds N
/// to the count, then emits `'added N'`. A gated action waits for its gate.
class Counter extends Notifier<int>
    with
        StateEffectNotifier<int, String>,
        EventActionNotifier<int, String, int, String> {
  final mapped = <String>[];
  final gates = <int, Completer<void>>{};
  var builds = 0;

  @override
  int build() {
    builds++;
    return 0;
  }

  @override
  int? mapEventToAction(String event) {
    mapped.add(event);
    return event.startsWith('+') ? int.parse(event.substring(1)) : null;
  }

  @override
  Future<void> onAction(int action) async {
    final gate = gates[action];
    if (gate != null) await gate.future;
    setState((count) => count + action);
    emitEffect('added $action');
  }

  void rebuild() => ref.invalidateSelf();
}

final counter = NotifierProvider<Counter, int>(Counter.new);
final autoCounter = NotifierProvider.autoDispose<Counter, int>(Counter.new);

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('events in, states out, effects once', () async {
    final states = <int>[];
    container.listen(counter, (_, next) => states.add(next));
    final notifier = container.read(counter.notifier);
    final effects = <String>[];
    notifier.effects.listen(effects.add);

    notifier
      ..onEvent('+1')
      ..onEvent('+2');
    await pumpEventQueue();
    expect(states, [1, 3]);
    expect(effects, ['added 1', 'added 2']);
  });

  test('a null action runs nothing', () async {
    final notifier = container.read(counter.notifier)..onEvent('skip');
    await pumpEventQueue();
    expect(notifier.mapped, ['skip']);
    expect(container.read(counter), 0);
  });

  test('an effect before the page listens is delivered once', () async {
    final notifier = container.read(counter.notifier)..onEvent('+1');
    await pumpEventQueue();
    final first = <String>[];
    final subscription = notifier.effects.listen(first.add);
    await pumpEventQueue();
    await subscription.cancel();
    final second = <String>[];
    notifier.effects.listen(second.add);
    await pumpEventQueue();
    expect(first, ['added 1']);
    expect(second, isEmpty);
  });

  test('effects still arrive after ref.invalidateSelf()', () async {
    container.listen(counter, (_, _) {});
    final notifier = container.read(counter.notifier);
    final effects = <String>[];
    var done = false;
    notifier.effects.listen(effects.add, onDone: () => done = true);

    notifier.rebuild();
    await pumpEventQueue();
    container.read(counter);
    expect(notifier.builds, 2);
    expect(identical(container.read(counter.notifier), notifier), isTrue);

    notifier.onEvent('+1');
    await pumpEventQueue();
    expect(effects, ['added 1']);
    expect(done, isFalse);
    expect(container.read(counter), 1);
  });

  group('the emitter is disposed with the provider', () {
    test('on container.dispose()', () async {
      final own = ProviderContainer();
      final notifier = own.read(counter.notifier);
      var done = false;
      notifier.effects.listen((_) {}, onDone: () => done = true);
      own.dispose();
      await pumpEventQueue();
      expect(done, isTrue);
    });

    test('on auto-dispose', () async {
      final subscription = container.listen(autoCounter, (_, _) {});
      final notifier = container.read(autoCounter.notifier);
      var done = false;
      notifier.effects.listen((_) {}, onDone: () => done = true);
      subscription.close();
      await pumpEventQueue();
      expect(done, isTrue);
    });
  });

  test('after dispose, events are ignored and late work is inert', () async {
    final own = ProviderContainer();
    final notifier = own.read(counter.notifier);
    final effects = <String>[];
    notifier.effects.listen(effects.add);
    final gate = notifier.gates[1] = Completer<void>();
    notifier.onEvent('+1');
    await pumpEventQueue();

    own.dispose();
    gate.complete(); // setState and emitEffect after dispose: no throw
    notifier.onEvent('+2');
    await pumpEventQueue();
    expect(notifier.mapped, ['+1']);
    expect(effects, isEmpty);
  });

  test('actions run concurrently: onEvent does not await one', () async {
    final notifier = container.read(counter.notifier);
    final slow = notifier.gates[1] = Completer<void>();
    notifier
      ..onEvent('+1')
      ..onEvent('+2');
    await pumpEventQueue();
    expect(container.read(counter), 2); // the second finished first
    slow.complete();
    await pumpEventQueue();
    expect(container.read(counter), 3);
  });
}
