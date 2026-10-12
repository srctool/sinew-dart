import 'package:dio/dio.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

import 'http_status_error.dart';
import 'interceptors.dart';
import 'platform_errors.dart';

const _repository = ExceptionLayer.repository;

/// The source guard for an HTTP call: [call] returns the response's envelope,
/// and the result is a [Result] with a classified [SinewException] on
/// failure. It never throws.
///
/// - A failed status, a timeout, a cancel or no connection goes through
///   [apiHandlers], first match wins.
/// - An envelope whose `failure()` is set fails as a [ValidationException]
///   (with field errors) or an [ApiErrorException], before `toDomain()`.
/// - `toDomain()` runs inside the guard, so a mapping bug becomes a reported
///   [ParseException] or [UnexpectedException].
/// - The envelope's `message()` becomes `Success.message`.
///
/// The client needs `SinewErrorBodyInterceptor` to give a failed response its
/// readable message. Without it, a failed status is classified by status
/// alone.
///
/// ```dart
/// Future<Result<Order>> cancel(String id) => processApiCall('ORD', 'CANCEL', () => api.cancel(id));
/// ```
Future<Result<R>> processApiCall<R>(
  String module,
  String function,
  Future<Envelope<R>> Function() call,
) async => switch (await _guard(module, function, false, call)) {
  Success(:final data, :final message) => Success(data as R, message: message),
  Failure(:final error, :final stackTrace) => Failure(error, stackTrace),
};

/// [processApiCall] for a lookup that may not exist: a 404 is
/// `Success(null)`, every other failure is unchanged.
Future<Result<R?>> processOptionalApiCall<R>(
  String module,
  String function,
  Future<Envelope<R>> Function() call,
) => _guard(module, function, true, call);

Future<Result<R?>> _guard<R>(
  String module,
  String function,
  bool notFoundIsNull,
  Future<Envelope<R>> Function() call,
) async {
  var message = '';
  final result = await processCall<R?>(
    module,
    function,
    _repository,
    apiHandlers(module, function),
    () async {
      final Envelope<R> envelope;
      try {
        envelope = await call();
      } on DioException catch (e) {
        // A SinewException the auth interceptor wrapped (a refresh's cause)
        // passes through as is: already classified, and already reported.
        if (e.error case final SinewException wrapped) throw wrapped;
        if (notFoundIsNull && _statusError(e)?.status == 404) return null;
        rethrow;
      }
      final failure = envelope.failure();
      if (failure != null) throw _failureException(module, function, failure);
      message = envelope.message() ?? '';
      return envelope.toDomain();
    },
  );
  return switch (result) {
    Success(:final data) => Success(data, message: message),
    Failure() => result,
  };
}

const _validation = LocalMessage(
  'sinew.error.validation',
  fallback: 'Please check the highlighted fields.',
);
const _genericMessage = LocalMessage(
  'sinew.error.generic',
  fallback: 'Something went wrong.',
);

ErrorMessage _serverOr(String? text, LocalMessage local) =>
    text != null && text.trim().isNotEmpty ? ServerMessage(text) : local;

SinewException _failureException(
  String module,
  String function,
  EnvelopeFailure failure,
) {
  final fields = failure.fieldErrors;
  return fields != null && fields.isNotEmpty
      ? ValidationException(
          module,
          _repository,
          function,
          fieldErrors: fields,
          message: _serverOr(failure.message, _validation),
        )
      : ApiErrorException(
          module,
          _repository,
          function,
          message: _serverOr(failure.message, _genericMessage),
        );
}

/// The HTTP handler table over Dio's errors, first match wins. Public, so an
/// app can guard a call Sinew doesn't wrap with `processCall` and these
/// handlers.
///
/// | Matches | Becomes |
/// |---|---|
/// | a `DioException` carrying a `SinewException` (from the auth interceptor) | that exception |
/// | a cancel with `DeadlineExceeded`, or a connect, send or receive timeout | [RequestTimeOutException] |
/// | any other cancel | [CancelException], never reported |
/// | a connection error, or a socket failure, unless a TLS failure is in it | [NoInternetConnectionException] |
/// | a failed status: 400/422 with field errors, 401, 403, 404, 409, 429, 503/504, other 5xx, the rest | the base table's rows |
/// | unreadable JSON, a DTO that doesn't fit, an enum value with no fallback | [ParseException], reported |
/// | an envelope with no payload | [ParseException], reported |
///
/// A readable error-body message is the exception's server text; otherwise
/// its type's local message. A bad certificate or a TLS failure (a pinning
/// mismatch included) matches nothing and becomes a reported
/// [UnexpectedException]: a security event, never "offline". So does a 408
/// status, which the server sent and so isn't a client timeout.
List<ExceptionHandler> apiHandlers(String module, String function) => [
  ExceptionHandler(
    (e) => e is DioException && e.error is SinewException,
    (e) => (e as DioException).error! as SinewException,
  ),
  ExceptionHandler(
    _isTimeout,
    (e) => RequestTimeOutException(module, _repository, function, cause: e),
  ),
  ExceptionHandler(
    (e) => e is DioException && e.type == DioExceptionType.cancel,
    (e) => CancelException(module, _repository, function, cause: e),
  ),
  ExceptionHandler(
    _isNoConnection,
    (e) =>
        NoInternetConnectionException(module, _repository, function, cause: e),
  ),
  ExceptionHandler(
    (e) => e is DioException && _statusError(e) != null,
    (e) =>
        _statusException(module, function, _statusError(e as DioException)!, e),
  ),
  ExceptionHandler(
    _isUnreadable,
    (e) => ParseException(module, _repository, function, cause: e),
  ),
  envelopeDataMissing(module, function, _repository),
];

