# sinew_network example

A complete app that uses this package, with every platform runner, is the repository's
[example](https://github.com/srctool/sinew-dart/tree/main/example): a paged list of orders through Sinew's pager, its
Riverpod mixins and Camouflage's `CamoPagedList`.

## Usage

```dart
final config = SinewConfig(
  baseUrl: 'https://api.example.com/v1',
  locale: () => 'en',
  anonymousPaths: {'/auth/login'},
);
final dio = SinewHttp.dio(config, tokenSource);

// In a repository: any failure becomes a typed SinewException.
Future<Result<Order>> cancel(String id) =>
    processApiCall('ORD', 'CANCEL', () => api.cancel(id));
```

API classes use paths relative to `baseUrl` (`get('orders')`), since a leading `/` would replace its own path. On sign-out, call `SinewHttp.resetAuth(dio)` and `tokenSource.clear()`.
