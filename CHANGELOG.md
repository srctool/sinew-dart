# Changelog

All notable changes to Sinew for Dart and Flutter are documented here. Every package shares one version (lockstep); each package also keeps its own CHANGELOG for pub.dev.

## [Unreleased]
- S1 `sinew_models`: `Domain` (value equality from `props`), `Remote`, `Entity`; the error base contract (`SinewException`, `ExceptionLayer`, `ErrorMessage` with `ServerMessage` and `LocalMessage`, `EnvelopeDataMissing`); `Envelope` with the optional `failure()` and `message()` hooks, `EnvelopeFailure`, the four envelope bases, `PagingMetaEnvelope` and `unreachableDomainFromJson`; `PagingDomain`, `PagingMetaDomain`, `PagingEntity`, `ViewState` and `Result` (`Success(data, message)` / `Failure(error, stackTrace)`).
- S0: workspace skeleton. One package per Sinew package in a pub workspace managed by Melos, the dependency-graph check (`tool/check_graph.dart`), `sinew_l10n`'s generated and committed localizations (English, Indonesian), and the example app for all six platforms.
