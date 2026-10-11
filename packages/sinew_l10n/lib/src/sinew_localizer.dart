import 'package:flutter/widgets.dart';
import 'package:sinew_exception/sinew_exception.dart';

import 'generated/sinew_localizations.dart';

/// The [Localizer] a page renders errors with: the app's own strings first,
/// so an app can override any `sinew.` key, then Sinew's English and
/// Indonesian for the page's current locale.
///
/// ```dart
/// final localizer = SinewLocalizer.of(context, appStrings: AppLocalizer(context));
/// Text(error.displayMessage(localizer));
/// ```
///
/// Requires [SinewLocalizations.delegate] in the app's
/// `localizationsDelegates`.
class SinewLocalizer implements Localizer {
  /// Creates a localizer over [strings], asking [appStrings] first.
  const SinewLocalizer(this.strings, {this.appStrings});

  /// The localizer for [context]'s locale.
  factory SinewLocalizer.of(BuildContext context, {Localizer? appStrings}) =>
      SinewLocalizer(SinewLocalizations.of(context), appStrings: appStrings);

  /// Sinew's strings in one language.
  final SinewLocalizations strings;

  /// The app's own strings, asked first.
  final Localizer? appStrings;

  /// Every key Sinew translates.
  static const Set<String> keys = {
    'sinew.error.noInternet',
    'sinew.error.timeout',
    'sinew.error.validation',
    'sinew.error.unauthorized',
    'sinew.error.forbidden',
    'sinew.error.notFound',
    'sinew.error.conflict',
    'sinew.error.rateLimited',
    'sinew.error.rateLimitedNoTime',
    'sinew.error.server',
    'sinew.error.unavailable',
    'sinew.error.generic',
    'sinew.error.storageFull',
    'sinew.error.stillProcessing',
  };

  @override
  String? resolve(String key, Map<String, Object> args) =>
      appStrings?.resolve(key, args) ?? _sinew(key, args);

  String? _sinew(String key, Map<String, Object> args) => switch (key) {
    'sinew.error.noInternet' => strings.sinewErrorNoInternet,
    'sinew.error.timeout' => strings.sinewErrorTimeout,
    'sinew.error.validation' => strings.sinewErrorValidation,
    'sinew.error.unauthorized' => strings.sinewErrorUnauthorized,
    'sinew.error.forbidden' => strings.sinewErrorForbidden,
    'sinew.error.notFound' => strings.sinewErrorNotFound,
    'sinew.error.conflict' => strings.sinewErrorConflict,
    'sinew.error.rateLimited' => switch (args['seconds']) {
      final num seconds => strings.sinewErrorRateLimited(seconds.toInt()),
      _ => null, // without its quantity, the caller shows the English fallback
    },
    'sinew.error.rateLimitedNoTime' => strings.sinewErrorRateLimitedNoTime,
    'sinew.error.server' => strings.sinewErrorServer,
    'sinew.error.unavailable' => strings.sinewErrorUnavailable,
    'sinew.error.generic' => strings.sinewErrorGeneric,
    'sinew.error.storageFull' => strings.sinewErrorStorageFull,
    'sinew.error.stillProcessing' => strings.sinewErrorStillProcessing,
    _ => null,
  };
}
