import 'package:sinew_models/sinew_models.dart';
import 'package:test/test.dart';

class _TestException extends SinewException {
  const _TestException() : super('ORD', ExceptionLayer.repository, 'GO');

  @override
  String get typeCode => 'TST';

  @override
  ErrorMessage get message =>
      const LocalMessage('test.error', fallback: 'Test failure.');
}

void main() {
  const error = _TestException();

  group('paging shapes', () {
    test('defaults are an empty page with no next page', () {
      expect(
        const PagingDomain<String>(),
        const PagingDomain<String>(items: [], meta: PagingMetaDomain()),
      );
      expect(const PagingMetaDomain().hasNextPage, isFalse);
      expect(const PagingMetaDomain().nextKey, '');
    });

    test('copyWith replaces only the given fields', () {
      const meta = PagingMetaDomain(page: 1, limit: 20);
      expect(
        meta.copyWith(page: 2),
        const PagingMetaDomain(page: 2, limit: 20),
      );
      expect(const PagingDomain(items: [1]).copyWith(items: [1, 2]).items, [
        1,
        2,
      ]);
    });

    test('a stored page maps its items and every meta field', () {
      const stored = PagingEntity(
        items: [1, 2],
        meta: PagingMetaEntity(
          page: 2,
          limit: 10,
          total: 35,
          totalPage: 4,
          hasNextPage: true,
          hasPreviousPage: true,
          nextKey: 'c2',
        ),
      );
      expect(
        stored.toDomain((item) => 'item $item'),
        const PagingDomain(
          items: ['item 1', 'item 2'],
          meta: PagingMetaDomain(
            page: 2,
            limit: 10,
            total: 35,
            totalPage: 4,
            hasNextPage: true,
            hasPreviousPage: true,
            nextKey: 'c2',
          ),
        ),
      );
    });
  });

  group('ViewState', () {
    test('dataOrNull reads every variant', () {
      expect(const Loading<String>().dataOrNull, isNull);
      expect(const Loading('previous').dataOrNull, 'previous');
      expect(const Done('loaded').dataOrNull, 'loaded');
      expect(const Failed<String>(error).dataOrNull, isNull);
      expect(const Failed(error, data: 'previous').dataOrNull, 'previous');
    });

    test('isLoading only for Loading', () {
      expect(const Loading<String>().isLoading, isTrue);
      expect(const Done('x').isLoading, isFalse);
      expect(const Failed<String>(error).isLoading, isFalse);
    });

    test('Failed keeps the exception, not rendered text', () {
      expect(const Failed<String>(error).error, same(error));
    });

    test('equality ignores type arguments, so a const default equals an explicit state', () {
      // `const Loading()` as a default parameter is a Loading<Never>; it must
      // still equal a Loading<String> with the same data, both ways round.
      const ViewState<String> byDefault =
          Loading<Never>(); // what a const default produces
      const explicit = Loading<String>();
      expect(byDefault, explicit);
      expect(explicit, byDefault);
      expect(
        const Result<num>.success(1) == const Result<int>.success(1),
        isTrue,
      );
      expect(
        const Result<int>.success(1) == const Result<num>.success(1),
        isTrue,
      );
    });

    test('states compare by value', () {
      expect(const Done([1, 2]), const Done([1, 2]));
      expect(const Loading('a'), const Loading('a'));
      expect(const Loading('a'), isNot(const Done('a')));
    });
  });

  group('Result', () {
    test('a success carries data and an optional message', () {
      expect((const Result.success(1) as Success<int>).message, '');
      expect(
        (const Result.success(
          1,
          message: 'Order placed.',
        ) as Success<int>).message,
        'Order placed.',
      );
    });

    test(
      'when passes data and message, or the typed error and stack trace',
      () {
        final trace = StackTrace.current;
        expect(
          const Result.success(
            1,
            message: 'ok',
          ).when(success: (d, m) => '$d $m', failure: (e, _) => e.code),
          '1 ok',
        );
        expect(
          Result<int>.failure(error, trace).when(
            success: (d, m) => '$d',
            failure: (e, s) => '${e.code} ${identical(s, trace)}',
          ),
          'ORD-R-GO-TST true',
        );
      },
    );

    test('fold runs the matching branch', () {
      expect(
        const Result.success(1).fold((d) => 'data $d', (e) => e.code),
        'data 1',
      );
      expect(
        const Result<int>.failure(error).fold((d) => 'data $d', (e) => e.code),
        'ORD-R-GO-TST',
      );
    });

    test('transform keeps the message and passes failures through', () {
      expect(
        const Result.success(2, message: 'Saved.').transform((d) => '$d'),
        const Result.success('2', message: 'Saved.'),
      );
      expect(
        const Result<int>.failure(error).transform((d) => d + 1),
        const Result<int>.failure(error),
      );
    });

    test('requireData returns the data or throws the SinewException with its stack trace', () {
      expect(const Result.success(1).requireData(), 1);
      expect(
        () => const Result<int>.failure(error).requireData(),
        throwsA(same(error)),
      );
      final trace = StackTrace.current;
      try {
        Result<int>.failure(error, trace).requireData();
        fail('requireData returned');
      } on SinewException catch (e, s) {
        expect(e, same(error));
        expect(s.toString(), trace.toString());
      }
    });
  });
}
