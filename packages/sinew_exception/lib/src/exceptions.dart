import 'package:sinew_models/sinew_models.dart';

// The built-in classification. Every type takes the module, layer and function of the guard that creates it.
// A type whose text is always local has a fixed message. A "server if readable" type takes a message that
// defaults to its local key, so a handler passes a ServerMessage only when the body had readable text.
// The codes and the `sinew.` key prefix are reserved; an app's own exceptions use other codes and keys.

const _generic = LocalMessage(
  'sinew.error.generic',
  fallback: 'Something went wrong.',
);

// Connectivity

/// No connection, a DNS failure, or a refused or reset connection.
class NoInternetConnectionException extends SinewException {
  /// Creates the exception.
  const NoInternetConnectionException(
    super.module,
    super.layer,
    super.function, {
    super.cause,
  });

  @override
  String get typeCode => 'NIC';

  @override
  bool get retryable => true;

  @override
  ErrorMessage get message => const LocalMessage(
    'sinew.error.noInternet',
    fallback: "You're offline. Check your connection and try again.",
  );
}

/// A connect, send or receive timeout, or the total deadline passed.
class RequestTimeOutException extends SinewException {
  /// Creates the exception.
  const RequestTimeOutException(
    super.module,
    super.layer,
    super.function, {
    super.cause,
  });

  @override
  String get typeCode => 'RTO';

  @override
  bool get retryable => true;

  @override
  ErrorMessage get message => const LocalMessage(
    'sinew.error.timeout',
    fallback: 'This is taking too long. Please try again.',
  );
}

/// A cancelled request. Never displayed and never reported: cancelling isn't a failure.
class CancelException extends SinewException {
  /// Creates the exception.
  const CancelException(
    super.module,
    super.layer,
    super.function, {
    super.cause,
  });

  @override
  String get typeCode => 'CNL';

  @override
  ErrorMessage get message => _generic;
}

// HTTP responses

/// A 400 or 422 with field messages. The form message is the backend's when it
/// sent one; field messages are shown beside their fields without a code.
class ValidationException extends SinewException {
  /// Creates the exception.
  const ValidationException(
    super.module,
    super.layer,
    super.function, {
    this.fieldErrors = const {},
    this.message = const LocalMessage(
      'sinew.error.validation',
      fallback: 'Please check the highlighted fields.',
    ),
    super.cause,
  });

  /// Field name → messages.
  final Map<String, List<String>> fieldErrors;

  @override
  final ErrorMessage message;

  @override
  String get typeCode => 'VAL';
}

/// A 401 the auth layer couldn't recover from.
class UnauthorizedException extends SinewException {
  /// Creates the exception.
  const UnauthorizedException(
    super.module,
    super.layer,
    super.function, {
    this.message = const LocalMessage(
      'sinew.error.unauthorized',
      fallback: 'Your session has ended. Please sign in again.',
    ),
    super.cause,
  });

  @override
  final ErrorMessage message;

  @override
  String get typeCode => 'UNA';
}

/// A 403.
class ForbiddenException extends SinewException {
  /// Creates the exception.
  const ForbiddenException(
    super.module,
    super.layer,
    super.function, {
    this.message = const LocalMessage(
      'sinew.error.forbidden',
      fallback: "You don't have access to this.",
    ),
    super.cause,
  });

  @override
  final ErrorMessage message;

  @override
  String get typeCode => 'FOR';
}

/// A 404.
class NotFoundException extends SinewException {
  /// Creates the exception.
  const NotFoundException(
    super.module,
    super.layer,
    super.function, {
    this.message = const LocalMessage(
      'sinew.error.notFound',
      fallback: 'This item no longer exists.',
    ),
    super.cause,
  });

  @override
  final ErrorMessage message;

  @override
  String get typeCode => 'NTF';
}

/// A 409.
class ConflictException extends SinewException {
  /// Creates the exception.
  const ConflictException(
    super.module,
    super.layer,
    super.function, {
    this.message = const LocalMessage(
      'sinew.error.conflict',
      fallback: 'This was changed by someone else. Reload and try again.',
    ),
    super.cause,
  });

  @override
  final ErrorMessage message;

  @override
  String get typeCode => 'CFL';
}

/// A 429. Its local message names the wait when the backend sent `Retry-After`.
class RateLimitedException extends SinewException {
  /// Creates the exception. Without [message], the local message depends on [retryAfter].
  const RateLimitedException(
    super.module,
    super.layer,
    super.function, {
    this.retryAfter,
    ErrorMessage? message,
    super.cause,
  })
    // A named parameter can't be private, so it can't be an initializing formal for _message.
    // ignore: prefer_initializing_formals
    : _message = message;

  /// How long the backend asked to wait, when it said.
  final Duration? retryAfter;

  final ErrorMessage? _message;

