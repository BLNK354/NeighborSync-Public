import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_database.dart';

/// Offline read/write helpers used by CrudService. Only [replaySyncQueue]
/// talks to Supabase; the rest use the local database.
class OfflineRepository {
  OfflineRepository._();
  static final OfflineRepository instance = OfflineRepository._();

  LocalDatabase get _db => LocalDatabase.instance;

  /// Saves [rows] of [table] in the local cache. Errors are ignored so a
  /// cache failure never breaks the screen.
  Future<void> cacheRows(String table, List<Map<String, dynamic>> rows) async {
    try {
      await _db.batch((batch) {
        for (final row in rows) {
          final id = row['id']?.toString();
          if (id == null) continue;
          batch.insert(
            _db.cachedRecords,
            CachedRecordsCompanion.insert(
              sourceTable: table,
              recordId: id,
              dataJson: jsonEncode(row),
            ),
            onConflict: drift.DoUpdate(
              (old) => CachedRecordsCompanion(
                dataJson: drift.Value(jsonEncode(row)),
                cachedAt: drift.Value(DateTime.now()),
              ),
              target: [_db.cachedRecords.sourceTable, _db.cachedRecords.recordId],
            ),
          );
        }
      });
    } catch (_) {
      // Ignored on purpose: the cache is optional.
    }
  }

  /// Rows previously cached for [table] via [cacheRows], newest first.
  Future<List<Map<String, dynamic>>> cachedRows(String table) async {
    final query = _db.select(_db.cachedRecords)
      ..where((t) => t.sourceTable.equals(table))
      ..orderBy([(t) => drift.OrderingTerm(expression: t.cachedAt, mode: drift.OrderingMode.desc)]);
    final rows = await query.get();
    return rows.map((r) => jsonDecode(r.dataJson) as Map<String, dynamic>).toList();
  }

  /// Queues a create, update or delete to send to Supabase later. For
  /// create and update it also saves a local copy so the change shows now.
  Future<void> queueWrite({
    required String table,
    required String operation, // 'insert' | 'update' | 'delete'
    String? recordId,
    required Map<String, dynamic> payload,
  }) async {
    await _db.into(_db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            sourceTable: table,
            operation: operation,
            recordId: drift.Value(recordId),
            payloadJson: jsonEncode(payload),
          ),
        );

    if (operation != 'delete') {
      // Temporary id for rows made offline; the real one arrives on sync.
      final localId = recordId ?? 'offline-${DateTime.now().microsecondsSinceEpoch}';
      final merged = {...payload, 'id': localId, '_pending_sync': true};
      await cacheRows(table, [merged]);
    }
  }

  /// Unsynced items, oldest first, so they replay in the order made.
  Future<List<SyncQueueItem>> pendingItems() {
    final query = _db.select(_db.syncQueueItems)
      ..where((t) => t.synced.equals(false))
      ..orderBy([(t) => drift.OrderingTerm(expression: t.createdAt)]);
    return query.get();
  }

  /// Sends every queued write to Supabase in order. A failure is saved on
  /// that item and the rest still run. Called when the app is back online.
  Future<void> replaySyncQueue(SupabaseClient client) async {
    final items = await pendingItems();
    for (final item in items) {
      try {
        final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;
        switch (item.operation) {
          case 'insert':
            payload.remove('id'); // let Supabase assign the real id
            await client.from(item.sourceTable).insert(payload);
            break;
          case 'update':
            if (item.recordId == null) throw StateError('update queued with no record id');
            await client.from(item.sourceTable).update(payload).eq('id', item.recordId!);
            break;
          case 'delete':
            if (item.recordId == null) throw StateError('delete queued with no record id');
            await client.from(item.sourceTable).delete().eq('id', item.recordId!);
            break;
        }
        await (_db.update(_db.syncQueueItems)..where((t) => t.id.equals(item.id))).write(
          const SyncQueueItemsCompanion(synced: drift.Value(true)),
        );
      } catch (e) {
        await (_db.update(_db.syncQueueItems)..where((t) => t.id.equals(item.id))).write(
          SyncQueueItemsCompanion(errorMessage: drift.Value(e.toString())),
        );
        // Carry on so one failure doesn't block later items.
      }
    }
  }
}
