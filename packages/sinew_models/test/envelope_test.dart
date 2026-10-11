import 'dart:convert';

import 'package:sinew_models/sinew_models.dart';
import 'package:test/test.dart';

import 'fixtures/envelopes.dart';

Map<String, dynamic> _json(String source) =>
    jsonDecode(source) as Map<String, dynamic>;

PagedResponse<OrderRemote, Order> _paged(String source) =>
    PagedResponse.fromJson(_json(source), orderRemoteFromJson, orderFromJson);

ObjectResponse<OrderRemote, Order> _object(String source) =>
    ObjectResponse.fromJson(_json(source), orderRemoteFromJson, orderFromJson);

ListResponse<OrderRemote, Order> _list(String source) =>
    ListResponse.fromJson(_json(source), orderRemoteFromJson, orderFromJson);

RecordsPagedResponse<OrderRemote, Order> _records(String source) =>
    RecordsPagedResponse.fromJson(
      _json(source),
      orderRemoteFromJson,
      orderFromJson,
    );

void main() {
  const order1 = Order('o-1', OrderStatus.pending, 1200);
  const order2 = Order('o-2', OrderStatus.paid, 800);
  const twoOrders =
      '[ { "id": "o-1", "status": "pending", "total": 1200 }, { "id": "o-2", "status": "paid", "total": 800 } ]';

  group('example 1: success flag, message, meta object', () {
    test('a paged envelope maps every item and its meta', () {
      final page = _paged(
        '{ "success": true, "message": "", "data": $twoOrders, '
        '"meta": { "page": 1, "limit": 20, "total": 95, "totalPage": 5, "hasNextPage": true } }',
      ).toDomain();
      expect(
        page,
        const PagingDomain(
          items: [order1, order2],
          meta: PagingMetaDomain(
            page: 1,
            limit: 20,
            total: 95,
            totalPage: 5,
            hasNextPage: true,
          ),
        ),
      );
    });

    test(
      'a paged envelope without meta has the default meta and no next page',
      () {
        final page = _paged('{ "data": $twoOrders }').toDomain();
        expect(page.meta, const PagingMetaDomain());
        expect(page.items, hasLength(2));
      },
    );

    test('a meta with missing keys falls back to the app meta defaults', () {
      expect(
        _paged('{ "data": [], "meta": { "total": 3 } }').toDomain().meta,
        const PagingMetaDomain(page: 1, total: 3),
      );
    });

    test('an object envelope maps its payload', () {
      expect(
        _object(
          '{ "success": true, "data": { "id": "o-1", "status": "pending", "total": 1200 } }',
        ).toDomain(),
        order1,
      );
    });

    test('missing keys degrade one value, not the whole payload', () {
      expect(
        _object('{ "data": { "id": "o-1" } }').toDomain(),
        const Order('o-1', OrderStatus.unknown, 0),
      );
    });

    test('an unknown enum value decodes to unknown', () {
      expect(
        _object('{ "data": { "id": "o-1", "status": "refunded", "total": 5 } }')
            .toDomain()
            .status,
        OrderStatus.unknown,
      );
    });

    test('success false with errors is reported by failure()', () {
      final envelope = _object(
        '{ "success": false, "message": "Please check the form.", '
        '"errors": { "email": ["Email is taken."] }, "data": null }',
      );
      expect(
        envelope.failure(),
        const EnvelopeFailure(
          message: 'Please check the form.',
          fieldErrors: {
            'email': ['Email is taken.'],
          },
        ),
      );
    });

    test('success false without errors is reported by failure()', () {
      expect(
        _object('{ "success": false, "message": "Out of stock." }').failure(),
        const EnvelopeFailure(message: 'Out of stock.'),
      );
    });

    test('success true and a missing flag both mean succeeded', () {
      expect(
        _object('{ "success": true, "data": { "id": "o-1" } }').failure(),
        isNull,
      );
      expect(_object('{ "data": { "id": "o-1" } }').failure(), isNull);
    });

    test('message() is reported when present and null when absent', () {
      expect(
        _object('{ "message": "Order placed.", "data": { "id": "o-1" } }')
            .message(),
        'Order placed.',
      );
      expect(_object('{ "data": { "id": "o-1" } }').message(), isNull);
    });

    test('an object envelope with null data throws EnvelopeDataMissing', () {
      expect(
        () => _object('{ "success": true, "data": null }').toDomain(),
        throwsA(isA<EnvelopeDataMissing>()),
      );
    });

    test('a list envelope maps every item and treats null as empty', () {
      expect(_list('{ "data": $twoOrders }').toDomain(), [order1, order2]);
      expect(_list('{ "data": null }').toDomain(), isEmpty);
    });

    test('a paged envelope with null data is an empty page', () {
      expect(_paged('{ "data": null }').toDomain().items, isEmpty);
    });

    test('a void envelope maps to nothing and can still carry a message', () {
      final envelope = VoidResponse.fromJson(
        _json('{ "message": "Deleted." }'),
      );
      envelope.toDomain();
      expect(envelope.message(), 'Deleted.');
    });
  });

  group('example 2: records nested in data, no flag or message', () {
    test('maps its items and computes hasNextPage', () {
      final page = _records(
        '{ "data": { "records": $twoOrders, "max_page": 5, "total": 95, "page_size": 20, "current_page": 1 } }',
      ).toDomain();
      expect(
        page,
        const PagingDomain(
          items: [order1, order2],
          meta: PagingMetaDomain(
            page: 1,
            limit: 20,
            total: 95,
            totalPage: 5,
            hasNextPage: true,
          ),
        ),
      );
    });

    test('the last page has no next page', () {
      expect(
        _records(
          '{ "data": { "records": [], "max_page": 5, "current_page": 5 } }',
        ).toDomain().meta.hasNextPage,
        isFalse,
      );
    });

    test('keeps both hooks at their defaults', () {
      final envelope = _records('{ "data": { "records": [] } }');
      expect(envelope.failure(), isNull);
      expect(envelope.message(), isNull);
    });
  });

  group('unreachableDomainFromJson', () {
    test('decoding a generic envelope never calls it', () {
      // The stub throws when called, so decoding at all proves it wasn't.
      expect(_paged('{ "data": $twoOrders }').toDomain().items, isNotEmpty);
    });

    test('calling it throws', () {
      expect(() => Order.fromJson(<String, dynamic>{}), throwsStateError);
    });
  });
}
