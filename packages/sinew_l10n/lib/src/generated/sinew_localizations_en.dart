// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'sinew_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SinewLocalizationsEn extends SinewLocalizations {
  SinewLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get sinewErrorNoInternet =>
      'You\'re offline. Check your connection and try again.';

  @override
  String get sinewErrorTimeout => 'This is taking too long. Please try again.';

  @override
  String get sinewErrorValidation => 'Please check the highlighted fields.';

  @override
  String get sinewErrorUnauthorized =>
      'Your session has ended. Please sign in again.';

  @override
  String get sinewErrorForbidden => 'You don\'t have access to this.';

  @override
  String get sinewErrorNotFound => 'This item no longer exists.';

  @override
  String get sinewErrorConflict =>
      'This was changed by someone else. Reload and try again.';

  @override
  String sinewErrorRateLimited(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Too many attempts. Try again in $seconds seconds.',
      one: 'Too many attempts. Try again in 1 second.',
    );
    return '$_temp0';
  }

  @override
  String get sinewErrorRateLimitedNoTime =>
      'Too many attempts. Try again in a moment.';

  @override
  String get sinewErrorServer => 'Something went wrong on our side.';

  @override
  String get sinewErrorUnavailable => 'The service is busy. Please try again.';

  @override
  String get sinewErrorGeneric => 'Something went wrong.';

  @override
  String get sinewErrorStorageFull => 'Your device is out of space.';

  @override
  String get sinewErrorStillProcessing =>
      'This is still processing. Check again later.';
}
