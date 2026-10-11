import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_l10n/sinew_l10n.dart';
import 'package:sinew_models/sinew_models.dart';

const _r = ExceptionLayer.repository;

// One exception per local key, with the arguments its message takes.
const List<SinewException> localMessages = [
  NoInternetConnectionException('ORD', _r, 'GO'),
  RequestTimeOutException('ORD', _r, 'GO'),
  ValidationException('ORD', _r, 'GO'),
  UnauthorizedException('ORD', _r, 'GO'),
  ForbiddenException('ORD', _r, 'GO'),
  NotFoundException('ORD', _r, 'GO'),
  ConflictException('ORD', _r, 'GO'),
  RateLimitedException('ORD', _r, 'GO', retryAfter: Duration(seconds: 30)),
  RateLimitedException('ORD', _r, 'GO'),
  ServerException('ORD', _r, 'GO', status: 500),
  ServiceUnavailableException('ORD', _r, 'GO', status: 503),
  UnexpectedException('ORD', _r, 'GO'),
  StorageFullException('ORD', _r, 'GO'),
  PollingTimeOutException('ORD', _r, 'GO'),
];

class _FormalStrings implements Localizer {
  @override
  String? resolve(String key, Map<String, Object> args) =>
      key == 'sinew.error.noInternet' ? 'Anda sedang offline.' : null;
}

void main() {
  final english = SinewLocalizer(lookupSinewLocalizations(const Locale('en')));
  final indonesian = SinewLocalizer(
    lookupSinewLocalizations(const Locale('id')),
  );
  LocalMessage local(SinewException e) => e.message as LocalMessage;

  test('every built-in key is translated', () {
    expect(localMessages.map((e) => local(e).key).toSet(), SinewLocalizer.keys);
    expect(SinewLocalizer.keys, hasLength(14));
  });

  test('English matches the exception fallbacks', () {
    // A missing translation and the English text must read the same.
    for (final e in localMessages) {
      expect(
        english.resolve(local(e).key, local(e).args),
        local(e).text,
        reason: local(e).key,
      );
    }
  });

  test('every key has Indonesian', () {
    for (final e in localMessages) {
      final text = indonesian.resolve(local(e).key, local(e).args);
      expect(text, isNotNull, reason: local(e).key);
      expect(
        text,
        isNot(local(e).text),
        reason: '${local(e).key} is not translated',
      );
    }
    expect(
      indonesian.resolve('sinew.error.noInternet', const {}),
      'Kamu sedang offline. Periksa koneksimu lalu coba lagi.',
    );
  });

  test('plurals follow each language rules', () {
    expect(
      english.resolve('sinew.error.rateLimited', const {'seconds': 1}),
      'Too many attempts. Try again in 1 second.',
    );
    expect(
      english.resolve('sinew.error.rateLimited', const {'seconds': 30}),
      'Too many attempts. Try again in 30 seconds.',
    );
    expect(
      indonesian.resolve('sinew.error.rateLimited', const {'seconds': 1}),
      'Terlalu banyak percobaan. Coba lagi dalam 1 detik.',
    );
  });

  test('a key Sinew does not translate resolves to null', () {
    expect(english.resolve('orders.error.notCancellable', const {}), isNull);
    expect(
      english.resolve('sinew.error.rateLimited', const {}),
      isNull,
    ); // a plural needs its quantity
  });

  test("the app's strings win over Sinew's", () {
    final localizer = SinewLocalizer(
      lookupSinewLocalizations(const Locale('id')),
      appStrings: _FormalStrings(),
    );
    expect(
      localizer.resolve('sinew.error.noInternet', const {}),
      'Anda sedang offline.',
    );
    expect(
      localizer.resolve('sinew.error.generic', const {}),
      'Terjadi kesalahan.',
    );
  });

  testWidgets(
    'switching the locale re-renders an error on screen in the new language',
    (tester) async {
      const error = NoInternetConnectionException('ORD', _r, 'GO');

      Widget app(Locale locale) => Localizations(
        locale: locale,
        delegates: SinewLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) => Text(
            error.displayMessage(SinewLocalizer.of(context)),
            textDirection: TextDirection.ltr,
          ),
        ),
      );

      await tester.pumpWidget(app(const Locale('en')));
      expect(
        find.text(
          "You're offline. Check your connection and try again. (ORD-R-GO-NIC)",
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(app(const Locale('id')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Kamu sedang offline. Periksa koneksimu lalu coba lagi. (ORD-R-GO-NIC)',
        ),
        findsOneWidget,
      );
    },
  );
}
