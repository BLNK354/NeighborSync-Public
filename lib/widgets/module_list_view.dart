import 'package:flutter/material.dart';
import 'pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/module_config.dart';
import '../core/refresh_bus.dart';
import '../services/crud_service.dart';
import '../theme/app_theme.dart';
import 'request_error_view.dart';
import 'module_form_dialog.dart';
import 'status_badge.dart';
import 'table_sorting.dart';
import '../core/safe_state.dart';

/// Generic list/table for any [ModuleConfig]: loading, create/edit/delete,
/// and empty/error states. Place it as the `child` of AdminShell or MemberShell.
///
/// Set [readOnly] to hide create/edit/delete. The allow...Override flags can
/// only narrow the module's own flags, never widen them. [extraFilters] adds
/// fixed filters (e.g. `{'user_id': myRowId}` for "My Bills").
class ModuleListView extends StatefulWidget {
  final ModuleConfig config;
  final bool readOnly;
  final bool? allowCreateOverride;
  final bool? allowEditOverride;
  final bool? allowDeleteOverride;
  final Map<String, dynamic>? extraFilters;

  const ModuleListView({
    super.key,
    required this.config,
    this.readOnly = false,
    this.allowCreateOverride,
    this.allowEditOverride,
    this.allowDeleteOverride,
    this.extraFilters,
  });

  @override
  State<ModuleListView> createState() => _ModuleListViewState();
}

class _ModuleListViewState extends State<ModuleListView> with SafeSetState<ModuleListView>, TableSortState {
  List<Map<String, dynamic>> _rows = [];
  // 1-based page; 10 rows a page (kPageSize).
  int _page = 1;

  /// Columns shown in the table, captured during build so [sortKeyFor] can
  /// map a column index back to the field it represents.
  List<FieldConfig> _sortableFields = const [];

  /// Default order for grouped lists: by group name, then by title, until
  /// a header is clicked. Null for ungrouped lists.
  @override
  int Function(Map<String, dynamic>, Map<String, dynamic>)? get defaultOrder {
    final keyOf = widget.config.groupKey;
    if (keyOf == null) return null;
    final title = widget.config.titleField;
    String low(Object? v) => (v ?? '').toString().trim().toLowerCase();
    return (a, b) {
      final g = low(keyOf(a)).compareTo(low(keyOf(b)));
      if (g != 0) return g;
      return low(a[title]).compareTo(low(b[title]));
    };
  }

