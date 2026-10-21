import 'package:sinew_exception/sinew_exception.dart';

/// A [Localizer] over [strings], filling `{name}` placeholders from the
/// arguments. A key it doesn't have resolves to the key itself, so a test
/// asserts which key a page showed; with [echoKeys] off it resolves to
/// `null`, as an app without that translation does, and the English fallback
/// shows. [requested] records every key asked for.
final class FakeLocalizer implements Localizer {
  /// A localizer over [strings].
  FakeLocalizer({this.strings = const {}, this.echoKeys = true});

  /// The translations by key.
  final Map<String, String> strings;

  /// Whether a missing key resolves to itself rather than `null`.
  final bool echoKeys;

  final _requested = <String>[];

  /// Every key resolved, in order.
  List<String> get requested => List.unmodifiable(_requested);

  @override
  String? resolve(String key, Map<String, Object> args) {
    _requested.add(key);
    final text = strings[key];
    if (text == null) return echoKeys ? key : null;
    return args.entries.fold<String>(
      text,
      (result, arg) => result.replaceAll('{${arg.key}}', '${arg.value}'),
    );
  }
}
