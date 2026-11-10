# sinew_camouflage example

A complete app that uses this package, with every platform runner, is the repository's
[example](https://github.com/srctool/sinew-dart/tree/main/example): a paged list of orders through Sinew's pager, its
Riverpod mixins and Camouflage's `CamoPagedList`.

## Usage

```dart
CamoPagedList<Order>(
  state: state.orders.toCamoOf(context),
  itemKey: (order) => order.id,
  onLoadMore: () => onEvent(const OrderListEndReached()),
  onRetry: () => onEvent(const OrderListRetryTapped()),
  onRefresh: () async => onEvent(const OrderListRefreshed()),
  itemBuilder: (context, order, _) => CamoListItem(
    headline: order.title,
    supporting: order.status,
  ),
)
```

Only a next-page load or failure keeps the items: a refresh drops them, so the list shows its skeleton.
