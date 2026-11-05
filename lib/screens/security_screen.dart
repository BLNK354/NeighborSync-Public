import 'package:flutter/material.dart';
import '../core/fetch_all.dart';
import '../core/card_filter.dart';
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
import '../widgets/responsive_officer_shell.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/status_badge.dart';
import '../widgets/gate_pass_scanner.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Officer Security Incidents screen. One stat card per incident status
/// (Open, Investigating, Resolved, Closed, Escalated); tap one to filter.
class AdminSecurityScreen extends StatefulWidget {
  const AdminSecurityScreen({super.key});

  @override
  State<AdminSecurityScreen> createState() => _AdminSecurityScreenState();
}

class _AdminSecurityScreenState extends State<AdminSecurityScreen>
    with SafeSetState<AdminSecurityScreen>, TableSortState {
  // 1-based page for the 10-row pager (pagination_footer.dart).
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  /// Whether to show the create button. The database requires
  /// security_incidents:create, so read-only roles must not see it.
  bool _canCreate = false;

  /// Whether to show the gate-pass scanner (gate_passes:read_all).
  /// Kept separate from `_canCreate`, which is a different permission.
  bool _canScanPasses = false;
  String _statusFilter = 'all';

  /// A status card filters the list to that status; tapping the same card
  /// again clears it. Back to page 1 either way.
  void _tapStatus(String status) => setState(() {
        _statusFilter = _statusFilter == status ? 'all' : status;
        _page = 1;
      });

  @override
  void initState() {
    super.initState();
    // A dashboard card may have sent us here already narrowed (card_filter.dart).
    _statusFilter = CardFilter.take('security') ?? _statusFilter;
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads all incidents with assignee names, plus the officer's permissions.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final perms = await SupabaseService.instance.getMyPermissions();
      final data = await fetchAllRows((from, to) => SupabaseService.instance.client
          .from('security_incidents')
          .select('*, assignee:assigned_to(first_name, last_name)')
          .order('incident_date', ascending: false)
          .order('id', ascending: false)
          .range(from, to));
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
        _canCreate = canPerform(perms, 'security_incidents', 'create');
        _canScanPasses = canPerform(perms, 'gate_passes', 'read_all');
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

  int _count(String status) => _rows.where((r) => r['status'] == status).length;

  List<Map<String, dynamic>> get _visible =>
      _statusFilter == 'all'
          ? _rows
          // 'unresolved' is the dashboards' Open Incidents: open + investigating.
          : _statusFilter == 'unresolved'
              ? _rows.where((r) => const {'open', 'investigating'}.contains(r['status'])).toList()
              : _rows.where((r) => r['status'] == _statusFilter).toList();

  /// Shows a read-only detail card; Edit appears only for those allowed to update.
  Future<void> _openDetail(Map<String, dynamic> r) async {
    final edit = await showModuleDetailDialog(
      context,
      security,
      r,
      subtitle: [ (r['incident_number'] ?? '').toString(), 'Assigned: ${_name(r['assignee'] as Map<String, dynamic>?)}' ]
          .where((s) => s.trim().isNotEmpty && !s.endsWith('—'))
          .join(' · '),
    );
    if (edit == true && mounted) await _openForm(r);
  }

  /// Opens the log/edit form and reloads if saved.
  Future<void> _openForm([Map<String, dynamic>? initial]) async {
    final saved = await showModuleFormDialog(context, security, initial: initial);
    if (saved == true) _load();
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return 'Unassigned';
    return [p['first_name'], p['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
  }

  /// 0 Incident# · 1 Title · 2 Type · 3 Severity · 4 Assigned · 5 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> r, int col) {
    switch (col) {
      case 0:
        return text(r['incident_number'] ?? r['id']);
      case 1:
        return text(r['title']);
      case 2:
        return text(r['type']);
      case 3:
        return rankedKey(r['severity'], kPriorityRank);
      case 4:
        return text(_name(r['assignee'] as Map<String, dynamic>?));
      case 5:
        return rankedKey(r['status'], kStatusRank);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: 'Security Incidents',
      activeItem: 'Security',
      activeTab: 'Services',
      desktopChild: _desktopBody(),
      mobileChild: _mobileBody(),
    );
  }

  Widget _desktopBody() {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('All incidents',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                        const Spacer(),
                        PopupMenuButton<String>(
                          onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'all', child: Text('All statuses')),
                            PopupMenuItem(value: 'open', child: Text('Open')),
                            PopupMenuItem(value: 'investigating', child: Text('Investigating')),
                            PopupMenuItem(value: 'escalated', child: Text('Escalated')),
                            PopupMenuItem(value: 'resolved', child: Text('Resolved')),
                            PopupMenuItem(value: 'closed', child: Text('Closed')),
                          ],
                          child: OutlinedButton(
                              onPressed: null,
                              child: Text(_statusFilter == 'all' ? 'Filter' : titleCase(_statusFilter))),
                        ),
                        const SizedBox(width: 10),
                        // Gate-pass scanner, here because guards work on this screen.
                        if (_canScanPasses) ...[
                          const ScanGatePassButton(),
                          const SizedBox(width: 10),
                        ],
                        if (_canCreate) FilledButton(onPressed: () => _openForm(), child: const Text('Log Incident')),
                      ],
                    ),
                    const SizedBox(height: 18),
                    responsiveStatCards((w) => [
                      DashboardStatCard(icon: Icons.report_gmailerrorred_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Open', value: '${_count('open')}', width: w, selected: _statusFilter == 'open', onTap: () => _tapStatus('open')),
                      DashboardStatCard(icon: Icons.travel_explore_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Investigating', value: '${_count('investigating')}', width: w, selected: _statusFilter == 'investigating', onTap: () => _tapStatus('investigating')),
                      DashboardStatCard(icon: Icons.verified_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Resolved', value: '${_count('resolved')}', width: w, selected: _statusFilter == 'resolved', onTap: () => _tapStatus('resolved')),
                      DashboardStatCard(icon: Icons.lock_outline, iconBg: const Color(0xFFEDEFF2), label: 'Closed', value: '${_count('closed')}', width: w, selected: _statusFilter == 'closed', onTap: () => _tapStatus('closed')),
                      DashboardStatCard(icon: Icons.priority_high_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Escalated', value: '${_count('escalated')}', width: w, selected: _statusFilter == 'escalated', onTap: () => _tapStatus('escalated')),
                    ]),
                    const SizedBox(height: 20),
                    Expanded(child: _buildTable()),
                  ],
                ),
              );
  }

  // ---------- mobile body ----------
  Widget _mobileBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    final rows = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: PopupMenuButton<String>(
                  onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'all', child: Text('All statuses')),
                    PopupMenuItem(value: 'open', child: Text('Open')),
                    PopupMenuItem(value: 'investigating', child: Text('Investigating')),
                    PopupMenuItem(value: 'escalated', child: Text('Escalated')),
                    PopupMenuItem(value: 'resolved', child: Text('Resolved')),
                    PopupMenuItem(value: 'closed', child: Text('Closed')),
                  ],
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.filter_list, size: 16),
                    label: Text(_statusFilter == 'all' ? 'Filter' : titleCase(_statusFilter)),
                  ),
                ),
              ),
              // Icon-only on phones; the tooltip has the label.
              if (_canScanPasses) const ScanGatePassButton(compact: true),
              if (_canCreate) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(onPressed: () => _openForm(), child: const Text('+ Incident')),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: responsiveStatCards((w) => [
            DashboardStatCard(icon: Icons.report_gmailerrorred_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Open', value: '${_count('open')}', width: w, selected: _statusFilter == 'open', onTap: () => _tapStatus('open')),
            DashboardStatCard(icon: Icons.travel_explore_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Investigating', value: '${_count('investigating')}', width: w, selected: _statusFilter == 'investigating', onTap: () => _tapStatus('investigating')),
            DashboardStatCard(icon: Icons.verified_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Resolved', value: '${_count('resolved')}', width: w, selected: _statusFilter == 'resolved', onTap: () => _tapStatus('resolved')),
            DashboardStatCard(icon: Icons.lock_outline, iconBg: const Color(0xFFEDEFF2), label: 'Closed', value: '${_count('closed')}', width: w, selected: _statusFilter == 'closed', onTap: () => _tapStatus('closed')),
            DashboardStatCard(icon: Icons.priority_high_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Escalated', value: '${_count('escalated')}', width: w, selected: _statusFilter == 'escalated', onTap: () => _tapStatus('escalated')),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No incidents logged yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: pageSlice(rows, _page).length + (pageCountFor(rows.length) > 1 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= pageSlice(rows, _page).length) {
                      return pagerFor(rows.length, _page, (p) => setState(() => _page = p));
                    }
                    final r = pageSlice(rows, _page)[i];
                    return InkWell(
                      onTap: () => _openDetail(r),
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
                                  Text('#${r['incident_number'] ?? r['id']} · ${(r['title'] ?? '').toString()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  const SizedBox(height: 3),
                                  Text('${titleCase((r['type'] ?? '').toString())} · ${_name(r['assignee'] as Map<String, dynamic>?)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                StatusBadge((r['status'] ?? '').toString()),
                                const SizedBox(height: 6),
                                StatusBadge((r['severity'] ?? '—').toString()),
                                if ((r['suggested_severity'] ?? '').toString().isNotEmpty &&
                                    r['suggested_severity'] != r['severity']) ...[
                                  const SizedBox(height: 4),
                                  Text('AI: ${titleCase(r['suggested_severity'].toString())}',
                                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                ],
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

  /// Desktop table of the visible incidents, sortable and paged.
  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return const Center(child: Text('No incidents logged yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    }
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
              DataColumn(label: const Text('INCIDENT #'), onSort: onSort),
              DataColumn(label: const Text('TITLE'), onSort: onSort),
              DataColumn(label: const Text('TYPE'), onSort: onSort),
              DataColumn(label: const Text('SEVERITY'), onSort: onSort),
              DataColumn(label: const Text('ASSIGNED'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
            ],
            rows: [
              for (final r in pageSlice(sortRows(rows), _page))
                DataRow(
                  onSelectChanged: (_) => _openDetail(r),
                  cells: [
                    DataCell(Text('#${r['incident_number'] ?? r['id']}')),
                    DataCell(Text((r['title'] ?? '').toString())),
                    DataCell(StatusBadge((r['type'] ?? '').toString())),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBadge((r['severity'] ?? '—').toString()),
                        if ((r['suggested_severity'] ?? '').toString().isNotEmpty &&
                            r['suggested_severity'] != r['severity']) ...[
                          const SizedBox(width: 6),
                          Text('AI: ${titleCase(r['suggested_severity'].toString())}',
                              style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                        ],
                      ],
                    )),
                    DataCell(Text(_name(r['assignee'] as Map<String, dynamic>?))),
                    DataCell(StatusBadge((r['status'] ?? '').toString())),
                  ],
                ),
            ],
          ),
      ),
    );
  }
}
