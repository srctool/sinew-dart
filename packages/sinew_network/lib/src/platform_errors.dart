// The web build has no dart:io: there, neither a socket nor a TLS failure can
// be told apart from Dio's own connection error.
export 'platform_errors_web.dart'
    if (dart.library.io) 'platform_errors_io.dart';
