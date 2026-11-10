// ignore_for_file: avoid_print

import 'package:sinew_presentation/sinew_presentation.dart';

/// The state a page renders.
final class CounterState {
  const CounterState(this.count);

  final int count;
}

/// A one-time reaction: never state, so a rebuild can't repeat it.
final class ReachedTen {
  const ReachedTen();
}

/// A page with one intent: state in, state and effects out.
final class Counter extends StateEffectHandler<CounterState, ReachedTen> {
  Counter() : super(const CounterState(0));

  void increment() {
    setState((state) => CounterState(state.count + 1));
    if (state.count == 10) emitEffect(const ReachedTen());
  }
}

Future<void> main() async {
  final counter = Counter();
  counter.effects.listen((effect) => print('effect: the counter reached ten'));
  counter.states.listen((state) => print('count: ${state.count}'));

  for (var i = 0; i < 10; i++) {
    counter.increment();
    await Future<void>.delayed(Duration.zero); // let the page see each state
  }
  counter.dispose();
}
