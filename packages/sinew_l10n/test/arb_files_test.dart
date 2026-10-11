import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Checks on the ARB sources themselves. Runs on the VM, from the package directory.

Map<String, Object?> _arb(String locale) =>
    jsonDecode(File('lib/l10n/sinew_$locale.arb').readAsStringSync())
        as Map<String, Object?>;

/// Every message key with the placeholder names its text uses.
Map<String, Set<String>> _placeholders(Map<String, Object?> arb) => {
  for (final entry in arb.entries)
    if (!entry.key.startsWith('@'))
      entry.key: RegExp(r'\{(\w+)[,}]')
          .allMatches(entry.value! as String)
          .map((m) => m.group(1)!)
          .toSet(),
};

void main() {
  test('both languages define every key with the same placeholders', () {
    expect(_placeholders(_arb('id')), _placeholders(_arb('en')));
  });

  test('the template declares the type of every placeholder', () {
    final english = _arb('en');
    for (final MapEntry(:key, value: names) in _placeholders(english).entries) {
      if (names.isEmpty) continue;
      final declared =
          ((english['@$key'] as Map<String, Object?>?)?['placeholders']
                  as Map<String, Object?>?)
              ?.keys
              .toSet();
      expect(declared, names, reason: key);
    }
  });
}
