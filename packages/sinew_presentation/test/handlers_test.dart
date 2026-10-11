import 'dart:async';

import 'package:sinew_presentation/sinew_presentation.dart';
import 'package:test/test.dart';

/// A simple page: one direct method, no event or action types.
final class _Counter extends StateEffectHandler<int, String> {
  _Counter() : super(0);

  void add(int by) {
    setState((count) => count + by);
    emitEffect('added $by');
  }
}

/// Maps `'+N'` to an action of N, `'skip'` to none, and records each action.
final class _Events extends EventActionHandler<int, String, int, String> {
  _Events() : super(0);

  final mapped = <String>[];
  final started = <int>[];
  final gates = <int, Completer<void>>{};

  @override
  int? mapEventToAction(String event) {
    mapped.add(event);
    return event.startsWith('+') ? int.parse(event.substring(1)) : null;
  }

  @override
  Future<void> onAction(int action) async {
    started.add(action);
    final gate = gates[action];
    if (gate != null) await gate.future;
    setState((count) => count + action);
    emitEffect('done $action');
  }
}

void main() {
  group('StateEffectHandler', () {
    test('setState updates the state and emits it', () async {
      final handler = _Counter();
      final states = <int>[];
      handler.states.listen(states.add);
      handler
        ..add(1)
        ..add(2);
      await pumpEventQueue();
      expect(handler.state, 3);
      expect(states, [1, 3]);
    });

    test('a state equal to the current one is not emitted', () async {
      final handler = _Counter();
      final states = <int>[];
      handler.states.listen(states.add);
      handler.add(0);
      await pumpEventQueue();
      expect(states, isEmpty);
    });

    test('emitEffect goes through the emitter: buffered, once', () async {
      final handler = _Counter()..add(1);
      final effects = <String>[];
      handler.effects.listen(effects.add);
      await pumpEventQueue();
      expect(effects, ['added 1']);
    });

    test('after dispose, setState and emitEffect do nothing', () async {
      final handler = _Counter();
      final effects = <String>[];
      var statesDone = false;
      var effectsDone = false;
      handler.states.listen((_) {}, onDone: () => statesDone = true);
      handler.effects.listen(effects.add, onDone: () => effectsDone = true);
      handler
        ..dispose()
        ..add(1)
        ..dispose();
      await pumpEventQueue();
      expect(handler.state, 0);
      expect(effects, isEmpty);
      expect(statesDone, isTrue);
      expect(effectsDone, isTrue);
    });
  });

  group('EventActionHandler', () {
    test('an event maps to an action, which runs', () async {
      final handler = _Events();
      final effects = <String>[];
      handler.effects.listen(effects.add);
      handler.onEvent('+2');
      await pumpEventQueue();
      expect(handler.started, [2]);
      expect(handler.state, 2);
      expect(effects, ['done 2']);
    });

    test('a null action runs nothing', () async {
      final handler = _Events()..onEvent('skip');
      await pumpEventQueue();
      expect(handler.mapped, ['skip']);
      expect(handler.started, isEmpty);
      expect(handler.state, 0);
    });

    test('events after dispose are ignored: not even mapped', () async {
      final handler = _Events()
        ..dispose()
        ..onEvent('+1');
      await pumpEventQueue();
      expect(handler.mapped, isEmpty);
      expect(handler.started, isEmpty);
    });

    test('actions run concurrently: onEvent does not await one', () async {
      final handler = _Events();
      final slow = handler.gates[1] = Completer<void>();
      handler
        ..onEvent('+1')
        ..onEvent('+2');
      await pumpEventQueue();
      expect(handler.started, [1, 2]);
      expect(handler.state, 2); // the second finished first

      slow.complete();
      await pumpEventQueue();
      expect(handler.state, 3);
    });

    test('an action finishing after dispose touches nothing', () async {
      final handler = _Events();
      final effects = <String>[];
      handler.effects.listen(effects.add);
      final gate = handler.gates[1] = Completer<void>();
      handler.onEvent('+1');
      await pumpEventQueue();
      handler.dispose();
      gate.complete();
      await pumpEventQueue();
      expect(handler.state, 0);
      expect(effects, isEmpty);
    });

    test("a throw in onAction reaches the zone's error handler", () async {
      final errors = <Object>[];
      final handler = _Throwing();
      runZonedGuarded(() => handler.onEvent('go'), (e, _) => errors.add(e));
      await pumpEventQueue();
      expect(errors, [isA<StateError>()]);
    });
  });
}

final class _Throwing extends EventActionHandler<int, String, String, Never> {
  _Throwing() : super(0);

  @override
  String? mapEventToAction(String event) => event;

  @override
  Future<void> onAction(String action) async => throw StateError('a bug');
}
