# Changelog

All notable changes to Sinew for Dart and Flutter are documented here. Every package shares one version (lockstep); each package also keeps its own CHANGELOG for pub.dev.

## [Unreleased]
- S1 `sinew_l10n`: `SinewLocalizer` (and `SinewLocalizer.of(context, appStrings:)`): the app's strings first, then Sinew's English and Indonesian for the page's locale, mapping each `sinew.error.*` key to its generated getter; replaces the S0 placeholder. Tests check every built-in key in both languages, English equal to each exception's fallback, the ARB placeholders, and a locale switch re-rendering an error on screen.
- S1 `sinew_exception`: the 20 built-in types (including `CancelException`), `ExceptionHandler`, `envelopeDataMissing`, `processCall` (pass-through, first-match handlers, Dart `Error`s caught, unexpected and parse failures reported with their stack trace), `processUseCase`, `CrashReporter` (`none`, `install`, `current`), `Localizer` and `displayMessage`.
- S1 `sinew_models`: `Domain` (value equality from `props`), `Remote`, `Entity`; the error base contract (`SinewException`, `ExceptionLayer`, `ErrorMessage` with `ServerMessage` and `LocalMessage`, `EnvelopeDataMissing`); `Envelope` with the optional `failure()` and `message()` hooks, `EnvelopeFailure`, the four envelope bases, `PagingMetaEnvelope` and `unreachableDomainFromJson`; `PagingDomain`, `PagingMetaDomain`, `PagingEntity`, `ViewState` and `Result` (`Success(data, message)` / `Failure(error, stackTrace)`).
- S0: workspace skeleton. One package per Sinew package in a pub workspace managed by Melos, the dependency-graph check (`tool/check_graph.dart`), `sinew_l10n`'s generated and committed localizations (English, Indonesian), and the example app for all six platforms.
