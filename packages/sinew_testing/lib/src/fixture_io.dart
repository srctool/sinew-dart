import 'dart:io';

import 'missing_fixture.dart';

/// Reads `test/fixtures/<name>` from the package folder.
String fixture(String name) {
  final file = File('test/fixtures/$name');
  if (!file.existsSync()) {
    throw MissingFixture('No fixture "$name": expected ${file.absolute.path}');
  }
  return file.readAsStringSync();
}
