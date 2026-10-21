@TestOn('vm')
library;

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_storage/sinew_storage.dart';

import 'support/memory_executor.dart';

/// An in-memory drift database with one `orders` table, created without code
/// generation: the queries are the `LIMIT ? OFFSET ?` SQL a DAO runs.
final class OrdersDb extends GeneratedDatabase {
  OrdersDb() : super(memoryExecutor());

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  Future<void> seed(int count) async {
    await customStatement(
      'CREATE TABLE orders (id INTEGER PRIMARY KEY, placed_at INTEGER NOT NULL)',
    );
    // Placed in reverse id order, so the query's ORDER BY is what sorts them.
    for (var id = 1; id <= count; id++) {
      await customStatement(
        'INSERT INTO orders (id, placed_at) VALUES (?, ?)',
        [id, 1000 - id],
      );
    }
  }

  /// Newest first: the order a list screen shows.
  Future<List<int>> page(int offset, int count) async => [
    for (final row in await customSelect(
      'SELECT id FROM orders ORDER BY placed_at ASC LIMIT ? OFFSET ?',
      variables: [Variable.withInt(count), Variable.withInt(offset)],
    ).get())
      row.read<int>('id'),
  ];
}

void main() {
  late OrdersDb db;
  setUp(() => db = OrdersDb());
  tearDown(() => db.close());

  /// Pages the table and checks the page's rows and flags.
  Future<void> expectPage(
    int page,
    List<int> items, {
    required bool next,
    required bool previous,
    int firstPage = 1,
  }) async {
    final result = await pagedQuery(page, 10, db.page, firstPage: firstPage);
    expect(result.items, items, reason: 'page $page');
    expect(result.meta.hasNextPage, next, reason: 'page $page');
    expect(result.meta.hasPreviousPage, previous, reason: 'page $page');
  }

  List<int> ids(int from, int to) => [for (var id = to; id >= from; id--) id];

  test('the first, a middle and the last page', () async {
    await db.seed(25);
    await expectPage(1, ids(16, 25), next: true, previous: false);
    await expectPage(2, ids(6, 15), next: true, previous: true);
    await expectPage(3, ids(1, 5), next: false, previous: true);
  });

  test('an empty table has one empty page', () async {
    await db.seed(0);
    await expectPage(1, [], next: false, previous: false);
  });

  test('a last page that is exactly full has no next page', () async {
    await db.seed(20);
    await expectPage(2, ids(1, 10), next: false, previous: true);
  });

  test('a zero-based first page', () async {
    await db.seed(25);
    await expectPage(0, ids(16, 25), next: true, previous: false, firstPage: 0);
    await expectPage(2, ids(1, 5), next: false, previous: true, firstPage: 0);
  });
}
