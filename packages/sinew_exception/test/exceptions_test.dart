import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:test/test.dart';

const _r = ExceptionLayer.repository;

final List<SinewException> builtIns = [
  const NoInternetConnectionException('ORD', _r, 'GO'),
  const RequestTimeOutException('ORD', _r, 'GO'),
  const CancelException('ORD', _r, 'GO'),
  const ValidationException('ORD', _r, 'GO'),
  const UnauthorizedException('ORD', _r, 'GO'),
  const ForbiddenException('ORD', _r, 'GO'),
  const NotFoundException('ORD', _r, 'GO'),
  const ConflictException('ORD', _r, 'GO'),
  const RateLimitedException(
    'ORD',
    _r,
    'GO',
    retryAfter: Duration(seconds: 30),
  ),
  const ServerException('ORD', _r, 'GO', status: 500),
  const ServiceUnavailableException('ORD', _r, 'GO', status: 503),
  const ApiErrorException(
    'ORD',
    _r,
    'GO',
    message: ServerMessage('Out of stock.'),
  ),
  const UndefinedErrorResponseException('ORD', _r, 'GO', status: 418),
  const ParseException('ORD', _r, 'GO'),
  const LocalStorageCorruptionException('ORD', _r, 'GO'),
  const StorageFullException('ORD', _r, 'GO'),
  const StorageReadException('ORD', _r, 'GO'),
  const StorageWriteException('ORD', _r, 'GO'),
  const PollingTimeOutException('ORD', _r, 'GO'),
  const UnexpectedException('ORD', _r, 'GO'),
];

const sinewKeys = {
  'noInternet',
  'timeout',
  'validation',
  'unauthorized',
  'forbidden',
  'notFound',
  'conflict',
  'rateLimited', //
  'rateLimitedNoTime',
  'server',
  'unavailable',
  'generic',
  'storageFull',
  'stillProcessing',
};

void main() {
  test('every built-in type has its own code', () {
    final codes = builtIns.map((e) => e.typeCode).toSet();
    expect(codes, hasLength(20));
    expect(codes, {
      'NIC', 'RTO', 'CNL', 'VAL', 'UNA', 'FOR', 'NTF', 'CFL', 'RTL', 'SRV', //
      'SUN', 'AE', 'UER', 'DF', 'LSC', 'SF', 'SR', 'SW', 'PTO', 'GEN',
    });
  });

  test('every local message uses a reserved sinew key', () {
    final keys = builtIns
        .map((e) => e.message)
        .whereType<LocalMessage>()
        .map((m) => m.key)
        .toList();
    expect(
      keys,
      hasLength(19),
    ); // all but ApiErrorException, which is always server text
    expect(
      keys.every((k) => sinewKeys.map((s) => 'sinew.error.$s').contains(k)),
      isTrue,
      reason: '$keys',
    );
  });

  test('every fallback is plain text with its arguments filled in', () {
    for (final e in builtIns.where((e) => e.message is LocalMessage)) {
      final text = e.message.text;
      expect(text, endsWith('.'), reason: e.typeCode);
      for (final word in ['{', 'Exception', 'null', 'http', r'\']) {
        expect(text, isNot(contains(word)), reason: '${e.typeCode}: $text');
      }
    }
  });

  test('retryable follows the classification', () {
    expect(builtIns.where((e) => e.retryable).map((e) => e.typeCode).toSet(), {
      'NIC',
      'RTO',
      'RTL',
      'SUN',
      'SR',
      'SW',
      'PTO',
    });
  });

  test('codes read module-layer-function-type', () {
    expect(builtIns.first.code, 'ORD-R-GO-NIC');
  });

  test('server-if-readable types take the backend text', () {
    expect(
      const NotFoundException(
        'ORD',
        _r,
        'GO',
        message: ServerMessage('Pesanan tidak ditemukan.'),
      ).message,
      const ServerMessage('Pesanan tidak ditemukan.'),
    );
    expect(
      const NotFoundException('ORD', _r, 'GO').message,
      isA<LocalMessage>(),
    );
  });

  test('rate limited names the wait only when it is known', () {
    final known =
        const RateLimitedException(
              'ORD',
              _r,
              'GO',
              retryAfter: Duration(seconds: 30),
            ).message
            as LocalMessage;
    expect(known.key, 'sinew.error.rateLimited');
    expect(known.args, {'seconds': 30});
    const unknown = RateLimitedException('ORD', _r, 'GO');
    expect(
      (unknown.message as LocalMessage).key,
      'sinew.error.rateLimitedNoTime',
    );
    expect(unknown.retryAfter, isNull);
  });

  test('extra fields are kept', () {
    const validation = ValidationException(
      'ORD',
      _r,
      'GO',
      fieldErrors: {
        'email': ['Email is taken.'],
      },
    );
    expect(validation.fieldErrors, {
      'email': ['Email is taken.'],
    });
    expect(const ServerException('ORD', _r, 'GO', status: 502).status, 502);
    expect(
      const ServiceUnavailableException('ORD', _r, 'GO', status: 503).status,
      503,
    );
    expect(
      const UndefinedErrorResponseException(
        'ORD',
        _r,
        'GO',
        status: 418,
      ).status,
      418,
    );
  });
}
