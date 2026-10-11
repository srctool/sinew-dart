import 'package:riverpod/riverpod.dart';
import 'package:sinew_exception/sinew_exception.dart';
import 'package:sinew_models/sinew_models.dart';

/// Where an `AsyncNotifier` page meets Sinew code.
extension AsyncToViewState<T> on AsyncValue<T> {
  /// Loading → `Loading`, `AsyncData` → `Done`, `AsyncError` → `Failed`,
  /// each keeping the previous value when there is one.
  ///
  /// Loading is read from `isLoading`, not the type: Riverpod represents a
  /// refresh as an `AsyncData`, and a retry as an `AsyncError`, still
  /// loading. Both become `Loading` with the previous value.
  ///
  /// An error that isn't a [SinewException] becomes an
  /// [UnexpectedException] coded with [module], the view-model layer and
  /// [function], with the error as its cause. It isn't reported here: this
  /// runs on every build.
  ViewState<T> toViewState(String module, String function) => switch (this) {
    _ when isLoading => Loading(value),
    AsyncData(:final value) => Done(value),
    AsyncError(:final error, :final stackTrace) => Failed(
      error is SinewException
          ? error
          : UnexpectedException(
              module,
              ExceptionLayer.viewModel,
              function,
              cause: error,
            ),
      data: value,
      stackTrace: stackTrace,
    ),
    AsyncLoading() => Loading(value),
  };
}

/// Where Sinew state meets `AsyncValue` code.
extension ViewStateToAsync<T> on ViewState<T> {
  /// `Loading` → `AsyncLoading`, `Done` → `AsyncData`, `Failed` →
  /// `AsyncError` with its stack trace, or an empty one.
  ///
  /// The previous data of `Loading` and `Failed` is dropped: Riverpod 3
  /// attaches previous values only internally, as a provider rebuilds.
  AsyncValue<T> toAsyncValue() => switch (this) {
    Loading() => AsyncLoading<T>(),
    Done(:final data) => AsyncData(data),
    Failed(:final error, :final stackTrace) => AsyncError<T>(
      error,
      stackTrace ?? StackTrace.empty,
    ),
  };
}
