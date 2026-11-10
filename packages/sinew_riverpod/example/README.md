# sinew_riverpod example

A complete app that uses this package, with every platform runner, is the repository's
[example](https://github.com/srctool/sinew-dart/tree/main/example): a paged list of orders through Sinew's pager, its
Riverpod mixins and Camouflage's `CamoPagedList`.

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
