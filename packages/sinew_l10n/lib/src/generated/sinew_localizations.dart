import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'sinew_localizations_en.dart';
import 'sinew_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of SinewLocalizations
/// returned by `SinewLocalizations.of(context)`.
///
/// Applications need to include `SinewLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/sinew_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: SinewLocalizations.localizationsDelegates,
///   supportedLocales: SinewLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the SinewLocalizations.supportedLocales
/// property.
abstract class SinewLocalizations {
  SinewLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static SinewLocalizations of(BuildContext context) {
    return Localizations.of<SinewLocalizations>(context, SinewLocalizations)!;
  }

  static const LocalizationsDelegate<SinewLocalizations> delegate =
      _SinewLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id'),
  ];

  /// No description provided for @sinewErrorNoInternet.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Check your connection and try again.'**
  String get sinewErrorNoInternet;

  /// No description provided for @sinewErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'This is taking too long. Please try again.'**
  String get sinewErrorTimeout;

  /// No description provided for @sinewErrorValidation.
  ///
  /// In en, this message translates to:
  /// **'Please check the highlighted fields.'**
  String get sinewErrorValidation;

  /// No description provided for @sinewErrorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Your session has ended. Please sign in again.'**
  String get sinewErrorUnauthorized;

  /// No description provided for @sinewErrorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access to this.'**
  String get sinewErrorForbidden;

  /// No description provided for @sinewErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'This item no longer exists.'**
  String get sinewErrorNotFound;

  /// No description provided for @sinewErrorConflict.
  ///
  /// In en, this message translates to:
  /// **'This was changed by someone else. Reload and try again.'**
  String get sinewErrorConflict;

  /// No description provided for @sinewErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Too many attempts. Try again in 1 second.} other{Too many attempts. Try again in {seconds} seconds.}}'**
  String sinewErrorRateLimited(int seconds);

  /// No description provided for @sinewErrorRateLimitedNoTime.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in a moment.'**
  String get sinewErrorRateLimitedNoTime;

  /// No description provided for @sinewErrorServer.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on our side.'**
  String get sinewErrorServer;

  /// No description provided for @sinewErrorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The service is busy. Please try again.'**
  String get sinewErrorUnavailable;

  /// No description provided for @sinewErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get sinewErrorGeneric;

  /// No description provided for @sinewErrorStorageFull.
  ///
  /// In en, this message translates to:
  /// **'Your device is out of space.'**
  String get sinewErrorStorageFull;

  /// No description provided for @sinewErrorStillProcessing.
  ///
  /// In en, this message translates to:
  /// **'This is still processing. Check again later.'**
  String get sinewErrorStillProcessing;
}

class _SinewLocalizationsDelegate
    extends LocalizationsDelegate<SinewLocalizations> {
  const _SinewLocalizationsDelegate();

  @override
  Future<SinewLocalizations> load(Locale locale) {
    return SynchronousFuture<SinewLocalizations>(
      lookupSinewLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_SinewLocalizationsDelegate old) => false;
}

SinewLocalizations lookupSinewLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SinewLocalizationsEn();
    case 'id':
      return SinewLocalizationsId();
  }

  throw FlutterError(
    'SinewLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
