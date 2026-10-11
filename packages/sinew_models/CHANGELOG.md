## 0.1.0-dev.1

- Fix: `ViewState` and `Result` equality ignores type arguments, so a `const` default (`Loading<Never>`) equals an explicit state both ways round.
- S1: `Domain` (value equality from `props`), `Remote`, `Entity`; the error base contract (`SinewException`, `ExceptionLayer`, `ErrorMessage` with `ServerMessage` and `LocalMessage`, `EnvelopeDataMissing`); `Envelope` with the optional `failure()` and `message()` hooks, `EnvelopeFailure`, the four envelope bases, `PagingMetaEnvelope` and `unreachableDomainFromJson`; `PagingDomain`, `PagingMetaDomain`, `PagingEntity`, `ViewState` and `Result` (`Success(data, message)` / `Failure(error, stackTrace)`).
- S0: package skeleton.
