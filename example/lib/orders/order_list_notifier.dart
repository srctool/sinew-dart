import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinew_paging/sinew_paging.dart';
import 'package:sinew_riverpod/sinew_riverpod.dart';

import 'order_backend.dart';

/// The list screen's state.
final class OrderListState {
  /// Creates the state.
  const OrderListState({this.orders = const PagingState()});

  /// The list.
  final PagingState<Order> orders;
}

/// What the page reports.
sealed class OrderListEvent {
  const OrderListEvent();
}

/// The page opened.
final class OrderListOpened extends OrderListEvent {
  /// Creates the event.
  const OrderListOpened();
}

/// The list neared its end.
final class OrderListEndReached extends OrderListEvent {
  /// Creates the event.
  const OrderListEndReached();
}

/// Retry was tapped.
final class OrderListRetryTapped extends OrderListEvent {
  /// Creates the event.
  const OrderListRetryTapped();
}

/// The user asked for a refresh.
final class OrderListRefreshed extends OrderListEvent {
  /// Creates the event.
  const OrderListRefreshed();
}

/// The work an event means: one load.
final class LoadOrders {
  /// Creates the action.
  const LoadOrders(this.type);

  /// Which load to run.
  final LoadType type;
}

/// The backend the screen reads. A test replaces it.
final orderBackendProvider = Provider<OrderBackend>(
  (ref) => MockOrderBackend(),
);

/// The list screen's notifier.
final orderListProvider = NotifierProvider<OrderList, OrderListState>(
  OrderList.new,
);

// region notifier
/// Turns the page's events into loads, on Sinew's Riverpod mixins.
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
    // The pager runs initial once per query.
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
// endregion
