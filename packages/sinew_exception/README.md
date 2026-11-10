# sinew_exception

[![pub package](https://img.shields.io/pub/v/sinew_exception.svg)](https://pub.dev/packages/sinew_exception)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**A coded error model: typed exceptions, guards that create them once, a crash reporter and a localizer.**

Every failure is translated **once**, where it happened, into a `SinewException` with a code that reads `module-layer-function-type`, so a support report points at the exact call. Everything above that layer only passes the exception along.

## Features

- Built-in types for connectivity, HTTP statuses, parsing, storage and polling: `NoInternetConnectionException`, `ValidationException`, `UnauthorizedException`, `NotFoundException`, `ServerException`, `ParseException`, `StorageFullException` and more
- `processCall` and `processUseCase`: guards that turn whatever a block throws into a `Result`, with your `ExceptionHandler`s deciding what means what
- `CrashReporter`: where bugs (unexpected and parse failures) are reported, `CrashReporter.none` by default
- `Localizer` and `displayMessage`: the user-facing text, rendered at display time so a language switch updates an error already on screen

## Getting started

```sh
dart pub add sinew_exception
```

## Usage

```dart
final result = await processCall<Order>(
  'ORD',
  'load',
  ExceptionLayer.repository,
  [
    ExceptionHandler(
      (error) => error is FormatException,
      (error) => const ParseException('ORD', ExceptionLayer.repository, 'load'),
    ),
  ],
  () => api.order(7),
);

result.when(
  success: (order, message) => show(order),
  failure: (error, stackTrace) => print(error.code), // ORD-R-load-DF
);
```

The full program is in [example/main.dart](example/main.dart).

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_models`](https://pub.dev/packages/sinew_models)
- [`sinew_l10n`](https://pub.dev/packages/sinew_l10n)
- [`sinew_network`](https://pub.dev/packages/sinew_network)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_exception](https://pub.dev/documentation/sinew_exception/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
