import 'package:flutter/material.dart';
import '../core/fetch_all.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/permissions.dart';
import '../core/module_registry.dart';
import '../widgets/module_detail_dialog.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Officer list of violations: stat cards (Open, Resolved, Repeat Offenders)
/// and a table. Severity comes from the violation type and shows "—" if none.
/// Shown as a tab inside CommunityConcernScreen.
class AdminCasesScreen extends StatefulWidget {
  const AdminCasesScreen({super.key});

  @override
  State<AdminCasesScreen> createState() => _AdminCasesScreenState();
}

class _AdminCasesScreenState extends State<AdminCasesScreen>
    with SafeSetState<AdminCasesScreen>, TableSortState {
  // Current page, starting at 1.
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  /// Whether this officer may add records; read-only roles must not see a
  /// create button the database would reject.
  bool _canCreate = false;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final perms = await SupabaseService.instance.getMyPermissions();
      final data = await fetchAllRows((from, to) => SupabaseService.instance.client
          .from('violations')
          .select('*, offender:reported_against(first_name, last_name), '
              'violation_type:violation_type_id(name, severity)')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(from, to));
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
        _canCreate = canPerform(perms, 'violations', 'create');
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

  int get _open => _rows
      .where((v) => !['resolved', 'dismissed'].contains(v['status']))
      .length;
  int get _resolved => _rows.where((v) => v['status'] == 'resolved').length;

  int get _repeatOffenders {
    final counts = <int, int>{};
    for (final v in _rows) {
      final id = v['reported_against'] as int?;
      if (id == null) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts.values.where((c) => c > 1).length;
  }

  /// Rows after the filter. 'open' and 'repeat' (someone named in more than
  /// one case) are set only by the stat cards.
  List<Map<String, dynamic>> get _visible {
    switch (_statusFilter) {
      case 'all':
        return _rows;
      case 'open':
        return _rows.where((v) => !['resolved', 'dismissed'].contains(v['status'])).toList();
      case 'repeat':
        final counts = <int, int>{};
        for (final v in _rows) {
          final id = v['reported_against'] as int?;
          if (id != null) counts[id] = (counts[id] ?? 0) + 1;
        }
        return _rows.where((v) => (counts[v['reported_against']] ?? 0) > 1).toList();
      default:
        return _rows.where((v) => v['status'] == _statusFilter).toList();
    }
  }

  void _tapCard(String v) => setState(() {
        _statusFilter = _statusFilter == v ? 'all' : v;
        _page = 1;
      });

  /// Opens a read-only card first; Edit shows only for those who may update.
  Future<void> _openDetail(Map<String, dynamic> r) async {
    final edit = await showModuleDetailDialog(
      context,
      cases,
      r,
      subtitle: [ (r['violation_number'] ?? '').toString(), 'Against: ${_name(r['offender'] as Map<String, dynamic>?)}' ]
          .where((s) => s.trim().isNotEmpty && !s.endsWith('—'))
          .join(' · '),
    );
    if (edit == true && mounted) await _openForm(r);
  }

  Future<void> _openForm([Map<String, dynamic>? initial]) async {
    final saved = await showModuleFormDialog(context, cases, initial: initial);
    if (saved == true) _load();
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return '—';
    return [p['first_name'], p['last_name']]
        .where((s) => s != null && s.toString().isNotEmpty)
        .join(' ');
  }

  /// 0 ID · 1 Resident · 2 Type · 3 Severity · 4 Status · 5 Date
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> v, int col) {
    switch (col) {
      case 0:
        return text(v['violation_number'] ?? v['id']);
      case 1:
        return text(_name(v['offender'] as Map<String, dynamic>?));
      case 2:
        return text((v['violation_type'] as Map<String, dynamic>?)?['name']);
      case 3:
        return rankedKey(
            (v['violation_type'] as Map<String, dynamic>?)?['severity'], kPriorityRank);
      case 4:
        return rankedKey(v['status'], kStatusRank);
      case 5:
        return date(v['violation_date']);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child:
              Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      return constraints.maxWidth < 700 ? _mobileBody() : _desktopBody();
    });
  }

  /// Wide layout: status filter, stat cards and the table.
  Widget _desktopBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('All violations',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted)),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'all', child: Text('All statuses')),
                  PopupMenuItem(value: 'reported', child: Text('Reported')),
                  PopupMenuItem(value: 'noticed', child: Text('Noticed')),
                  PopupMenuItem(value: 'contested', child: Text('Contested')),
                  PopupMenuItem(value: 'upheld', child: Text('Upheld')),
                  PopupMenuItem(
                      value: 'penalty_imposed', child: Text('Penalty Imposed')),
                  PopupMenuItem(value: 'dismissed', child: Text('Dismissed')),
                  PopupMenuItem(value: 'resolved', child: Text('Resolved')),
                ],
                child: OutlinedButton(
                    onPressed: null,
                    child: Text(_statusFilter == 'all'
                        ? 'Filter'
                        : _statusFilter == 'repeat' ? 'Repeat offenders' : titleCase(_statusFilter))),
              ),
              const SizedBox(width: 10),
              if (_canCreate) FilledButton(
                  onPressed: () => _openForm(),
                  child: const Text('Issue Violation')),
            ],
          ),
          const SizedBox(height: 18),
          responsiveStatCards((w) => [
            DashboardStatCard(icon: Icons.gavel_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Open', value: '$_open', width: w, selected: _statusFilter == 'open', onTap: () => _tapCard('open')),
            DashboardStatCard(icon: Icons.check_circle_outline, iconBg: const Color(0xFFE2F0F7), label: 'Resolved', value: '$_resolved', width: w, selected: _statusFilter == 'resolved', onTap: () => _tapCard('resolved')),
            DashboardStatCard(icon: Icons.repeat, iconBg: const Color(0xFFFBEFD6), label: 'Repeat Offenders', value: '$_repeatOffenders', width: w, selected: _statusFilter == 'repeat', onTap: () => _tapCard('repeat')),
          ]),
          const SizedBox(height: 20),
          Expanded(child: _buildTable()),
        ],
      ),
    );
  }

  /// Phone layout: a list of cards.
  Widget _mobileBody() {
    final rows = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(rows.length == _rows.length ? '${_rows.length} violations' : '${rows.length} of ${_rows.length} violations',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted)),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'all', child: Text('All statuses')),
                  PopupMenuItem(value: 'reported', child: Text('Reported')),
                  PopupMenuItem(value: 'noticed', child: Text('Noticed')),
                  PopupMenuItem(value: 'contested', child: Text('Contested')),
                  PopupMenuItem(value: 'upheld', child: Text('Upheld')),
                  PopupMenuItem(
                      value: 'penalty_imposed', child: Text('Penalty Imposed')),
                  PopupMenuItem(value: 'dismissed', child: Text('Dismissed')),
                  PopupMenuItem(value: 'resolved', child: Text('Resolved')),
                ],
                icon: const Icon(Icons.filter_list,
                    size: 20, color: AppColors.textSecondary),
              ),
              if (_canCreate)
                FilledButton(
                  onPressed: () => _openForm(),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8)),
                  child:
                      const Text('+ Violation', style: TextStyle(fontSize: 12.5)),
                ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                      _statusFilter == 'all' ? 'No violations yet.' : 'No violations match this filter.',
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: pageSlice(rows, _page).length + (pageCountFor(rows.length) > 1 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= pageSlice(rows, _page).length) {
                      return pagerFor(rows.length, _page, (p) => setState(() => _page = p));
                    }
                    final v = pageSlice(rows, _page)[i];
                    final vt = v['violation_type'] as Map<String, dynamic>?;
                    return InkWell(
                      onTap: () => _openDetail(v),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '#${v['violation_number'] ?? v['id']} · ${_name(v['offender'] as Map<String, dynamic>?)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary)),
                                  const SizedBox(height: 3),
                                  Text(
                                      '${(vt?['name'] ?? '—').toString()} · ${(v['violation_date'] ?? '').toString()}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _severityBadge(vt?['severity']?.toString()),
                                const SizedBox(height: 4),
                                StatusBadge((v['status'] ?? '').toString()),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return Center(
          child: Text(
              _statusFilter == 'all' ? 'No violations yet.' : 'No violations match this filter.',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted)));
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))
        ],
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
            headingTextStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted),
            dataTextStyle:
                const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            columns: [
              DataColumn(label: const Text('ID'), onSort: onSort),
              DataColumn(label: const Text('RESIDENT'), onSort: onSort),
              DataColumn(label: const Text('TYPE'), onSort: onSort),
              DataColumn(label: const Text('SEVERITY'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
              DataColumn(label: const Text('DATE'), onSort: onSort),
            ],
            rows: [
              for (final v in pageSlice(sortRows(rows), _page))
                DataRow(
                  onSelectChanged: (_) => _openDetail(v),
                  cells: [
                    DataCell(Text('#${v['violation_number'] ?? v['id']}')),
                    DataCell(
                        Text(_name(v['offender'] as Map<String, dynamic>?))),
                    DataCell(Text(((v['violation_type']
                                as Map<String, dynamic>?)?['name'] ??
                            '—')
                        .toString())),
                    DataCell(_severityBadge((v['violation_type']
                            as Map<String, dynamic>?)?['severity']
                        ?.toString())),
                    DataCell(StatusBadge((v['status'] ?? '').toString())),
                    DataCell(Text((v['violation_date'] ?? '').toString())),
                  ],
                ),
            ],
          ),
      ),
    );
  }

  Widget _severityBadge(String? severity) {
    if (severity == null) {
      return const Text('—',
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted));
    }
    return StatusBadge(severity);
  }
}
