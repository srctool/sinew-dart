// The sample order list from the Presentation note: events in, states and
// effects out, pure Dart, no Flutter import.

import 'dart:async';

import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_paging/sinew_paging.dart';
import 'package:sinew_presentation/sinew_presentation.dart';
import 'package:sinew_testing/paging.dart';
import 'package:test/test.dart';

final class OrderListState {
  const OrderListState({
    this.orders = const PagingState(),
    this.cancelling = false,
  });

  final PagingState<String> orders;
  final bool cancelling;

  OrderListState copyWith({PagingState<String>? orders, bool? cancelling}) =>
      OrderListState(
        orders: orders ?? this.orders,
        cancelling: cancelling ?? this.cancelling,
      );
}

sealed class OrderListEvent {
  const OrderListEvent();
}

final class Opened extends OrderListEvent {
  const Opened();
}

final class Refreshed extends OrderListEvent {
  const Refreshed();
}

final class EndReached extends OrderListEvent {
  const EndReached();
}

final class RetryTapped extends OrderListEvent {
  const RetryTapped();
}

final class CancelTapped extends OrderListEvent {
  const CancelTapped(this.id);
  final String id;
}

sealed class OrderListAction {
  const OrderListAction();
}

final class Load extends OrderListAction {
  const Load(this.type);
  final LoadType type;
}

final class Cancel extends OrderListAction {
  const Cancel(this.id);
  final String id;
}

sealed class OrderListEffect {
  const OrderListEffect();
}

final class Cancelled extends OrderListEffect {
  const Cancelled(this.message);
  final String message;

  @override
  bool operator ==(Object other) =>
      other is Cancelled && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

final class ShowError extends OrderListEffect {
  const ShowError(this.error);
  final SinewException error;

  @override
  bool operator ==(Object other) => other is ShowError && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

final class OrderListHandler
    extends
        EventActionHandler<
          OrderListState,
          OrderListEvent,
          OrderListAction,
          OrderListEffect
        > {
  OrderListHandler(ControlledFetch<String> fetch, this._cancelOrder)
    : _pager = Pager<String>.offset(fetch.call),
      super(const OrderListState());

  final Pager<String> _pager;
  final Future<Result<void>> Function(String id) _cancelOrder;

  @override
  OrderListAction? mapEventToAction(OrderListEvent event) => switch (event) {
    Opened() => const Load(
      LoadType.initial,
    ), // a repeat is ignored by the pager
    Refreshed() => const Load(LoadType.refresh),
    EndReached() => state.orders.canLoadMore ? const Load(LoadType.more) : null,
    RetryTapped() => Load(state.orders.retryType),
    CancelTapped(:final id) => state.cancelling ? null : Cancel(id),
  };

  @override
  Future<void> onAction(OrderListAction action) async {
    switch (action) {
      case Load(:final type):
        await _pager.load(
          type,
          state.orders,
          update: (orders) => setState((s) => s.copyWith(orders: orders)),
        );
      case Cancel(:final id):
        setState((s) => s.copyWith(cancelling: true));
        final result = await _cancelOrder(id);
        setState((s) => s.copyWith(cancelling: false));
        switch (result) {
          case Success(:final message):
            emitEffect(Cancelled(message));
          case Failure(:final error):
            emitEffect(ShowError(error));
        }
    }
  }

  @override
  void dispose() {
    _pager.cancel();
    super.dispose();
  }
}

const _offline = NoInternetConnectionException(
  'ORD',
  ExceptionLayer.repository,
  'GO',
);

PagingMetaDomain _meta(int page, {required bool hasNext}) =>
    PagingMetaDomain(page: page, hasNextPage: hasNext);

void main() {
  test('the order list runs end to end with no framework', () async {
    final fetch = ControlledFetch<String>();
    addTearDown(fetch.assertAllCompleted);
    final cancel = Completer<Result<void>>();
    final handler = OrderListHandler(fetch, (_) => cancel.future);
    addTearDown(handler.dispose);
    final effects = <OrderListEffect>[];
    handler.effects.listen(effects.add);

    handler.onEvent(const Opened());
    await pumpEventQueue();
    expect(handler.state.orders.view, isA<Loading<Object?>>());
    handler.onEvent(const Opened()); // the router re-creates the page
    await pumpEventQueue();
    expect(fetch.calls, hasLength(1));

    fetch.succeed(0, ['a', 'b'], meta: _meta(1, hasNext: true));
    await pumpEventQueue();
    expect(handler.state.orders.canLoadMore, isTrue);

    handler.onEvent(const EndReached());
    await pumpEventQueue();
    fetch.fail(1, _offline);
    await pumpEventQueue();
    expect(handler.state.orders.view, isA<Failed<Object?>>());

    handler.onEvent(const RetryTapped());
    await pumpEventQueue();
    expect(fetch.calls[2].key, 2); // retry repeats the failed page
    fetch.succeed(2, ['c'], meta: _meta(2, hasNext: false));
    await pumpEventQueue();
    final view = handler.state.orders.view as Done<PagingDomain<String>>;
    expect(view.data.items, ['a', 'b', 'c']);

    handler.onEvent(const EndReached()); // last page: no action
    await pumpEventQueue();
    expect(fetch.calls, hasLength(3));

    handler.onEvent(const CancelTapped('a'));
    await pumpEventQueue();
    expect(handler.state.cancelling, isTrue);
    handler.onEvent(const CancelTapped('a')); // guarded by state
    cancel.complete(const Result.success(null, message: 'Order cancelled.'));
    await pumpEventQueue();
    expect(effects, [const Cancelled('Order cancelled.')]);
    expect(handler.state.cancelling, isFalse);
  });

  test('a failed action is an effect, not state', () async {
    final handler = OrderListHandler(
      ControlledFetch<String>(),
      (_) async => const Result.failure(_offline),
    );
    addTearDown(handler.dispose);
    final effects = <OrderListEffect>[];
    handler.effects.listen(effects.add);

    handler.onEvent(const CancelTapped('a'));
    await pumpEventQueue();
    expect(effects, [const ShowError(_offline)]);
    expect(handler.state.cancelling, isFalse); // the page is still valid
    expect(handler.state.orders.view, isA<Loading<Object?>>());
  });

  test(
    'an effect emitted while the page re-subscribes is shown once',
    () async {
      final handler = OrderListHandler(
        ControlledFetch<String>(),
        (_) async => const Result.success(null, message: 'Order cancelled.'),
      );
      addTearDown(handler.dispose);
      final before = <OrderListEffect>[];
      final subscription = handler.effects.listen(before.add);
      await subscription.cancel(); // the page goes away

      handler.onEvent(const CancelTapped('a'));
      await pumpEventQueue();
      final after = <OrderListEffect>[];
      handler.effects.listen(after.add); // and comes back
      await pumpEventQueue();
      expect(before, isEmpty);
      expect(after, [const Cancelled('Order cancelled.')]);
    },
  );
}
