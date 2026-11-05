import 'dart:async';
import '../core/address_sort.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/module_config.dart';
import '../offline/connectivity_service.dart';
import '../offline/offline_repository.dart';
import 'supabase_service.dart';

/// Table-agnostic CRUD backend for the generic module screens.
///
/// Offline: when the device is offline or a call fails, list() returns the
/// local cache and create/update/delete are queued, then replayed once back
/// online (OfflineRepository.replaySyncQueue). Bespoke screens that run
/// their own queries are not covered.
class CrudService {
  CrudService._();
  static final CrudService instance = CrudService._();

  SupabaseClient get _client => SupabaseService.instance.client;
  OfflineRepository get _offline => OfflineRepository.instance;

  /// Column list for the query; joins roles when the module filters by role.
  String _selectString(ModuleConfig cfg) {
    if (cfg.selectOverride != null) return cfg.selectOverride!;
    if (cfg.roleFilter != null) return '*, roles!inner(name)';
    return '*';
  }

  /// Rows for a module, newest-first by its config; falls back to the
  /// local cache when offline or the call fails.
  Future<List<Map<String, dynamic>>> list(
    ModuleConfig cfg, {
    String? search,
    Map<String, dynamic>? extraFilters,
    int limit = 200,
  }) async {
    if (!ConnectivityService.instance.isOnline.value) {
      return _localList(cfg, search: search, extraFilters: extraFilters);
    }
    try {
      var query = _client.from(cfg.table).select(_selectString(cfg));

      if (cfg.roleFilter != null) {
        query = query.eq('roles.name', cfg.roleFilter as Object);
      }
      cfg.filterEq?.forEach((k, v) {
        query = query.eq(k, v as Object);
      });
      extraFilters?.forEach((k, v) {
        query = query.eq(k, v as Object);
      });
      if (search != null &&
          search.trim().isNotEmpty &&
          cfg.searchField != null) {
        query = query.ilike(cfg.searchField!, '%${search.trim()}%');
      }

      final data = await query
          .order(cfg.orderBy, ascending: !cfg.orderDescending)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(data as List);
      // Refresh the offline cache without waiting.
      unawaited(_offline.cacheRows(cfg.table, rows));
      return rows;
    } catch (_) {
      // Request failed: show cached rows instead of an error.
      return _localList(cfg, search: search, extraFilters: extraFilters);
    }
  }

  /// Cached rows with the same equality and search filters applied locally.
  Future<List<Map<String, dynamic>>> _localList(
    ModuleConfig cfg, {
    String? search,
    Map<String, dynamic>? extraFilters,
  }) async {
    var rows = await _offline.cachedRows(cfg.table);
    extraFilters?.forEach((k, v) {
      rows = rows.where((r) => r[k] == v).toList();
    });
    if (search != null && search.trim().isNotEmpty && cfg.searchField != null) {
      final needle = search.trim().toLowerCase();
      rows = rows.where((r) => (r[cfg.searchField!] ?? '').toString().toLowerCase().contains(needle)).toList();
    }
    return rows;
  }

  /// Inserts a row (queued if offline). Runs the module's AI classifier in
  /// the background when one is configured.
  Future<void> create(ModuleConfig cfg, Map<String, dynamic> data) async {
    if (!ConnectivityService.instance.isOnline.value) {
      await _offline.queueWrite(table: cfg.table, operation: 'insert', payload: data);
      return;
    }
    try {
      if (cfg.classifyFunctionName != null) {
        // Read back the new id for the classifier; these modules let the
        // inserting roles also SELECT.
        final inserted =
            await _client.from(cfg.table).insert(data).select(cfg.idField).single();
        unawaited(_classifyInBackground(cfg.classifyFunctionName!, inserted[cfg.idField]));
      } else {
        await _client.from(cfg.table).insert(data);
      }
    } on PostgrestException {
      // The server rejected it (data, RLS, constraint): show the error,
      // do not queue something that will keep failing.
      rethrow;
    } catch (e) {
      // Anything else looks like a connection problem: queue it.
      await _offline.queueWrite(table: cfg.table, operation: 'insert', payload: data);
    }
  }

  /// Updates one row by id (queued if offline) and records AI-override
  /// events for complaint priority and incident severity.
  Future<void> update(
    ModuleConfig cfg,
    dynamic id,
    Map<String, dynamic> data,
  ) async {
    if (!ConnectivityService.instance.isOnline.value) {
      await _offline.queueWrite(table: cfg.table, operation: 'update', recordId: id.toString(), payload: data);
      return;
    }
    try {
      await _client.from(cfg.table).update(data).eq(cfg.idField, id as Object);
      // Audit rows are written by the trg_zz_audit database trigger, not here.
      if (cfg.table == 'complaints' && data.containsKey('priority')) {
        unawaited(_logPriorityOverrideIfNeeded(id, data['priority'] as String?));
      }
      if (cfg.table == 'security_incidents' && data.containsKey('severity')) {
        unawaited(_logSeverityOverrideIfNeeded(id, data['severity'] as String?));
      }
    } on PostgrestException {
      rethrow;
    } catch (e) {
      await _offline.queueWrite(table: cfg.table, operation: 'update', recordId: id.toString(), payload: data);
    }
  }

