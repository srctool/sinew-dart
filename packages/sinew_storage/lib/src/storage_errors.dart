// The web build has no dart:io; there, storage errors are the browser's
// DOMExceptions, told apart by name.
export 'storage_errors_web.dart' if (dart.library.io) 'storage_errors_io.dart';
