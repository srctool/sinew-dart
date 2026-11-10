# sinew_models

[![pub package](https://img.shields.io/pub/v/sinew_models.svg)](https://pub.dev/packages/sinew_models)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**The shapes every Sinew app shares: domain models, envelopes, `Result` and `ViewState`.**

Sinew keeps three kinds of model apart, so a backend that renames a field touches one file. **`Domain`** is what the app needs, in business language. **`Remote`** is what the backend sends, shaped like its JSON. **`Entity`** is what is stored on the device. `Remote` and `Entity` each map to a `Domain` with `toDomain()`.

## Features

- `Domain`, `Remote` and `Entity`, with value equality from `props` (no `equatable` dependency)
- Envelope bases (`ObjectEnvelope`, `ListEnvelope`, `PagedEnvelope`, `VoidEnvelope`) that map any backend's body to one domain shape, and report a failure inside a 2xx body
- `Result<T>`: a `Success` that carries the backend's message, or a typed `Failure`, read with `when`
- `ViewState<T>`: `Loading`, `Done` and `Failed`, where `Loading` and `Failed` can keep the previous data
- `PagingDomain` and `PagingMetaDomain`: one page shape for every backend

## Getting started

```sh
dart pub add sinew_models
```

## Usage

Map a response body to the domain, and read the outcome:

```dart
final class Order extends Domain {
  const Order(this.id, this.title);

  final int id;
  final String title;

  @override
  List<Object?> get props => [id, title];
}

final class OrderRemote extends Remote<Order> {
  const OrderRemote(this.id, this.title);

  final int id;
  final String title;

  @override
  Order toDomain() => Order(id, title);
}

final class OrderEnvelope extends ObjectEnvelope<OrderRemote, Order> {
  const OrderEnvelope(this.data);

  @override
  final OrderRemote? data;
}

final result = Result.success(const OrderEnvelope(OrderRemote(7, 'Two coffees')).toDomain());
final text = result.when(
  success: (order, message) => 'Loaded ${order.title}',
  failure: (error, stackTrace) => 'Failed: ${error.code}',
);
```

The full program is in [example/main.dart](example/main.dart).

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_exception`](https://pub.dev/packages/sinew_exception)
- [`sinew_paging`](https://pub.dev/packages/sinew_paging)
- [`sinew_network`](https://pub.dev/packages/sinew_network)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_models](https://pub.dev/documentation/sinew_models/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
