# sinew_devtools example

A complete app that uses this package, with every platform runner, is the repository's
[example](https://github.com/srctool/sinew-dart/tree/main/example): a paged list of orders through Sinew's pager, its
Riverpod mixins and Camouflage's `CamoPagedList`.

## Usage

```dart
void main() {
  DevToolsGate.assertMatchesFlavor();
  runApp(DevToolsGate.enabled ? SinewDevTools(child: const App()) : const App());
}
```

Build with `--dart-define=SINEW_FLAVOR=staging` for devtools in a release build. A production build, or one with no define, has none. CI proves it by searching the compiled output for a marker string.
