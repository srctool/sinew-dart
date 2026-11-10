# sinew_testing example

A complete app that uses this package, with every platform runner, is the repository's
[example](https://github.com/srctool/sinew-dart/tree/main/example): a paged list of orders through Sinew's pager, its
Riverpod mixins and Camouflage's `CamoPagedList`.

## Usage

Test a repository against a mock backend:

```dart
test('orders load', () async {
  final http = mockHttp((routes) => routes
      .on('GET', '/v1/orders').respond(200, body: fixture('orders_page.json')));
  final result = await OrderRepository(OrderApi(http.dio)).page(1);
  expect(http.requests.single.uri.path, '/v1/orders');
});
```

Hold a pager's calls open to test every state of a list:

```dart
final fetch = controlledFetch<Order>();
final pager = Pager<Order>.offset(fetch.call);
```