  /// Deletes one row by id (queued if offline).
  Future<void> delete(ModuleConfig cfg, dynamic id) async {
    if (!ConnectivityService.instance.isOnline.value) {
      await _offline.queueWrite(table: cfg.table, operation: 'delete', recordId: id.toString(), payload: const {});
      return;
    }
    try {
      await _client.from(cfg.table).delete().eq(cfg.idField, id as Object);
      // The audit trigger logs the delete.
    } on PostgrestException {
      rethrow;
    } catch (e) {
      await _offline.queueWrite(table: cfg.table, operation: 'delete', recordId: id.toString(), payload: const {});
    }
  }

  /// Logs a "priority_override" audit event when an officer sets a
  /// complaint priority different from the classifier's suggestion.
  Future<void> _logPriorityOverrideIfNeeded(dynamic id, String? newPriority) async {
    if (newPriority == null) return;
    try {
      final row = await _client
          .from('complaints')
          .select('suggested_priority, classification_source')
          .eq('id', id as Object)
          .maybeSingle();
      final suggested = row?['suggested_priority'] as String?;
      // Not classified yet, or no disagreement: nothing to log.
      if (suggested == null || suggested == newPriority) return;
      // The actor comes from the JWT inside log_audit_action. Only the
      // client knows the change contradicts the suggestion, so this is
      // logged here rather than by the row trigger.
      await _client.rpc('log_audit_action', params: {
        'p_action': 'priority_override',
        'p_module': 'complaints',
        'p_resource_id': id is int ? id : int.tryParse(id.toString()),
        'p_detail': jsonEncode({
          'ai_suggested_priority': suggested,
          'officer_set_priority': newPriority,
          'classification_source': row?['classification_source'],
        }),
      });
    } catch (_) {
      // Best-effort.
    }
  }

  /// Same as the priority override, for incident severity.
  Future<void> _logSeverityOverrideIfNeeded(dynamic id, String? newSeverity) async {
    if (newSeverity == null) return;
    try {
      final row = await _client
          .from('security_incidents')
          .select('suggested_severity, classification_source')
          .eq('id', id as Object)
          .maybeSingle();
      final suggested = row?['suggested_severity'] as String?;
      // Not classified yet, or no disagreement: nothing to log.
      if (suggested == null || suggested == newSeverity) return;
      await _client.rpc('log_audit_action', params: {
        'p_action': 'severity_override',
        'p_module': 'security_incidents',
        'p_resource_id': id is int ? id : int.tryParse(id.toString()),
        'p_detail': jsonEncode({
          'ai_suggested_severity': suggested,
          'officer_set_severity': newSeverity,
          'classification_source': row?['classification_source'],
        }),
      });
    } catch (_) {
      // Best-effort.
    }
  }

  /// Asks the module's Edge Function to classify a new record. Errors are
  /// ignored; classification never blocks a save.
  Future<void> _classifyInBackground(String functionName, dynamic id) async {
    try {
      await _client.functions.invoke(functionName, body: {'id': id});
    } catch (_) {
      // Ignored on purpose.
    }
  }

  /// Dropdown options for a [FieldType.reference] field. Not cached, so
  /// the dropdown is empty while offline.
  Future<List<Map<String, dynamic>>> refOptions(
    FieldConfig field, {
    /// Current form values, so options can depend on other fields.
    Map<String, dynamic> values = const {},
  }) async {
    if (field.refTable == null) return const [];
    final cols = field.refSelectColumns ?? const ['id'];

    // A role filter computed from the form values wins over the static one.
    final dynamicRoles = field.refRoleFilterFrom?.call(values);
    if (dynamicRoles != null && dynamicRoles.isNotEmpty) {
      final data = await _client
          .from(field.refTable!)
          .select('${cols.join(', ')}, roles!inner(name)')
          .inFilter('roles.name', dynamicRoles)
          .eq('status', 'active')
          .limit(1000);
      return _sorted(field, data);
    }

    // Role-restricted picker: `roles!inner` drops other roles entirely, and
    // only active accounts are offered. The extra `roles` key is ignored by
    // refLabel().
    if (field.refRoleFilter != null && field.refRoleFilter!.isNotEmpty) {
      final data = await _client
          .from(field.refTable!)
          .select('${cols.join(', ')}, roles!inner(name)')
          .inFilter('roles.name', field.refRoleFilter!)
          .eq('status', 'active')
          .limit(1000);
      return _sorted(field, data);
    }

    // Active entries only, but keep the record's current value in the list
    // or editing it would blank the field.
    if (field.refActiveOnly) {
      // Parsed to int because or() takes a raw filter string.
      final current = int.tryParse(values[field.key]?.toString() ?? '');
      final query = _client.from(field.refTable!).select(cols.join(', '));
      final data = current == null
          ? await query.eq('is_active', true).limit(300)
          : await query.or('is_active.eq.true,id.eq.$current').limit(1000);
      return _sorted(field, data);
    }

    final data = await _client
        .from(field.refTable!)
        .select(cols.join(', '))
        .limit(1000);
    return _sorted(field, data);
  }

  /// Sorts picker rows: lots by block then lot number, people by name.
  List<Map<String, dynamic>> _sorted(FieldConfig field, dynamic data) {
    final rows = List<Map<String, dynamic>>.from(data as List);
    if (field.refTable == 'lots') {
      rows.sort(compareLotRows);
    } else if (field.refTable == 'users') {
      String name(Map<String, dynamic> u) =>
          '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim().toLowerCase();
      rows.sort((a, b) => name(a).compareTo(name(b)));
    }
    return rows;
  }
}
