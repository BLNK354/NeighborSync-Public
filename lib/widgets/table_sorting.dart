/// Shared sorting and layout for the officer data tables.
///
///   * [TableSortState] adds sortable columns to a screen's State.
///   * [fullWidthTable] makes a DataTable fill the width.
library;

import 'package:flutter/material.dart';

/// Priority order (urgent first) for [TableSortState.rankedKey].
const kPriorityRank = <String, int>{
  'urgent': 0,
  'critical': 0,
  'high': 1,
  'medium': 2,
  'normal': 2,
  'low': 3,
};

/// Status order: open items first, closed last. Used by
/// [TableSortState.rankedKey].
const kStatusRank = <String, int>{
  // open / needs action
  'submitted': 0,
  'pending': 0,
  'reported': 0,
  'open': 0,
  'draft': 0,
  'unpaid': 0,
  'under_review': 1,
  'pending_verification': 1,
  'noticed': 1,
  'contested': 1,
  'in_progress': 2,
  'partial': 2,
  'active': 2,
  'approved': 3,
  'upheld': 3,
  'verified': 3,
  // closed / terminal
  'paid': 4,
  'resolved': 4,
  'completed': 4,
  'waived': 5,
  'dismissed': 5,
  'rejected': 5,
  'cancelled': 5,
  'expired': 5,
  'inactive': 5,
  'refunded': 5,
};

/// Sort value that always lands last in ascending order. Use for empty
/// placeholders like "Unassigned".
const String kSortsLast = '￿';

/// Mix into a screen's [State] to get sortable columns.
///
/// Example:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with SafeSetState<MyScreen>, TableSortState {
///   @override
///   Comparable<Object> sortKeyFor(Map<String, dynamic> row, int col) =>
///       switch (col) {
///         0 => text(row['name']),
///         1 => rankedKey(row['priority'], kPriorityRank),
///         _ => '',
///       };
/// }
/// ```
/// then in build: `sortColumnIndex: sortColumn`, `sortAscending: sortAsc`,
/// each `DataColumn(..., onSort: onSort)`, and `sortRows(myFilteredRows)`.
mixin TableSortState<T extends StatefulWidget> on State<T> {
  /// Column being sorted, or null for the loaded order.
  int? sortColumn;
  bool sortAsc = true;

  /// Sort value for [row] under column [col]. Implement per screen.
  Comparable<Object> sortKeyFor(Map<String, dynamic> row, int col);

  /// Case-insensitive text key. Empty values sort last rather than first.
  Comparable<Object> text(Object? v, {bool emptyLast = true}) {
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s.isEmpty && emptyLast) return kSortsLast;
    return s;
  }

  /// Key for a value with a meaningful order (see [kPriorityRank],
  /// [kStatusRank]). Unknown values sort after all known ones.
  Comparable<Object> rankedKey(Object? v, Map<String, int> rank) =>
      rank[(v ?? '').toString().trim().toLowerCase()] ?? 999;

  /// Numeric key. Non-numeric or missing values sort last ascending.
  Comparable<Object> number(Object? v) =>
      num.tryParse((v ?? '').toString()) ?? double.infinity;

  /// Date key parsed from an ISO string. Missing dates sort last ascending.
  Comparable<Object> date(Object? v) =>
      DateTime.tryParse((v ?? '').toString()) ?? DateTime(9999);

  /// Pass as each `DataColumn`'s `onSort`.
  void onSort(int col, bool asc) => setState(() {
        sortColumn = col;
        sortAsc = asc;
      });

  /// Order used before a column is clicked. Null keeps the loaded order.
  int Function(Map<String, dynamic> a, Map<String, dynamic> b)? get defaultOrder => null;

  /// Applies the current sort. Always returns a copy; the input list is
  /// never reordered.
  List<Map<String, dynamic>> sortRows(List<Map<String, dynamic>> rows) {
    final col = sortColumn;
    if (col == null) {
      final d = defaultOrder;
      if (d == null) return rows;
      return List<Map<String, dynamic>>.from(rows)..sort(d);
    }
    final out = List<Map<String, dynamic>>.from(rows);
    out.sort((a, b) {
      final r = Comparable.compare(sortKeyFor(a, col), sortKeyFor(b, col));
      return sortAsc ? r : -r;
    });
    return out;
  }
}

/// Wraps a [DataTable] so it fills the width and scrolls sideways when too
/// narrow. [footer] (usually the page switcher) sits under the table in the
/// same vertical scroll.
Widget fullWidthTable(Widget table, {Widget? footer}) {
  return LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: table,
            ),
          ),
          if (footer != null) footer,
        ],
      ),
    ),
  );
}
