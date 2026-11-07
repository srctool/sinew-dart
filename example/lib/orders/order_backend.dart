import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

/// One row of the list.
final class Order {
  /// Creates an order.
  const Order(this.id, this.title, this.status);

  /// The order's id.
  final int id;

  /// Its title.
  final String title;

  /// Its status.
  final String status;
}

/// Where the screen's pages come from.
abstract interface class OrderBackend {
  /// The orders on [page].
  Future<Result<PagingDomain<Order>>> orders(int page);
}

/// A backend in memory, so the example runs anywhere and shows every state:
/// each list loads with a delay, its second page fails the first time, and a
/// refresh starts that over.
final class MockOrderBackend implements OrderBackend {
  /// Creates the backend.
  MockOrderBackend({
    this.latency = const Duration(milliseconds: 800),
    this.pageSize = 15,
    this.pageCount = 3,
  });

  /// How long each page takes.
  final Duration latency;

  /// The rows on a page.
  final int pageSize;

  /// The number of pages.
  final int pageCount;

  bool _nextPageFails = true;

  @override
  Future<Result<PagingDomain<Order>>> orders(int page) async {
    await Future<void>.delayed(latency);
    if (page == 1) _nextPageFails = true;
    if (page == 2 && _nextPageFails) {
      _nextPageFails = false;
      return const Failure(
        NoInternetConnectionException('SMP', ExceptionLayer.repository, 'ORD'),
      );
    }
    final first = (page - 1) * pageSize + 1;
    return Success(
      PagingDomain(
        items: [
          for (var id = first; id < first + pageSize; id++)
            Order(id, 'Order #$id', id % 3 == 0 ? 'Delivered' : 'On the way'),
        ],
        meta: PagingMetaDomain(
          page: page,
          limit: pageSize,
          hasNextPage: page < pageCount,
        ),
      ),
    );
  }
}
