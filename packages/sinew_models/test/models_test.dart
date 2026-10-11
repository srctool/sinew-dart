import 'package:sinew_models/sinew_models.dart';
import 'package:test/test.dart';

class _Money extends Domain {
  const _Money(this.amount, this.tags, this.extra);
  final int amount;
  final List<String> tags;
  final Map<String, int> extra;

  @override
  List<Object?> get props => [amount, tags, extra];
}

class _Other extends Domain {
  const _Other(this.amount);
  final int amount;

  @override
  List<Object?> get props => [amount];
}

class _TestException extends SinewException {
  const _TestException(ExceptionLayer layer, this.message, {super.cause})
    : super('ORD', layer, 'PO');

  @override
  String get typeCode => 'TST';

  @override
  final ErrorMessage message;
}

void main() {
  group('Domain', () {
    test('compares by props, deeply for lists and maps', () {
      // Distinct list and map instances, so equality can't come from canonicalized constants.
      _Money money(int amount, String tag, int x) =>
          _Money(amount, List.of([tag]), Map.of({'x': x}));
      expect(identical(money(5, 'a', 1), money(5, 'a', 1)), isFalse);
      expect(money(5, 'a', 1), money(5, 'a', 1));
      expect(money(5, 'a', 1).hashCode, money(5, 'a', 1).hashCode);
      expect(money(5, 'a', 1), isNot(money(5, 'b', 1)));
      expect(money(5, 'a', 1), isNot(money(5, 'a', 2)));
    });

    test('a different type with the same props is not equal', () {
      expect(const _Other(5), isNot(const _Money(5, [], {})));
    });
  });

  group('SinewException', () {
    test('code reads module-layer-function-type', () {
      final codes = ExceptionLayer.values.map(
        (layer) => _TestException(layer, const ServerMessage('x')).code,
      );
      expect(codes, [
        'ORD-VM-PO-TST',
        'ORD-UC-PO-TST',
        'ORD-R-PO-TST',
        'ORD-UT-PO-TST',
      ]);
    });

    test('a server message is shown unchanged', () {
      expect(
        const ServerMessage('Pesanan tidak ditemukan.').text,
        'Pesanan tidak ditemukan.',
      );
    });

    test('a local message keeps its key and arguments, and fills them into the fallback', () {
      const local = LocalMessage(
        'sinew.error.rateLimited',
        args: {'seconds': 30},
        fallback: 'Try again in {seconds} seconds.',
      );
      expect(local.key, 'sinew.error.rateLimited');
      expect(local.args, {'seconds': 30});
      expect(local.text, 'Try again in 30 seconds.');
    });

    test('messages compare by value', () {
      expect(
        const LocalMessage('k', args: {'n': 1}, fallback: 'f'),
        const LocalMessage('k', args: {'n': 1}, fallback: 'f'),
      );
      expect(const ServerMessage('a'), isNot(const ServerMessage('b')));
    });

    test('is not retryable by default and keeps its cause', () {
      final cause = StateError('boom');
      final e = _TestException(
        ExceptionLayer.repository,
        const ServerMessage('x'),
        cause: cause,
      );
      expect(e.retryable, isFalse);
      expect(e.cause, same(cause));
    });

    test('toString reads the code and the text, for logs', () {
      expect(
        const _TestException(
          ExceptionLayer.repository,
          ServerMessage('Gone.'),
        ).toString(),
        '_TestException(ORD-R-PO-TST): Gone.',
      );
    });

    test('EnvelopeDataMissing is a plain error, not a SinewException', () {
      const Object error = EnvelopeDataMissing();
      expect(error, isA<Exception>());
      expect(error, isNot(isA<SinewException>()));
    });
  });
}
