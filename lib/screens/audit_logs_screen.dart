import 'dart:convert';

import 'package:flutter/material.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/admin_shell.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';
import '../core/local_time.dart';

/// Read-only list of audit events for officers, with filters and a detail
/// dialog. Rows are written only by database triggers, never by the app.
/// Meant for audit_officer, hoa_president and super_admin, not the
/// secretary or treasurer.
class AdminAuditLogsScreen extends StatefulWidget {
  const AdminAuditLogsScreen({super.key});

  @override
  State<AdminAuditLogsScreen> createState() => _AdminAuditLogsScreenState();
}

class _AdminAuditLogsScreenState extends State<AdminAuditLogsScreen>
    with SafeSetState<AdminAuditLogsScreen>, TableSortState {
  // Current page, starting at 1.
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _severityFilter = 'all';

  /// The Today card's filter.
  bool _todayOnly = false;
  String _moduleFilter = 'all';
  String _actionFilter = 'all';

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads the latest 500 events, newest first.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetches the actor's role as well as their name.
      // audit_logs has one FK to users, so the bare embed is unambiguous.
      final data = await SupabaseService.instance.client
          .from('audit_logs')
          .select('*, actor:user_id(first_name, last_name, email, roles(name))')
          .order('created_at', ascending: false)
          .limit(500);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  /// True if the event happened today in local time (not UTC).
  bool _isToday(Map<String, dynamic> r) => isToday(r['created_at']);

  int get _total => _rows.length;
  int get _critical => _rows.where((r) => r['severity'] == 'critical').length;
  int get _warnings => _rows.where((r) => r['severity'] == 'warning').length;
  int get _today => _rows.where(_isToday).length;

  /// Rows left after the severity, today, module and action filters.
  List<Map<String, dynamic>> get _visible {
    var rows = _rows;
    if (_severityFilter != 'all') {
      rows = rows.where((r) => r['severity'] == _severityFilter).toList();
    }
    if (_todayOnly) rows = rows.where(_isToday).toList();
    if (_moduleFilter != 'all') {
      rows = rows.where((r) => r['module'] == _moduleFilter).toList();
    }
    if (_actionFilter != 'all') {
      rows = rows.where((r) => r['action'] == _actionFilter).toList();
    }
    return rows;
  }

  /// Sorted unique values of [key] in the loaded rows, for the filter menus.
  List<String> _distinct(String key) {
    final s = _rows.map((r) => (r[key] ?? '').toString()).where((v) => v.isNotEmpty).toSet().toList()..sort();
    return s;
  }

  /// One-line summary of what changed, like "priority: medium → urgent".
  /// Names only the fields when more than three changed; the detail dialog
  /// shows the full data.
  String _changeSummary(Map<String, dynamic> r) {
    Map<String, dynamic> parse(Object? v) {
      if (v == null) return {};
      try {
        final d = jsonDecode(v.toString());
        return d is Map<String, dynamic> ? d : {};
      } catch (_) {
        return {};
      }
    }

    final before = parse(r['old_values']);
    final after = parse(r['new_values']);
    final action = (r['action'] ?? '').toString();

    if (action == 'create') {
      return before.isEmpty && after.isNotEmpty ? 'record created' : '';
    }
    if (action == 'delete') return 'record deleted';

    // View, download and sign-in events have no before/after data.
    if (before.isEmpty) {
      final detail = after['detail'];
      return detail == null ? '' : detail.toString();
    }

    String show(Object? v) {
      if (v == null) return 'empty';
      final s = v.toString();
      return s.isEmpty ? 'empty' : (s.length > 24 ? '${s.substring(0, 24)}...' : s);
    }

    final keys = before.keys.toList();
    if (keys.length == 1) {
      final k = keys.first;
      return '$k: ${show(before[k])} → ${show(after[k])}';
    }
    if (keys.length <= 3) {
      return keys.map((k) => '$k: ${show(before[k])} → ${show(after[k])}').join(', ');
    }
    return '${keys.length} fields: ${keys.take(3).join(', ')}...';
  }

  /// The actor's role as readable text, or "System" if there is none.
  String _role(Map<String, dynamic>? actor) {
    final r = (actor?['roles'] as Map<String, dynamic>?)?['name'];
    return r == null ? 'System' : titleCase(r.toString().replaceAll('_', ' '));
  }

  /// The actor's full name, falling back to email, then "System".
  String _name(Map<String, dynamic>? p) {
    if (p == null) return 'System';
    final n = [p['first_name'], p['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
    return n.isEmpty ? (p['email'] ?? 'System').toString() : n;
  }

  String _time(String? iso) {
    // created_at is UTC; show it in the reader's local time.
    final t = localTime(iso);
    if (t == null) return '—';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final period = t.hour >= 12 ? 'PM' : 'AM';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
  }

  /// Opens a dialog with all details of one event, including raw before/after data.
  void _showDetail(Map<String, dynamic> r) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text((r['action'] ?? 'Event').toString()),
        // Max width lets the dialog shrink on narrow screens.
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Actor', _name(r['actor'] as Map<String, dynamic>?)),
                _detailRow('Role', _role(r['actor'] as Map<String, dynamic>?)),
                _detailRow('Module', (r['module'] ?? '—').toString()),
                _detailRow('Record', '${r['resource'] ?? '—'}'
                    '${r['resource_id'] == null ? '' : ' (#${r['resource_id']})'}'),
                _detailRow('Phase', (r['phase'] ?? 'All phases').toString()),
                _detailRow('Severity', (r['severity'] ?? '—').toString()),
                _detailRow('When', _time(r['created_at']?.toString())),
                if ((r['old_values'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Before', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SelectableText((r['old_values']).toString(), style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                ],
                if ((r['new_values'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('After', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SelectableText((r['new_values']).toString(), style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  /// One label and value line in the detail dialog.
  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary))),
        ],
      ),
    );
  }

  /// Column order: 0 When, 1 Who, 2 Role, 3 Action, 4 Module, 5 Record,
  /// 6 What changed (not sortable), 7 Severity. Must match the table columns.
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> r, int col) {
    switch (col) {
      case 0:
        return date(r['created_at']);
      case 1:
        return text(_name(r['actor'] as Map<String, dynamic>?));
      case 2:
        return text(_role(r['actor'] as Map<String, dynamic>?));
      case 3:
        return text(r['action']);
      case 4:
        return text(r['module']);
      case 5:
        return text(r['resource']);
      case 7:
        return rankedKey(r['severity'], kPriorityRank);
      default:
        return '';
    }
  }

  /// Phone layout: one card per event, with the change summary on its own line.
  Widget _cardList(List<Map<String, dynamic>> rows) {
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = sortRows(rows)[i];
        final change = _changeSummary(r);
        return InkWell(
          onTap: () => _showDetail(r),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${titleCase((r['action'] ?? '').toString().replaceAll('_', ' '))}'
                        ' · ${titleCase((r['module'] ?? '').toString().replaceAll('_', ' '))}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                    StatusBadge((r['severity'] ?? 'info').toString()),
                  ],
                ),
                if ((r['resource'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text((r['resource']).toString(),
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
                if (change.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(change, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                ],
                const SizedBox(height: 8),
                Text(
                  '${_name(r['actor'] as Map<String, dynamic>?)} '
                  '(${_role(r['actor'] as Map<String, dynamic>?)}) · '
                  '${_time(r['created_at']?.toString())}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Audit Logs',
      activeItem: 'Audit Logs',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Filters by severity, module and action. There is no
                      // search box; global search does not cover audit logs.
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _filterMenu(
                            label: 'Severity',
                            value: _severityFilter,
                            options: const ['info', 'warning', 'critical'],
                            onPick: (v) => setState(() => _severityFilter = v),
                          ),
                          _filterMenu(
                            label: 'Module',
                            value: _moduleFilter,
                            options: _distinct('module'),
                            onPick: (v) => setState(() => _moduleFilter = v),
                          ),
                          _filterMenu(
                            label: 'Action',
                            value: _actionFilter,
                            options: _distinct('action'),
                            onPick: (v) => setState(() => _actionFilter = v),
                          ),
                          if (_severityFilter != 'all' || _moduleFilter != 'all' || _actionFilter != 'all' || _todayOnly)
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _todayOnly = false;
                                _severityFilter = 'all';
                                _moduleFilter = 'all';
                                _actionFilter = 'all';
                              }),
                              icon: const Icon(Icons.close, size: 15),
                              label: Text('Clear (${_visible.length} of ${_rows.length})'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      responsiveStatCards((w) => [
                        DashboardStatCard(icon: Icons.history_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Total Events', value: '$_total', width: w, hint: 'Show all', onTap: () => setState(() { _severityFilter = 'all'; _moduleFilter = 'all'; _actionFilter = 'all'; _todayOnly = false; _page = 1; })),
                        DashboardStatCard(icon: Icons.error_outline, iconBg: const Color(0xFFFBE4E4), label: 'Critical', value: '$_critical', width: w, selected: _severityFilter == 'critical', onTap: () => setState(() { _severityFilter = _severityFilter == 'critical' ? 'all' : 'critical'; _page = 1; })),
                        DashboardStatCard(icon: Icons.warning_amber_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Warnings', value: '$_warnings', width: w, selected: _severityFilter == 'warning', onTap: () => setState(() { _severityFilter = _severityFilter == 'warning' ? 'all' : 'warning'; _page = 1; })),
                        DashboardStatCard(icon: Icons.today_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Today', value: '$_today', width: w, selected: _todayOnly, onTap: () => setState(() { _todayOnly = !_todayOnly; _page = 1; })),
                      ]),
                      const SizedBox(height: 20),
                      Expanded(child: _buildTable()),
                    ],
                  ),
                ),
    );
  }

  /// A dropdown button that picks one filter value, or "all".
  Widget _filterMenu({
    required String label,
    required String value,
    required List<String> options,
    required void Function(String) onPick,
  }) {
    return PopupMenuButton<String>(
      onSelected: onPick,
      itemBuilder: (context) => [
        PopupMenuItem(value: 'all', child: Text('All ${label.toLowerCase()}s')),
        for (final o in options)
          PopupMenuItem(value: o, child: Text(titleCase(o.replaceAll('_', ' ')))),
      ],
      child: OutlinedButton.icon(
        // Null so the button only looks like a button; PopupMenuButton handles the tap.
        onPressed: null,
        icon: const Icon(Icons.expand_more, size: 16),
        label: Text(value == 'all' ? label : titleCase(value.replaceAll('_', ' '))),
      ),
    );
  }

  /// The events table on wide screens, or cards on phones.
  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return const Center(child: Text('No matching events.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    }
    // Too many columns for a phone, so use cards below 900px.
    if (MediaQuery.of(context).size.width < 900) return _cardList(rows);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: fullWidthTable(
            footer: pagerFor(rows.length, _page, (p) => setState(() => _page = p)),
            
        DataTable(
            showCheckboxColumn: false,
            sortColumnIndex: sortColumn,
            sortAscending: sortAsc,
            columnSpacing: 28,
            headingRowHeight: 40,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 56,
            headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
            dataTextStyle: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            columns: [
              DataColumn(label: const Text('WHEN'), onSort: onSort),
              DataColumn(label: const Text('WHO'), onSort: onSort),
              DataColumn(label: const Text('ROLE'), onSort: onSort),
              DataColumn(label: const Text('ACTION'), onSort: onSort),
              DataColumn(label: const Text('MODULE'), onSort: onSort),
              DataColumn(label: const Text('RECORD'), onSort: onSort),
              const DataColumn(label: Text('WHAT CHANGED')),
              DataColumn(label: const Text('SEVERITY'), onSort: onSort),
            ],
            rows: [
              for (final r in pageSlice(sortRows(rows), _page))
                DataRow(
                  onSelectChanged: (_) => _showDetail(r),
                  cells: [
                    DataCell(Text(_time(r['created_at']?.toString()))),
                    DataCell(Text(_name(r['actor'] as Map<String, dynamic>?))),
                    DataCell(Text(_role(r['actor'] as Map<String, dynamic>?),
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                    DataCell(Text(titleCase((r['action'] ?? '').toString().replaceAll('_', ' ')))),
                    DataCell(Text(titleCase((r['module'] ?? '—').toString().replaceAll('_', ' ')))),
                    // The reference number residents quote, not the numeric id.
                    DataCell(Text((r['resource'] ?? '—').toString(),
                        overflow: TextOverflow.ellipsis)),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          _changeSummary(r),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ),
                    ),
                    DataCell(StatusBadge((r['severity'] ?? 'info').toString())),
                  ],
                ),
            ],
          ),
      ),
    );
  }
}
