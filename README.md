# Sinew for Dart and Flutter

Sinew is a plug-and-play app architecture: response mapping, results, a coded error model, paging, presentation base classes, an HTTP client with token refresh, secure storage, and developer tools. This repository is the **Dart and Flutter** implementation.

The design and the full documentation live in the umbrella repository, [srctool/sinew](https://github.com/srctool/sinew).

## Packages

| Package | Kind | Holds |
|---|---|---|
| `sinew_models` | Dart | `Domain`, `Response`, `Entity`, envelope bases, paging shapes, `ViewState`, `Result` |
| `sinew_exception` | Dart | `SinewException` types, handlers, `processCall`, `CrashReporter`, `Localizer` |
| `sinew_paging` | Dart | `Pager`, `PagingState`, `LoadType` |
| `sinew_presentation` | Dart | `StateEffectHandler`, `EventActionHandler`, `EffectEmitter` |
| `sinew_l10n` | Flutter | English and Indonesian for the local error keys (generated, committed) |
| `sinew_riverpod` | Flutter | notifier mixins, hooks, `AsyncValue` conversions |
| `sinew_riverpod_providers` | Flutter | ready providers for network, storage and security |
| `sinew_network` | Flutter | `SinewHttp` (Dio), the auth layer, `processApiCall`, retry, polling |
| `sinew_security` | Flutter | `FieldCipher`, `BiometricVault` (becomes a plugin with native code at S4) |
| `sinew_storage` | Flutter | `SecureStore`, `KeyValueStore`, `processStorageCall`, `pagedQuery` |
| `sinew_testing` | Flutter | fakes and test helpers (dev dependency only) |
| `sinew_camouflage` | Flutter | `PagingState.toCamo()` for Camouflage's `CamoPagedList` |
| `sinew_devtools`, `sinew_devtools_ui` | Flutter | developer tools, compiled out of production builds |

Status: milestone **S0** (skeleton). Each package holds a placeholder until its milestone; third-party dependencies (Dio, Riverpod, secure storage…) are added in each package's milestone.

## Work in the workspace

```bash
dart pub global activate melos
flutter pub get          # resolves the whole pub workspace
melos run analyze
melos run graph          # tool/check_graph.dart against tool/sinew_graph.txt
melos run test
melos run l10n           # regenerate sinew_l10n after editing its ARB files, then commit the output
```

## License

Apache 2.0, see [LICENSE](LICENSE).
