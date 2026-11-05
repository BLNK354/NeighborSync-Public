import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_database.g.dart';

/// One local cache for every table: stores the source table, the row id
/// and the row as JSON.
class CachedRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceTable => text()(); // e.g. 'gate_passes', 'complaints'
  TextColumn get recordId => text()(); // the Supabase row's uuid
  TextColumn get dataJson => text()(); // the row, json-encoded
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {sourceTable, recordId},
      ];
}

/// Changes made offline, waiting to be sent to Supabase in order. Sent items
/// are marked synced; failed ones stay unsynced with errorMessage set.
class SyncQueueItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceTable => text()();
  TextColumn get operation => text()(); // 'insert' | 'update' | 'delete'
  TextColumn get recordId => text().nullable()(); // null for inserts made offline (no server id yet)
  TextColumn get payloadJson => text()(); // the fields to write, json-encoded
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  TextColumn get errorMessage => text().nullable()();
}

@DriftDatabase(tables: [CachedRecords, SyncQueueItems])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase._internal() : super(_openConnection());

  /// The single shared connection; don't open the local store twice.
  static final LocalDatabase instance = LocalDatabase._internal();

  // Bump this and add a MigrationStrategy step whenever a table changes shape.
  @override
  int get schemaVersion => 1;
}

/// Opens the local database: a sqlite file on desktop and mobile, sqlite3.wasm on web.
QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'neighborsync_offline',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
