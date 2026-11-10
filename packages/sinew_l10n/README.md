# sinew_l10n

[![pub package](https://img.shields.io/pub/v/sinew_l10n.svg)](https://pub.dev/packages/sinew_l10n)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**English and Indonesian translations of Sinew's local error messages.**

`sinew_exception` gives every failure a message key and an English fallback. This package translates those keys, and plugs into Flutter's localization, so an error shown in the app follows the app's language.

## Features

- `SinewLocalizations`: the generated localizations and delegates, in English and Indonesian
- `SinewLocalizer`: a `Localizer` for `SinewException.displayMessage`, which asks your own strings first and falls back to Sinew's

## Getting started

```sh
flutter pub add sinew_l10n
```

## Usage

Add the delegates to your app, then render an error with the localizer:

```dart
MaterialApp(
  localizationsDelegates: SinewLocalizations.localizationsDelegates,
  supportedLocales: SinewLocalizations.supportedLocales,
  home: const Home(),
);

// in a build method
final localizer = SinewLocalizer.of(context);
Text(error.displayMessage(localizer));
```

Pass `appStrings:` to `SinewLocalizer.of` to translate your own error keys through the same localizer.

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_exception`](https://pub.dev/packages/sinew_exception)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_l10n](https://pub.dev/documentation/sinew_l10n/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
