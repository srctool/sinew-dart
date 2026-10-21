import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// An in-memory SQLite database.
QueryExecutor memoryExecutor() => NativeDatabase.memory();
