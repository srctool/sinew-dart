import 'package:drift/drift.dart';

/// No in-memory SQLite without FFI.
QueryExecutor memoryExecutor() =>
    throw UnsupportedError('the drift test runs on the VM');
