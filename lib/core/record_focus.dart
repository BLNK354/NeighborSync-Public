import 'dart:async';
import 'package:flutter/material.dart';

/// Remembers which record a notification points to. The bell stores the id
/// here before opening the list; the list then clears filters, goes to the
/// record and highlights it for a few seconds.
class RecordFocus {
  RecordFocus._();

  static ({String table, Object id, DateTime at})? _pending;

  /// Called by the bell just before it opens the page.
  static void request(String table, Object id) =>
      _pending = (table: table, id: id, at: DateTime.now());

  /// The id waiting for [table], used once. Requests older than 20 seconds
  /// are ignored so a stale alert can't highlight a row later.
  static Object? take(String table) {
    final p = _pending;
    if (p == null || p.table != table) return null;
    _pending = null;
    if (DateTime.now().difference(p.at) > const Duration(seconds: 20)) return null;
    return p.id;
  }
}

/// Soft yellow used to highlight the focused row.
const kFocusRowColor = Color(0xFFFFF1B8);

/// Mixed into a list screen's State to receive [RecordFocus].
mixin RecordFocusTarget<T extends StatefulWidget> on State<T> {
  Object? _focusedId;
  Timer? _focusTimer;

  /// Call right after the screen's rows have loaded.
  ///
  /// [clearFilters] puts the list back to "all", so the record cannot be
  /// filtered out of view. [ordered] returns the rows in the order the
  /// table draws them, and [setPage] turns to the page holding the record.
  void takeRecordFocus(
    String table, {
    required VoidCallback clearFilters,
    required List<Map<String, dynamic>> Function() ordered,
    required void Function(int page) setPage,
  }) {
    final id = RecordFocus.take(table);
    if (id == null || !mounted) return;
    setState(() {
      clearFilters();
      final list = ordered();
      final i = list.indexWhere((r) => '${r['id']}' == '$id');
      if (i < 0) return; // not visible to this officer, or outside the loaded page
      // [pinFocused] moves the record to the top of page 1.
      setPage(1);
      _focusedId = list[i]['id'];
    });
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _focusedId = null);
    });
  }

  /// [rows] with the highlighted record moved to the front while the
  /// highlight lasts. Wrap the list a table pages through.
  List<Map<String, dynamic>> pinFocused(List<Map<String, dynamic>> rows) {
    if (_focusedId == null) return rows;
    final i = rows.indexWhere(isFocusedRow);
    if (i <= 0) return rows;
    return [rows[i], ...rows.sublist(0, i), ...rows.sublist(i + 1)];
  }

  bool isFocusedRow(Map<String, dynamic> r) =>
      _focusedId != null && '${r['id']}' == '$_focusedId';

  /// For `DataRow(color: ...)`.
  WidgetStateProperty<Color?>? focusRowColor(Map<String, dynamic> r) =>
      isFocusedRow(r) ? const WidgetStatePropertyAll(kFocusRowColor) : null;

  @override
  void dispose() {
    _focusTimer?.cancel();
    super.dispose();
  }
}