bool _isTimeout(Object e) =>
    e is DioException &&
    switch (e.type) {
      DioExceptionType.cancel => e.error is DeadlineExceeded,
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => true,
      _ => false,
    };

bool _isNoConnection(Object e) {
  if (e is! DioException) return false;
  final cause = e.error;
  if (cause != null && isTlsFailure(cause)) return false;
  return switch (e.type) {
    DioExceptionType.connectionError => true,
    DioExceptionType.unknown => cause != null && isSocketFailure(cause),
    _ => false,
  };
}

/// JSON that doesn't parse, a DTO whose fields don't fit, or an enum value
/// with no `unknownEnumValue`, raised by Dio's decoding or by the DTO's
/// `fromJson` inside the call.
bool _isUnreadable(Object e) {
  final error = e is DioException ? e.error : e;
  return error is TypeError ||
      error is FormatException ||
      // json_serializable's $enumDecode, for an enum value with no fallback.
      (error is ArgumentError &&
          '${error.message}'.contains('is not one of the supported values')) ||
      // json_serializable's checked mode; matched by name to avoid depending on json_annotation.
      error.runtimeType.toString() == 'CheckedFromJsonException';
}

/// The failed response in [e]: from `SinewErrorBodyInterceptor` with its body
/// read, or by status alone when that interceptor isn't installed.
HttpStatusError? _statusError(DioException e) {
  if (e.error case final HttpStatusError status) return status;
  final response = e.response;
  if (e.type != DioExceptionType.badResponse || response == null) return null;
  return HttpStatusError(
    response.statusCode ?? 0,
    null,
    parseRetryAfter(response.headers.value('retry-after')),
  );
}

SinewException _statusException(
  String module,
  String function,
  HttpStatusError error,
  Object cause,
) {
  final text = error.errorBody?.message;
  final server = text != null && text.trim().isNotEmpty
      ? ServerMessage(text)
      : null;
  final fields = error.errorBody?.fieldErrors;
  final status = error.status;
  if ((status == 400 || status == 422) && fields != null && fields.isNotEmpty) {
    return ValidationException(
      module,
      _repository,
      function,
      fieldErrors: fields,
      message: server ?? _validation,
      cause: cause,
    );
  }
  return switch (status) {
    401 =>
      server == null
          ? UnauthorizedException(module, _repository, function, cause: cause)
          : UnauthorizedException(
              module,
              _repository,
              function,
              message: server,
              cause: cause,
            ),
    403 =>
      server == null
          ? ForbiddenException(module, _repository, function, cause: cause)
          : ForbiddenException(
              module,
              _repository,
              function,
              message: server,
              cause: cause,
            ),
    404 =>
      server == null
          ? NotFoundException(module, _repository, function, cause: cause)
          : NotFoundException(
              module,
              _repository,
              function,
              message: server,
              cause: cause,
            ),
    409 =>
      server == null
          ? ConflictException(module, _repository, function, cause: cause)
          : ConflictException(
              module,
              _repository,
              function,
              message: server,
              cause: cause,
            ),
    429 => RateLimitedException(
      module,
      _repository,
      function,
      retryAfter: error.retryAfter,
      message: server,
      cause: cause,
    ),
    503 || 504 =>
      server == null
          ? ServiceUnavailableException(
              module,
              _repository,
              function,
              status: status,
              cause: cause,
            )
          : ServiceUnavailableException(
              module,
              _repository,
              function,
              status: status,
              message: server,
              cause: cause,
            ),
    >= 500 && < 600 =>
      server == null
          ? ServerException(
              module,
              _repository,
              function,
              status: status,
              cause: cause,
            )
          : ServerException(
              module,
              _repository,
              function,
              status: status,
              message: server,
              cause: cause,
            ),
    _ =>
      server == null
          ? UndefinedErrorResponseException(
              module,
              _repository,
              function,
              status: status,
              cause: cause,
            )
          : ApiErrorException(
              module,
              _repository,
              function,
              message: server,
              cause: cause,
            ),
  };
}