  @override
  ErrorMessage get message {
    final wait = retryAfter;
    return _message ??
        (wait == null
            ? const LocalMessage(
                'sinew.error.rateLimitedNoTime',
                fallback: 'Too many attempts. Try again in a moment.',
              )
            : LocalMessage(
                'sinew.error.rateLimited',
                args: {'seconds': wait.inSeconds},
                fallback: 'Too many attempts. Try again in {seconds} seconds.',
              ));
  }

  @override
  String get typeCode => 'RTL';

  @override
  bool get retryable => true;
}

/// Any 5xx except 503 and 504 (500, 501, 502, 505…): the backend's side.
class ServerException extends SinewException {
  /// Creates the exception.
  const ServerException(
    super.module,
    super.layer,
    super.function, {
    required this.status,
    this.message = const LocalMessage(
      'sinew.error.server',
      fallback: 'Something went wrong on our side.',
    ),
    super.cause,
  });

  /// The HTTP status.
  final int status;

  @override
  final ErrorMessage message;

  @override
  String get typeCode => 'SRV';
}

/// A 503 or 504: the backend is busy or a gateway timed out, so a retry may succeed.
class ServiceUnavailableException extends SinewException {
  /// Creates the exception.
  const ServiceUnavailableException(
    super.module,
    super.layer,
    super.function, {
    required this.status,
    this.message = const LocalMessage(
      'sinew.error.unavailable',
      fallback: 'The service is busy. Please try again.',
    ),
    super.cause,
  });

  /// The HTTP status.
  final int status;

  @override
  final ErrorMessage message;

  @override
  String get typeCode => 'SUN';

  @override
  bool get retryable => true;
}

/// The backend reported a failure with a readable message: an envelope
/// `failure()` or an error body. Always server text.
class ApiErrorException extends SinewException {
  /// Creates the exception.
  const ApiErrorException(
    super.module,
    super.layer,
    super.function, {
    required this.message,
    super.cause,
  });

  @override
  final ErrorMessage message;

  @override
  String get typeCode => 'AE';
}

/// Any other non-2xx status without a readable message.
class UndefinedErrorResponseException extends SinewException {
  /// Creates the exception.
  const UndefinedErrorResponseException(
    super.module,
    super.layer,
    super.function, {
    required this.status,
    super.cause,
  });

  /// The HTTP status.
  final int status;

  @override
  String get typeCode => 'UER';

  @override
  ErrorMessage get message => _generic;
}

/// A body that couldn't be parsed or mapped. Reported: it's a bug in the app or the backend.
class ParseException extends SinewException {
  /// Creates the exception.
  const ParseException(
    super.module,
    super.layer,
    super.function, {
    super.cause,
  });

  @override
  String get typeCode => 'DF';

  @override
  ErrorMessage get message => _generic;
}

// Storage

/// Stored data that can't be read back: a failed decryption or bytes that don't decode.
class LocalStorageCorruptionException extends SinewException {
  /// Creates the exception.
  const LocalStorageCorruptionException(
    super.module,
    super.layer,
    super.function, {
    super.cause,
  });

  @override
  String get typeCode => 'LSC';

  @override
  ErrorMessage get message => _generic;
}

/// The device is out of space.
class StorageFullException extends SinewException {
  /// Creates the exception.
  const StorageFullException(
    super.module,
    super.layer,
    super.function, {
    super.cause,
  });

  @override
  String get typeCode => 'SF';

  @override
  ErrorMessage get message => const LocalMessage(
    'sinew.error.storageFull',
    fallback: 'Your device is out of space.',
  );
}

/// Any other storage error, on a read.
class StorageReadException extends SinewException {
  /// Creates the exception.
  const StorageReadException(
    super.module,
    super.layer,
    super.function, {
    super.cause,
  });

  @override
  String get typeCode => 'SR';

  @override
  bool get retryable => true;

  @override
  ErrorMessage get message => _generic;
}

/// Any other storage error, on a write.
class StorageWriteException extends SinewException {
  /// Creates the exception.
  const StorageWriteException(
    super.module,
    super.layer,
    super.function, {
    super.cause,
  });

  @override
  String get typeCode => 'SW';

  @override
  bool get retryable => true;

  @override
  ErrorMessage get message => _generic;
}

// Other

/// Polling gave up while the backend was still processing.
class PollingTimeOutException extends SinewException {
  /// Creates the exception.
  const PollingTimeOutException(
    super.module,
    super.layer,
    super.function, {
    super.cause,
  });

  @override
  String get typeCode => 'PTO';

  @override
  bool get retryable => true;

  @override
  ErrorMessage get message => const LocalMessage(
    'sinew.error.stillProcessing',
    fallback: 'This is still processing. Check again later.',
  );
}

/// Anything no handler recognised: a bug. Reported.
class UnexpectedException extends SinewException {
  /// Creates the exception.
  const UnexpectedException(
    super.module,
    super.layer,
    super.function, {
    super.cause,
  });

  @override
  String get typeCode => 'GEN';

  @override
  ErrorMessage get message => _generic;
}
