// The web test build can't compile dart:ffi, so the native executor is
// imported only where there's FFI; the drift test itself runs on the VM.
export 'memory_executor_stub.dart'
    if (dart.library.ffi) 'memory_executor_native.dart';
