import 'package:sinew_models/sinew_models.dart';

/// How the app resolves a local message key in the current language.
abstract interface class Localizer {
  /// The text for [key] with [args] filled in, or `null` when not translated.
  String? resolve(String key, Map<String, Object> args);
}

/// Renders a [SinewException] for a page.
extension DisplayMessage on SinewException {
  /// The text a page shows, rendered every time it builds so a language
  /// switch updates an error already on screen.
  ///
  /// Server text is shown unchanged. A local key goes through [localizer],
  /// falling back to the English fallback with its arguments filled in (never
  /// the raw key). The code always ends the text. Validation field messages
  /// are shown beside their fields without one.
  String displayMessage(Localizer? localizer) {
    final text = switch (message) {
      ServerMessage(:final text) => text,
      final LocalMessage local =>
        localizer?.resolve(local.key, local.args) ?? local.text,
    };
    return '$text ($code)';
  }
}
