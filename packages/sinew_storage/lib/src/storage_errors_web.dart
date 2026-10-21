import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The browser out of space for this origin.
bool isPlatformStorageFull(Object error) =>
    _jsErrorName(error) == 'QuotaExceededError';

/// A browser storage error (from `localStorage` or IndexedDB), as opposed to
/// a bug's `TypeError`.
bool isPlatformStorageError(Object error) =>
    _storageErrorNames.contains(_jsErrorName(error));

const _storageErrorNames = {
  'QuotaExceededError',
  'SecurityError',
  'InvalidStateError',
  'UnknownError',
  'NotReadableError',
  'DataError',
};

/// The `name` of the JavaScript error [error] is, if it's one.
String? _jsErrorName(Object error) {
  try {
    final name = (error as JSObject)['name'];
    return name.isA<JSString>() ? (name as JSString).toDart : null;
  } catch (_) {
    return null; // a Dart object, not a JavaScript error
  }
}
