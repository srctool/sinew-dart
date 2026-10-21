import 'dart:io';

/// The device out of space: `ENOSPC` (errno 28) on Android, iOS, macOS and
/// Linux; `ERROR_HANDLE_DISK_FULL` (39) or `ERROR_DISK_FULL` (112) on Windows.
bool isPlatformStorageFull(Object error) =>
    error is FileSystemException &&
    switch (error.osError?.errorCode) {
      final int code =>
        Platform.isWindows ? code == 39 || code == 112 : code == 28,
      null => false,
    };

/// A file or socket-level I/O error.
bool isPlatformStorageError(Object error) => error is IOException;
