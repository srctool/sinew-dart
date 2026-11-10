# sinew_presentation

[![pub package](https://img.shields.io/pub/v/sinew_presentation.svg)](https://pub.dev/packages/sinew_presentation)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**`StateEffectHandler`, `EventActionHandler` and `EffectEmitter`: the presentation pattern, with no framework.**

A page has **state** (what it renders) and **effects** (one-time reactions, such as a snackbar or a navigation), and effects are never state, so a rebuild can't repeat them. These base classes hold that pattern in plain Dart. `sinew_riverpod` adapts them to Riverpod notifiers.

## Features

- `StateEffectHandler<S, F>` for a page with one intent: `setState`, `emitEffect`, and `states` and `effects` streams
- `EventActionHandler<S, E, A, F>` for a page with several intents: the page sends events, a pure `mapEventToAction` decides the work, and `onAction` does it
- `EffectEmitter<F>`: each effect is delivered once, to one listener, and held until there is one

## Getting started

```sh
dart pub add sinew_presentation
```

## Usage

```dart
final class Counter extends StateEffectHandler<CounterState, ReachedTen> {
  Counter() : super(const CounterState(0));

  void increment() {
    setState((state) => CounterState(state.count + 1));
    if (state.count == 10) emitEffect(const ReachedTen());
  }
}

final counter = Counter();
counter.effects.listen((effect) => print('the counter reached ten'));
counter.states.listen((state) => print('count: ${state.count}'));
```

The full program is in [example/main.dart](example/main.dart).

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_riverpod`](https://pub.dev/packages/sinew_riverpod)
- [`sinew_paging`](https://pub.dev/packages/sinew_paging)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_presentation](https://pub.dev/documentation/sinew_presentation/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
