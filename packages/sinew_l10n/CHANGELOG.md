## Unreleased

- Nothing changes for users. The generated localizations are left out of this package's own analysis, because Flutter 3.50 deprecates the delegates the generator lists.

## 1.0.0

- S1: `SinewLocalizer` (and `SinewLocalizer.of(context, appStrings:)`): the app's strings first, then Sinew's English and Indonesian for the page's locale, mapping each `sinew.error.*` key to its generated getter; replaces the S0 placeholder. Tests check every built-in key in both languages, English equal to each exception's fallback, the ARB placeholders, and a locale switch re-rendering an error on screen.
- S0: package skeleton.
