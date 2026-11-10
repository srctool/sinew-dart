# sinew_l10n example

A complete app that uses this package, with every platform runner, is the repository's
[example](https://github.com/srctool/sinew-dart/tree/main/example): a paged list of orders through Sinew's pager, its
Riverpod mixins and Camouflage's `CamoPagedList`.

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
