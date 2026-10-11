import 'exception.dart';

/// What every guard, repository and use case returns.
///
/// The failure is always a typed [SinewException], guaranteed by the guards,
/// and a success carries the backend's message, if it sent one. Consume it
/// with [when] or [fold], never by switching on [Success] and [Failure].
sealed class Result<T> {
  const Result();

  /// A success. Only `processApiCall` sets [message], from the envelope.
  const factory Result.success(T data, {String message}) = Success<T>;

  /// A failure, with where it happened.
  const factory Result.failure(SinewException error, [StackTrace? stackTrace]) =
      Failure<T>;

  /// Runs the branch for this result.
  R when<R>({
    required R Function(T data, String message) success,
    required R Function(SinewException error, StackTrace? stackTrace) failure,
  });

  /// Runs the branch for this result, without the message and stack trace.
  R fold<R>(
    R Function(T data) onSuccess,
    R Function(SinewException error) onFailure,
  ) => when(
    success: (data, _) => onSuccess(data),
    failure: (error, _) => onFailure(error),
  );

  /// Maps the data and keeps the message; a failure passes through.
  Result<R> transform<R>(R Function(T data) map);

  /// The data, or throws the failure's [SinewException] with its stack trace,
  /// so a use case can read results in a straight line.
  T requireData();
}

/// A successful result.
final class Success<T> extends Result<T> {
  /// Creates a success.
  const Success(this.data, {this.message = ''});

  /// The data.
  final T data;

  /// The backend's success text, or `''`.
  final String message;

  @override
  R when<R>({
    required R Function(T data, String message) success,
    required R Function(SinewException error, StackTrace? stackTrace) failure,
  }) => success(data, message);

  @override
  Result<R> transform<R>(R Function(T data) map) =>
      Success(map(data), message: message);

  @override
  T requireData() => data;

  @override
  bool operator ==(Object other) =>
      other is Success && other.data == data && other.message == message;

  @override
  int get hashCode => Object.hash(data, message);

  @override
  String toString() => 'Success($data${message.isEmpty ? '' : ', $message'})';
}

/// A failed result.
final class Failure<T> extends Result<T> {
  /// Creates a failure.
  const Failure(this.error, [this.stackTrace]);

  /// The failure.
  final SinewException error;

  /// Where the failure happened.
  final StackTrace? stackTrace;

  @override
  R when<R>({
    required R Function(T data, String message) success,
    required R Function(SinewException error, StackTrace? stackTrace) failure,
  }) => failure(error, stackTrace);

  @override
  Result<R> transform<R>(R Function(T data) map) => Failure(error, stackTrace);

  @override
  T requireData() {
    final trace = stackTrace;
    if (trace != null) Error.throwWithStackTrace(error, trace);
    throw error;
  }

  @override
  bool operator ==(Object other) =>
      other is Failure && identical(other.error, error);

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Failure(${error.code})';
}
