import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Golden images live under `test/goldens/<os>/`, since text renders slightly
/// differently per OS. A test compares against the reference for the OS it
/// runs on; where there's none yet, it records one and passes (CI uploads
/// them), and `flutter test --update-goldens` records every image again.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final os = Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
      ? 'windows'
      : 'linux';
  goldenFileComparator = _PerOsComparator(
    Uri.parse('${Directory.current.uri}test/goldens/$os/'),
  );
  await testMain();
}

final class _PerOsComparator extends LocalFileComparator {
  _PerOsComparator(Uri base) : super(base.resolve('placeholder.dart'));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final file = File.fromUri(basedir.resolveUri(golden));
    if (!file.existsSync()) {
      await update(golden, imageBytes);
      return true;
    }
    return super.compare(imageBytes, golden);
  }
}
