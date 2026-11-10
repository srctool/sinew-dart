# sinew_riverpod

[![pub package](https://img.shields.io/pub/v/sinew_riverpod.svg)](https://pub.dev/packages/sinew_riverpod)
[![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-sinew.srctool.com-blue.svg)](https://sinew.srctool.com)

**Riverpod notifier mixins, hooks and `AsyncValue` conversions for Sinew's presentation pattern.**

The presentation pattern of `sinew_presentation`, as mixins on a Riverpod `Notifier`. The emitter lives as long as the notifier, so a rebuild keeps it and the page keeps receiving effects.

## Features

- `StateEffectNotifier` and `EventActionNotifier`: `setState`, `emitEffect`, `onEvent`, and the pure `mapEventToAction` split
- `useOnOpened` and `useEffects`: Flutter Hooks that send "the page opened" once, and listen to effects while the page is mounted
- `ViewStateToAsync` and `AsyncToViewState`: convert between `ViewState` and Riverpod's `AsyncValue`

## Getting started

```sh
flutter pub add sinew_riverpod
```

## Usage

A list page in a notifier (from the [example app](https://github.com/srctool/sinew-dart/tree/main/example/lib/orders)):

```dart
class OrderList extends Notifier<OrderListState>
    with
        StateEffectNotifier<OrderListState, Never>,
        EventActionNotifier<OrderListState, OrderListEvent, LoadOrders, Never> {
  late final Pager<Order> _pager = Pager.offset(
    (page, _) => ref.read(orderBackendProvider).orders(page),
    itemKey: (order) => order.id,
  );

  @override
  OrderListState build() => const OrderListState();

  @override
  LoadOrders? mapEventToAction(OrderListEvent event) => switch (event) {
    OrderListOpened() => const LoadOrders(LoadType.initial),
    OrderListEndReached() =>
      state.orders.canLoadMore ? const LoadOrders(LoadType.more) : null,
    OrderListRetryTapped() => LoadOrders(state.orders.retryType),
    OrderListRefreshed() => const LoadOrders(LoadType.refresh),
  };

  @override
  Future<void> onAction(LoadOrders action) => _pager.load(
    action.type,
    state.orders,
    update: (next) => setState((_) => OrderListState(orders: next)),
  );
}
```

The page calls `ref.read(orderListProvider.notifier).onEvent(...)`.

## Related packages

Sinew is one architecture for Flutter and Kotlin, released as a set of packages at one version.

- [`sinew_presentation`](https://pub.dev/packages/sinew_presentation)
- [`sinew_paging`](https://pub.dev/packages/sinew_paging)
- [`sinew_riverpod_providers`](https://pub.dev/packages/sinew_riverpod_providers)

## Documentation

- **Usage docs:** [sinew.srctool.com](https://sinew.srctool.com)
- **API reference:** [pub.dev/documentation/sinew_riverpod](https://pub.dev/documentation/sinew_riverpod/latest/)
- **Source and issues:** [srctool/sinew-dart](https://github.com/srctool/sinew-dart)
- **Design and decisions:** the [Guide](https://sinew-dev.srctool.com/guide)

## License

Apache 2.0, see [LICENSE](LICENSE).