  /// Sorts by the field behind the tapped column. Status and priority
  /// fields use their workflow rankings, so "high" sorts above "low".
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> row, int col) {
    if (col < 0 || col >= _sortableFields.length) return '';
    final f = _sortableFields[col];
    final raw = row[f.key];

    if (f.key == widget.config.statusField) return rankedKey(raw, kStatusRank);
    if (f.key == 'priority' || f.key == 'severity') {
      return rankedKey(raw, kPriorityRank);
    }
    switch (f.type) {
      case FieldType.number:
      case FieldType.decimal:
        return number(raw);
      case FieldType.date:
      case FieldType.dateTime:
        return date(raw);
      default:
        // Sort by shown text so reference fields sort by name, not id.
        return text(f.listDisplay(row));
    }
  }
  bool _loading = true;
  String? _error;
  Object? _errorObject;
  /// Search text passed to the query. Always empty; there is no search box here.
  final String _search = '';

  bool get _canCreate =>
      !widget.readOnly &&
      (widget.allowCreateOverride ?? widget.config.allowCreate);
  bool get _canEdit =>
      !widget.readOnly &&
      (widget.allowEditOverride ?? widget.config.allowEdit);
  bool get _canDelete =>
      !widget.readOnly &&
      (widget.allowDeleteOverride ?? widget.config.allowDelete);

  @override
  void initState() {
    super.initState();
    // Needed for pull-to-refresh and the super_admin phase switcher to reach this list.
    RefreshBus.bind(this, _load);
    _load();
  }

  @override
  void didUpdateWidget(covariant ModuleListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.key != widget.config.key) _load();
  }

  /// Fetches the rows and updates the loading/error state.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await CrudService.instance.list(
        widget.config,
        search: _search,
        extraFilters: widget.extraFilters,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _errorObject = e;
        _loading = false;
      });
    }
  }

  Future<void> _openForm({Map<String, dynamic>? initial}) async {
    final saved =
        await showModuleFormDialog(context, widget.config, initial: initial);
    if (saved == true) _load();
  }

  /// Whether the row's retire button shows: the module has one, the caller
  /// can edit, and the row is not already retired.
  bool _canRetire(Map<String, dynamic> row) {
    final a = widget.config.retireAction;
    if (a == null || !_canEdit) return false;
    return !a.doneValues.contains(row[a.field]?.toString());
  }

  Future<void> _confirmRetire(Map<String, dynamic> row) async {
    final a = widget.config.retireAction!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.confirmTitle),
        content: Text(a.confirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(a.label)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CrudService.instance
          .update(widget.config, row[widget.config.idField], {a.field: a.value});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text(
            'This will permanently delete this ${widget.config.label.toLowerCase()} record.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CrudService.instance.delete(widget.config, row[widget.config.idField]);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed. ${friendlyError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final listFields =
        widget.config.fields.where((f) => f.showInList).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
              ),
              if (_canCreate) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'New ${widget.config.label}',
                  child: FilledButton(
                    onPressed: () => _openForm(),
                    child: const Icon(Icons.add, size: 18),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildBody(listFields)),
        ],
      ),
    );
  }

  Widget _buildBody(List<FieldConfig> listFields) {
    // sortKeyFor() needs this to map a column index to its field.
    _sortableFields = listFields;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _errorObject == null
          ? RequestErrorView(
              kind: RequestErrorKind.server, detail: _error, onRetry: _load)
          : RequestErrorView.fromError(_errorObject!, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text('No ${widget.config.label.toLowerCase()} records yet.',
            style: TextStyle(fontSize: 13, color: AppColors.textSub)),
      );
    }

    // Grouped lists page by group so a group is never split across pages.
    final pages = widget.config.groupKey == null
        ? pageCountFor(_rows.length)
        : pageCountFor(_groups().length, size: _kGroupsPerPage);
    if (_page > pages) _page = pages;
    return Column(
      children: [
        Expanded(
          child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: fullWidthTable(
        DataTable(
            showCheckboxColumn: false,
            headingRowHeight: 40,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 52,
            columnSpacing: 28,
            sortColumnIndex: sortColumn,
            sortAscending: sortAsc,
            headingTextStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSub),
            dataTextStyle:
                TextStyle(fontSize: 12.5, color: AppColors.textMain),
            columns: [
              for (final f in listFields)
                DataColumn(label: Text(f.label), onSort: onSort),
              // Actions column: not sortable.
              if (_canEdit || _canDelete) const DataColumn(label: Text('')),
            ],
            rows: _tableRows(listFields),
          ),
      ),
          ),
        ),
        if (pages > 1)
          PaginationFooter(
            page: _page,
            pageCount: pages,
            onPageChanged: (p) => setState(() => _page = p),
          ),
      ],
    );
  }

  /// Groups shown per page in a grouped list.
  static const _kGroupsPerPage = 5;

  /// Every row, sorted, collected into groups. Groups keep the sorted order
  /// (insertion order), not alphabetical by key.
  List<MapEntry<String, List<Map<String, dynamic>>>> _groups() {
    final keyOf = widget.config.groupKey!;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in sortRows(_rows)) {
      groups.putIfAbsent(keyOf(row), () => []).add(row);
    }
    return groups.entries.toList();
  }

  /// Table rows for the current page, with a header row per group if grouped.
  List<DataRow> _tableRows(List<FieldConfig> listFields) {
    if (widget.config.groupKey == null) {
      // Sort everything first, then take the page.
      final sorted = pageSlice(sortRows(_rows), _page);
      return [for (final row in sorted) _dataRow(row, listFields)];
    }
    // Group everything first, then page by group.
    final out = <DataRow>[];
    for (final g in pageSlice(_groups(), _page, size: _kGroupsPerPage)) {
      out.add(_groupHeaderRow(g.key, g.value, listFields));
      for (final row in g.value) {
        out.add(_dataRow(row, listFields));
      }
    }
    return out;
  }

  /// A tinted group header row. DataTable cannot span cells, so the label
  /// sits in the first cell and the rest are blank.
  DataRow _groupHeaderRow(
      String key, List<Map<String, dynamic>> rows, List<FieldConfig> listFields) {
    final build = widget.config.groupHeader;
    final label = build == null ? key : build(key, rows);
    final columns = listFields.length + ((_canEdit || _canDelete) ? 1 : 0);
    return DataRow(
      color: WidgetStateProperty.all(AppColors.highlight),
      cells: [
        DataCell(Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
        for (var i = 1; i < columns; i++) const DataCell(SizedBox.shrink()),
      ],
    );
  }

  /// One record row with its edit, retire and delete buttons.
  DataRow _dataRow(Map<String, dynamic> row, List<FieldConfig> listFields) {
    return DataRow(cells: [
                  for (final f in listFields)
                    DataCell(
                      f.key == widget.config.statusField
                          ? StatusBadge(f.listDisplay(row))
                          : Text(f.listDisplay(row)),
                    ),
                  if (_canEdit || _canDelete)
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_canEdit)
                          IconButton(
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _openForm(initial: row),
                          ),
                        if (_canRetire(row))
                          IconButton(
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            tooltip: widget.config.retireAction!.tooltip,
                            icon: const Icon(Icons.do_not_disturb_on_outlined),
                            onPressed: () => _confirmRetire(row),
                          ),
                        if (_canDelete)
                          IconButton(
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent),
                            onPressed: () => _confirmDelete(row),
                          ),
                      ],
                    )),
    ]);
  }
}
