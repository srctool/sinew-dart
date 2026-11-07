import 'dart:async';

import 'package:camouflage_core/camouflage_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_example/main.dart';
import 'package:sinew_example/orders/order_backend.dart';
import 'package:sinew_example/orders/order_list_notifier.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

/// Answers each page when the test says, so the test sees the states in
/// between.
final class ScriptedBackend implements OrderBackend {
  /// The rows on a page: few enough that the list asks for the next at once.
  static const pageSize = 3;

  /// The pages asked for, in order.
  final calls = <int>[];

  var _pending = Completer<Result<PagingDomain<Order>>>();

  @override
  Future<Result<PagingDomain<Order>>> orders(int page) {
    calls.add(page);
    return _pending.future;
  }

  void _answer(Result<PagingDomain<Order>> result) {
    final answered = _pending;
    _pending = Completer();
    answered.complete(result);
  }

  /// Answers the running call with [page].
  void answerPage(int page, {required bool hasNext}) => _answer(
    Success(
      PagingDomain(
        items: [
          for (var i = 1; i <= pageSize; i++)
            Order(
              (page - 1) * pageSize + i,
              'Order #${(page - 1) * pageSize + i}',
              'On the way',
            ),
        ],
        meta: PagingMetaDomain(page: page, hasNextPage: hasNext),
      ),
    ),
  );

  /// Fails the running call.
  void fail() => _answer(
    const Failure(
      NoInternetConnectionException('SMP', ExceptionLayer.repository, 'ORD'),
    ),
  );
}

/// Skeleton, items, more items, a failed next page and its retry, a refresh by
/// the pull and by the button, and the end of the list. `pump` rather than
/// `pumpAndSettle`, because the skeleton animates until it's gone.
Future<void> runOrderListFlow(WidgetTester tester) async {
  final backend = ScriptedBackend();

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [orderBackendProvider.overrideWithValue(backend)],
      child: const SinewExampleApp(),
    ),
  );
  await settle();

  // First load: the skeleton shows, without rows.
  expect(backend.calls, [1]);
  expect(find.text('Order #1'), findsNothing);

  // The first page. It's short, so the list asks for the next one right away.
  backend.answerPage(1, hasNext: true);
  await settle();
  expect(find.text('Order #1'), findsOneWidget);
  expect(backend.calls, [1, 2]);

  // The next page fails: the rows stay, with a retry row, and nothing loads
  // until it's tapped.
  backend.fail();
  await settle();
  expect(find.text('Retry'), findsOneWidget);
  expect(find.text('Order #1'), findsOneWidget);
  expect(backend.calls, [1, 2]);

  // Retry loads that page again.
  await tester.tap(find.text('Retry'));
  await settle();
  expect(backend.calls, [1, 2, 2]);
  backend.answerPage(2, hasNext: false);
  await settle();
  expect(find.text('Order #6'), findsOneWidget);
  expect(find.text('Retry'), findsNothing);

  // Pull to refresh goes back to the first page, with the skeleton. A bouncing
  // list releases the pull when it has sprung back, which takes a moment.
  await tester.drag(find.byType(CamoPagedList<Order>), const Offset(0, 400));
  for (var i = 0; i < 60 && backend.calls.length == 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await settle();
  expect(backend.calls, [1, 2, 2, 1]);
  expect(find.text('Order #1'), findsNothing);
  backend.answerPage(1, hasNext: true);
  await settle();
  expect(find.text('Order #1'), findsOneWidget);
  expect(backend.calls, [1, 2, 2, 1, 2]);
  backend.answerPage(2, hasNext: false);
  await settle();
  expect(find.text('Order #6'), findsOneWidget);

  // The refresh button does the same, for a mouse.
  await tester.tap(find.text('Refresh'));
  await settle();
  expect(backend.calls, [1, 2, 2, 1, 2, 1]);

  // The end of the list: everything shows, and nothing more loads.
  backend.answerPage(1, hasNext: false);
  await settle();
  expect(find.text('Order #3'), findsOneWidget);
  expect(backend.calls, [1, 2, 2, 1, 2, 1]);
}
