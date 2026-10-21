import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:sinew_paging/sinew_paging.dart';
import 'package:sinew_storage/sinew_storage.dart';

/// A table of [size] rows, paged with a list-backed `LIMIT/OFFSET`, recording
/// each call.
final class Table {
  Table([int size = 25]) : rows = [for (var i = 0; i < size; i++) 'order-$i'];

  final List<String> rows;
  final calls = <(int, int)>[];

  Future<PagingEntity<String>> page(int page, int limit, {int firstPage = 1}) =>
      pagedQuery(page, limit, firstPage: firstPage, (offset, count) async {
        calls.add((offset, count));
        return rows.skip(offset).take(count).toList();
      });
}

void main() {
  test('the first page', () async {
    final table = Table();
    final page = await table.page(1, 10);
    expect(page.items, table.rows.take(10));
    expect(page.meta.page, 1);
    expect(page.meta.limit, 10);
    expect(page.meta.hasNextPage, isTrue);
    expect(page.meta.hasPreviousPage, isFalse);
    expect(table.calls, [(0, 11)], reason: 'one extra row, no count query');
  });

  test('a middle page', () async {
    final table = Table();
    final page = await table.page(2, 10);
    expect(page.items, table.rows.sublist(10, 20));
    expect(page.meta.hasNextPage, isTrue);
    expect(page.meta.hasPreviousPage, isTrue);
    expect(table.calls, [(10, 11)]);
  });

  test('the last page', () async {
    final page = await Table().page(3, 10);
    expect(page.items, hasLength(5));
    expect(page.meta.hasNextPage, isFalse);
  });

  test('a last page that is exactly full', () async {
    final page = await Table(20).page(2, 10);
    expect(page.items, hasLength(10));
    expect(page.meta.hasNextPage, isFalse);
  });

  test('an empty table', () async {
    final page = await Table(0).page(1, 10);
    expect(page.items, isEmpty);
    expect(page.meta.hasNextPage, isFalse);
  });

  test('a page beyond the last is empty', () async {
    final page = await Table().page(9, 10);
    expect(page.items, isEmpty);
    expect(page.meta.hasNextPage, isFalse);
  });

  test('a zero-based first page', () async {
    final table = Table();
    final first = await table.page(0, 10, firstPage: 0);
    expect(first.items, table.rows.take(10));
    expect(first.meta.hasPreviousPage, isFalse);
    expect(
      (await table.page(1, 10, firstPage: 0)).items,
      table.rows.sublist(10, 20),
    );
    expect(table.calls, [(0, 11), (10, 11)]);
  });

  test('totals stay zero', () async {
    final meta = (await Table().page(1, 10)).meta;
    expect(meta.total, 0);
    expect(meta.totalPage, 0);
  });

  test('a bad page or limit is refused before the query', () async {
    final table = Table();
    await expectLater(table.page(1, 0), throwsArgumentError);
    await expectLater(table.page(1, -1), throwsArgumentError);
    await expectLater(table.page(0, 10), throwsArgumentError);
    await expectLater(table.page(1 << 50, 10), throwsArgumentError);
    expect(table.calls, isEmpty);
  });

  test('the largest offset that fits is allowed', () async {
    final table = Table();
    const last = 9007199254740991 ~/ 10; // 2^53 - 1, the web's integer limit
    await table.page(last + 1, 10);
    expect(table.calls.single.$1, last * 10);
  });

  test('a local list pages with Pager.offset like a remote one', () async {
    final table = Table();
    final pager = Pager<String>.offset(
      (page, _) => processStorageCall(
        'ORD',
        'GPO',
        StorageAccess.read,
        () async => (await table.page(page, 10)).toDomain((row) => row),
      ),
    );
    var state = const PagingState<String>();
    await pager.load(LoadType.initial, state, update: (s) => state = s);
    while (state.canLoadMore) {
      await pager.load(LoadType.more, state, update: (s) => state = s);
    }
    expect((state.view as Done<PagingDomain<String>>).data.items, table.rows);
    expect(table.calls, [(0, 11), (10, 11), (20, 11)]);
  });
}
