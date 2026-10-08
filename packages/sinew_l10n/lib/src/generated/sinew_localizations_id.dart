// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'sinew_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class SinewLocalizationsId extends SinewLocalizations {
  SinewLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get sinewErrorNoInternet =>
      'Kamu sedang offline. Periksa koneksimu lalu coba lagi.';

  @override
  String get sinewErrorTimeout => 'Prosesnya terlalu lama. Silakan coba lagi.';

  @override
  String get sinewErrorValidation => 'Periksa kembali isian yang ditandai.';

  @override
  String get sinewErrorUnauthorized =>
      'Sesimu telah berakhir. Silakan masuk kembali.';

  @override
  String get sinewErrorForbidden => 'Kamu tidak punya akses ke halaman ini.';

  @override
  String get sinewErrorNotFound => 'Data ini sudah tidak tersedia.';

  @override
  String get sinewErrorConflict =>
      'Data ini sudah diubah oleh orang lain. Muat ulang lalu coba lagi.';

  @override
  String sinewErrorRateLimited(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Terlalu banyak percobaan. Coba lagi dalam $seconds detik.',
    );
    return '$_temp0';
  }

  @override
  String get sinewErrorRateLimitedNoTime =>
      'Terlalu banyak percobaan. Coba lagi sebentar lagi.';

  @override
  String get sinewErrorServer => 'Terjadi kesalahan di sistem kami.';

  @override
  String get sinewErrorUnavailable =>
      'Layanan sedang sibuk. Silakan coba lagi.';

  @override
  String get sinewErrorGeneric => 'Terjadi kesalahan.';

  @override
  String get sinewErrorStorageFull => 'Penyimpanan perangkatmu penuh.';

  @override
  String get sinewErrorStillProcessing =>
      'Masih diproses. Coba cek lagi nanti.';
}
