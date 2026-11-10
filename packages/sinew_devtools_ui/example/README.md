# sinew_devtools_ui example

A complete app that uses this package, with every platform runner, is the repository's
[example](https://github.com/srctool/sinew-dart/tree/main/example): a paged list of orders through Sinew's pager, its
Riverpod mixins and Camouflage's `CamoPagedList`.

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
