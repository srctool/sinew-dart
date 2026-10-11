## 0.1.0-dev.1

- S2: `EffectEmitter` (buffers while nobody listens, one listener at a time, re-listenable, hands an effect over only to an active, unpaused listener), `StateEffectHandler` (`state`, `states`, `effects`, `@protected` `setState` and `emitEffect`, inert after `dispose`) and `EventActionHandler` (`onEvent` maps an event to an action and runs it without awaiting, so actions run concurrently).
- S0: package skeleton.
