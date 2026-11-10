# sinew_devtools_ui

[![pub package](https://img.shields.io/pub/v/sinew_devtools_ui.svg)](https://pub.dev/packages/sinew_devtools_ui)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**The DevTools overlay, dashboard and inspector pages.**

The in-app dashboard for `sinew_devtools`: a floating button that opens the Network Monitor, the Exception Log, the stores, fault injection, the API host and a changelog, in its own theme and back stack, never the app's.

## Features

- `SinewDevTools` wraps the app, and `DevToolsMenuItem` opens the dashboard from a settings screen
- Network Monitor with Copy, Copy as cURL and Replay, and an Exception Log, both redacted
- Inspectors for the key-value and secure stores, with secrets masked and never copyable
- Your own sections: `DevToolSection` with `DevToolPage`, `DevToolGroup`, `DevToolToggle` and `DevToolAction` entries, shown after Sinew's
- `BuildRibbon` for a label such as `1.4.0 (212) · staging`, and three launchers: `FloatingLauncher`, `MenuLauncher` and `CustomLauncher`

## Getting started

```sh
flutter pub add sinew_devtools_ui
```

## Usage

```dart
void main() {
  DevToolsGate.assertMatchesFlavor();
  const app = App();
  runApp(
    DevToolsGate.enabled
        ? const SinewDevTools(ribbon: BuildRibbon('1.4.0 · staging'), child: app)
        : app,
  );
}
```

`SinewDevTools` and `DevToolsMenuItem` check `DevToolsGate.enabled` themselves, so a production build whose `main` forgot the gate still shows only the app.

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_devtools`](https://pub.dev/packages/sinew_devtools)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_devtools_ui](https://pub.dev/documentation/sinew_devtools_ui/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
