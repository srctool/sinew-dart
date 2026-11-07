import 'package:camouflage_core/camouflage_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinew_camouflage/sinew_camouflage.dart';

import 'order_backend.dart';
import 'order_list_notifier.dart';

/// The list. There's no pull gesture with a mouse, so the header offers a
/// refresh too.
class OrderListScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const OrderListScreen({super.key});

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen> {
  void _onEvent(OrderListEvent event) =>
      ref.read(orderListProvider.notifier).onEvent(event);

  @override
  void initState() {
    super.initState();
    // After the first frame: a provider can't change during a build.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _onEvent(const OrderListOpened()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderListProvider);
    return ColoredBox(
      color: Camouflage.colorsOf(context).surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: CamoButton(
                text: 'Refresh',
                onPressed: () => _onEvent(const OrderListRefreshed()),
              ),
            ),
            Expanded(
              child: CamoPagedList<Order>(
                state: state.orders.toCamoOf(context),
                itemKey: (order) => order.id,
                onLoadMore: () => _onEvent(const OrderListEndReached()),
                onRetry: () => _onEvent(const OrderListRetryTapped()),
                onRefresh: () async => _onEvent(const OrderListRefreshed()),
                itemBuilder: (context, order, _) => CamoListItem(
                  headline: order.title,
                  supporting: order.status,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
