import 'exception.dart';

/// What a page renders.
///
/// [Loading] and [Failed] can keep the previous data, so a reload doesn't
/// blank the screen. There's no idle state and no success message: one-time
/// reactions are effects, never state. Maps one-to-one onto Riverpod's
/// `AsyncValue`.
sealed class ViewState<T> {
  const ViewState();

  /// The data to render, from any state.
  T? get dataOrNull;

  /// Whether this is [Loading].
  bool get isLoading => this is Loading<T>;
}

/// Loading, optionally keeping the previous [data].
final class Loading<T> extends ViewState<T> {
  /// Creates a loading state.
  const Loading([this.data]);

  /// The previous data, if any.
  final T? data;

  @override
  T? get dataOrNull => data;

  @override
  bool operator ==(Object other) => other is Loading && other.data == data;

  @override
  int get hashCode => Object.hash(Loading, data);

  @override
  String toString() => 'Loading($data)';
}

/// Loaded. An empty list is still [Done].
final class Done<T> extends ViewState<T> {
  /// Creates a loaded state.
  const Done(this.data);

  /// The loaded data.
  final T data;

  @override
  T? get dataOrNull => data;

  @override
  bool operator ==(Object other) => other is Done && other.data == data;

  @override
  int get hashCode => Object.hash(Done, data);

  @override
  String toString() => 'Done($data)';
}

/// Failed. Keeps the [error], never pre-rendered text, so a language switch
/// re-renders it.
final class Failed<T> extends ViewState<T> {
  /// Creates a failed state.
  const Failed(this.error, {this.data, this.stackTrace});

  /// The failure.
  final SinewException error;

  /// The previous data, if any.
  final T? data;

  /// Where the failure happened.
  final StackTrace? stackTrace;

  @override
  T? get dataOrNull => data;

  @override
  bool operator ==(Object other) =>
      other is Failed && identical(other.error, error) && other.data == data;

  @override
  int get hashCode => Object.hash(error, data);

  @override
  String toString() => 'Failed(${error.code}, $data)';
}
