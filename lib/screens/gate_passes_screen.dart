import 'package:flutter/material.dart';
import '../core/card_filter.dart';
import '../core/fetch_all.dart';
import '../core/record_focus.dart';
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

/// Officer Gate Passes screen. Status cards (tap to filter) sit above a
/// table of pass number, visitor, validity window and status.
class AdminGatePassesScreen extends StatefulWidget {
  const AdminGatePassesScreen({super.key});

  @override
  State<AdminGatePassesScreen> createState() => _AdminGatePassesScreenState();
}

class _AdminGatePassesScreenState extends State<AdminGatePassesScreen>
    with SafeSetState<AdminGatePassesScreen>, TableSortState, RecordFocusTarget {
  // 1-based page for the 10-row pager (pagination_footer.dart).
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  /// Shows the New Gate Pass button; needs gate_passes:create (RLS enforces it).
  bool _canCreate = false;

  /// Shows the Scan button. Uses gate_passes:read_all, not create: residents
  /// also hold create, and scanning looks up other people's passes.
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
    _statusFilter = CardFilter.take('gate_passes') ?? _statusFilter;
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
          .from('gate_passes')
          .select('*')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(from, to));
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
        _canCreate = canPerform(perms, 'gate_passes', 'create');
        _canScanPasses = canPerform(perms, 'gate_passes', 'read_all');
        _loading = false;
      });
      // Opened from a notification: show and highlight that one record.
      takeRecordFocus('gate_passes',
          clearFilters: () { _statusFilter = 'all'; },
          ordered: () => sortRows(_visible),
          setPage: (p) => _page = p);
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
      _statusFilter == 'all' ? _rows : _rows.where((r) => r['status'] == _statusFilter).toList();

  /// Opens a read-only card; Edit shows only for roles allowed to update.
  Future<void> _openDetail(Map<String, dynamic> r) async {
    final edit = await showModuleDetailDialog(
      context,
      gatePasses,
      r,
      subtitle: [ (r['pass_number'] ?? '').toString() ]
          .where((s) => s.trim().isNotEmpty && !s.endsWith('—'))
          .join(' · '),
    );
    if (edit == true && mounted) await _openForm(r);
  }

  Future<void> _openForm([Map<String, dynamic>? initial]) async {
    final saved = await showModuleFormDialog(context, gatePasses, initial: initial);
    if (saved == true) _load();
  }

  String _date(dynamic v) => (v ?? '').toString().split('T').first;

  /// 0 Pass# · 1 Visitor · 2 Valid from · 3 Valid until · 4 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> r, int col) {
    switch (col) {
      case 0:
        return text(r['pass_number'] ?? r['id']);
      case 1:
        return text(r['visitor_name']);
      case 2:
        return date(r['valid_from']);
      case 3:
        return date(r['valid_until']);
      case 4:
        return rankedKey(r['status'], kStatusRank);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: 'Gate Passes',
      activeItem: 'Gate Passes',
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
                        const Text('All gate passes',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                        const Spacer(),
                        PopupMenuButton<String>(
                          onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'all', child: Text('All statuses')),
                            PopupMenuItem(value: 'pending', child: Text('Pending')),
                            PopupMenuItem(value: 'approved', child: Text('Approved')),
                            PopupMenuItem(value: 'rejected', child: Text('Rejected')),
                            PopupMenuItem(value: 'expired', child: Text('Expired')),
                            PopupMenuItem(value: 'used', child: Text('Used')),
                          ],
                          child: OutlinedButton(
                              onPressed: null,
                              child: Text(_statusFilter == 'all' ? 'Filter' : titleCase(_statusFilter))),
                        ),
                        const SizedBox(width: 10),
                        if (_canScanPasses) ...[
                          const ScanGatePassButton(),
                          const SizedBox(width: 10),
                        ],
                        if (_canCreate) FilledButton(onPressed: () => _openForm(), child: const Text('New Gate Pass')),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _statCards(),
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
                    PopupMenuItem(value: 'pending', child: Text('Pending')),
                    PopupMenuItem(value: 'approved', child: Text('Approved')),
                    PopupMenuItem(value: 'rejected', child: Text('Rejected')),
                    PopupMenuItem(value: 'expired', child: Text('Expired')),
                    PopupMenuItem(value: 'used', child: Text('Used')),
                  ],
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.filter_list, size: 16),
                    label: Text(_statusFilter == 'all' ? 'Filter' : titleCase(_statusFilter)),
                  ),
                ),
              ),
              // Icon-only so the row fits a 360px phone.
              if (_canScanPasses) const ScanGatePassButton(compact: true),
              if (_canCreate) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(onPressed: () => _openForm(), child: const Text('+ Pass')),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: _statCards(),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No gate passes yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: pageSlice(pinFocused(rows), _page).length + (pageCountFor(rows.length) > 1 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= pageSlice(pinFocused(rows), _page).length) {
                      return pagerFor(rows.length, _page, (p) => setState(() => _page = p));
                    }
                    final r = pageSlice(pinFocused(rows), _page)[i];
                    return InkWell(
                      onTap: () => _openDetail(r),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isFocusedRow(r) ? kFocusRowColor : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${r['pass_number'] ?? r['id']} · ${(r['visitor_name'] ?? '').toString()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  const SizedBox(height: 3),
                                  Text('${_date(r['valid_from'])} → ${_date(r['valid_until'])}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            StatusBadge((r['status'] ?? '').toString()),
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

  /// Status cards shared by desktop and mobile.
  Widget _statCards() {
    return responsiveStatCards((w) => [
          DashboardStatCard(icon: Icons.pending_actions_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Pending', value: '${_count('pending')}', width: w, selected: _statusFilter == 'pending', onTap: () => _tapStatus('pending')),
          DashboardStatCard(icon: Icons.check_circle_outline, iconBg: const Color(0xFFE3F1E9), label: 'Approved', value: '${_count('approved')}', width: w, selected: _statusFilter == 'approved', onTap: () => _tapStatus('approved')),
          DashboardStatCard(icon: Icons.cancel_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Rejected', value: '${_count('rejected')}', width: w, selected: _statusFilter == 'rejected', onTap: () => _tapStatus('rejected')),
          DashboardStatCard(icon: Icons.timer_off_outlined, iconBg: const Color(0xFFEDEFF2), label: 'Expired', value: '${_count('expired')}', width: w, selected: _statusFilter == 'expired', onTap: () => _tapStatus('expired')),
          DashboardStatCard(icon: Icons.how_to_reg_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Used', value: '${_count('used')}', width: w, selected: _statusFilter == 'used', onTap: () => _tapStatus('used')),
        ]);
  }

  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return const Center(child: Text('No gate passes yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
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
              DataColumn(label: const Text('PASS #'), onSort: onSort),
              DataColumn(label: const Text('VISITOR'), onSort: onSort),
              DataColumn(label: const Text('VALID FROM'), onSort: onSort),
              DataColumn(label: const Text('VALID UNTIL'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
              const DataColumn(label: Text('ACTIONS')),
            ],
            rows: [
              for (final r in pageSlice(pinFocused(sortRows(rows)), _page))
                DataRow(color: focusRowColor(r), cells: [
                  DataCell(Text((r['pass_number'] ?? r['id']).toString())),
                  DataCell(Text((r['visitor_name'] ?? '—').toString())),
                  DataCell(Text(_date(r['valid_from']))),
                  DataCell(Text(_date(r['valid_until']))),
                  DataCell(StatusBadge((r['status'] ?? '').toString())),
                  DataCell(TextButton(onPressed: () => _openDetail(r), child: const Text('Review'))),
                ]),
            ],
          ),
      ),
    );
  }
}
