# sinew_devtools

[![pub package](https://img.shields.io/pub/v/sinew_devtools.svg)](https://pub.dev/packages/sinew_devtools)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**DevTools capture: recorders, redaction, fault rules and host override.**

What a tester needs to see and break the app: every request and exception recorded with secrets already hidden, faults that force a status or drop a connection, and a host that can be switched. This package is the capture; `sinew_devtools_ui` is the overlay. A production build contains neither.

## Features

- `NetworkRecorder` and `ExceptionRecorder`: bounded, in memory, newest first
- `Redaction`: hides tokens, passwords and one-time codes in headers, URLs and bodies before anything is stored, extend-only
- `FaultRules` and `HostOverride`, applied inside the auth layer so a forced 401 runs the real refresh
- `DevToolsGate`: a `const` that is `false` in production, so the compiler removes every devtools entry point from the build

## Getting started

```sh
flutter pub add sinew_devtools
```

## Usage

```dart
void main() {
  DevToolsGate.assertMatchesFlavor();
  runApp(DevToolsGate.enabled ? SinewDevTools(child: const App()) : const App());
}
```

Build with `--dart-define=SINEW_FLAVOR=staging` for devtools in a release build. A production build, or one with no define, has none. CI proves it by searching the compiled output for a marker string.

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_devtools_ui`](https://pub.dev/packages/sinew_devtools_ui)
- [`sinew_network`](https://pub.dev/packages/sinew_network)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_devtools](https://pub.dev/documentation/sinew_devtools/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
