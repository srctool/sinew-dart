## 0.1.0-dev.1

- S1: `Domain` (value equality from `props`), `Remote`, `Entity`; the error base contract (`SinewException`, `ExceptionLayer`, `ErrorMessage` with `ServerMessage` and `LocalMessage`, `EnvelopeDataMissing`); `Envelope` with the optional `failure()` and `message()` hooks, `EnvelopeFailure`, the four envelope bases, `PagingMetaEnvelope` and `unreachableDomainFromJson`; `PagingDomain`, `PagingMetaDomain`, `PagingEntity`, `ViewState` and `Result` (`Success(data, message)` / `Failure(error, stackTrace)`).
- S0: package skeleton.
