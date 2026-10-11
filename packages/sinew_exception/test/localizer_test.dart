import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';
import 'package:test/test.dart';

const _r = ExceptionLayer.repository;

class _Indonesian implements Localizer {
  @override
  String? resolve(String key, Map<String, Object> args) => switch (key) {
    'sinew.error.noInternet' =>
      'Kamu sedang offline. Periksa koneksimu lalu coba lagi.',
    'sinew.error.rateLimited' =>
      'Terlalu banyak percobaan. Coba lagi dalam ${args['seconds']} detik.',
    _ => null,
  };
}

void main() {
  final indonesian = _Indonesian();

  test('server text is shown unchanged with the code', () {
    const e = NotFoundException(
      'ORD',
      _r,
      'GET',
      message: ServerMessage('Pesanan tidak ditemukan.'),
    );
    expect(
      e.displayMessage(indonesian),
      'Pesanan tidak ditemukan. (ORD-R-GET-NTF)',
    );
  });

  test('a local key is resolved by the localizer', () {
    expect(
      const NoInternetConnectionException(
        'ORD',
        _r,
        'GO',
      ).displayMessage(indonesian),
      'Kamu sedang offline. Periksa koneksimu lalu coba lagi. (ORD-R-GO-NIC)',
    );
  });

  test('arguments reach the localizer', () {
    expect(
      const RateLimitedException(
        'ORD',
        _r,
        'GO',
        retryAfter: Duration(seconds: 30),
      ).displayMessage(indonesian),
      'Terlalu banyak percobaan. Coba lagi dalam 30 detik. (ORD-R-GO-RTL)',
    );
  });

  test('a missing translation falls back to English, never the raw key', () {
    expect(
      const StorageFullException('ORD', _r, 'GO').displayMessage(indonesian),
      'Your device is out of space. (ORD-R-GO-SF)',
    );
    expect(
      const NoInternetConnectionException('ORD', _r, 'GO').displayMessage(null),
      "You're offline. Check your connection and try again. (ORD-R-GO-NIC)",
    );
  });

  test('the fallback has its arguments substituted', () {
    expect(
      const RateLimitedException(
        'ORD',
        _r,
        'GO',
        retryAfter: Duration(seconds: 30),
      ).displayMessage(null),
      'Too many attempts. Try again in 30 seconds. (ORD-R-GO-RTL)',
    );
  });

  test(
    'validation shows the code on the form message only, not on field messages',
    () {
      const e = ValidationException(
        'ORD',
        _r,
        'SU',
        fieldErrors: {
          'email': ['Email is taken.'],
        },
      );
      expect(
        e.displayMessage(null),
        'Please check the highlighted fields. (ORD-R-SU-VAL)',
      );
      expect(e.fieldErrors['email'], ['Email is taken.']);
    },
  );
}
