## 1.1.0

- Released with the other packages (lockstep). No changes in this package.

## 1.0.0

- S2: `StateEffectNotifier` and `EventActionNotifier`, mixins on `AnyNotifier<S, S>` (a `Notifier` or a generated `_$X`), with one emitter per notifier that survives rebuilds and is disposed with the provider; the hooks `useOnOpened` and `useEffects`; and `toViewState` / `toAsyncValue`, reading loading from `isLoading` so a refresh is `Loading(previous)`.
- S0: package skeleton.
