import 'package:flutter/material.dart';
import '../core/fetch_all.dart';
import '../core/card_filter.dart';
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
import '../widgets/responsive_officer_shell.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/status_badge.dart';
import '../widgets/dashboard_widgets.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Officer list of Move In/Out Requests (`move_requests`), with status cards
/// counted from the loaded rows.
class AdminMoveRequestsScreen extends StatefulWidget {
  const AdminMoveRequestsScreen({super.key});

  @override
  State<AdminMoveRequestsScreen> createState() => _AdminMoveRequestsScreenState();
}

class _AdminMoveRequestsScreenState extends State<AdminMoveRequestsScreen>
    with SafeSetState<AdminMoveRequestsScreen>, TableSortState, RecordFocusTarget {
  // 1-based page number for the pager.
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  /// Whether this officer may add records here (needs move_requests:create);
  /// hides the create button for read-only roles.
  bool _canCreate = false;
  String _statusFilter = 'all';

  /// Tapping a status card filters to it; tapping again clears the filter.
  void _tapStatus(String status) => setState(() {
        _statusFilter = _statusFilter == status ? 'all' : status;
        _page = 1;
      });

  @override
  void initState() {
    super.initState();
    // A dashboard card may have opened this page already filtered.
    _statusFilter = CardFilter.take('move_requests') ?? _statusFilter;
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
          .from('move_requests')
          .select('*, resident:resident_id(first_name, last_name)')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(from, to));
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
        _canCreate = canPerform(perms, 'move_requests', 'create');
        _loading = false;
      });
      // Opened from a notification: show and highlight that one record.
      takeRecordFocus('move_requests',
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

  /// Opens a read-only detail card; Edit shows only for roles that may update.
  Future<void> _openDetail(Map<String, dynamic> r) async {
    final edit = await showModuleDetailDialog(
      context,
      moveRequests,
      r,
      subtitle: [ (r['request_number'] ?? '').toString(), _name(r['resident'] as Map<String, dynamic>?) ]
          .where((s) => s.trim().isNotEmpty && !s.endsWith('—'))
          .join(' · '),
    );
    if (edit == true && mounted) await _openForm(r);
  }

  Future<void> _openForm([Map<String, dynamic>? initial]) async {
    final saved = await showModuleFormDialog(context, moveRequests, initial: initial);
    if (saved == true) _load();
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return '—';
    return [p['first_name'], p['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
  }

  /// 0 Request# · 1 Resident · 2 Type · 3 Move date · 4 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> r, int col) {
    switch (col) {
      case 0:
        return text(r['request_number'] ?? r['id']);
      case 1:
        return text(_name(r['resident'] as Map<String, dynamic>?));
      case 2:
        return text(r['request_type']);
      case 3:
        return date(r['move_date']);
      case 4:
        return rankedKey(r['status'], kStatusRank);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: 'Move In / Out Requests',
      activeItem: 'Move In/Out',
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
                        const Text('All requests',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                        const Spacer(),
                        PopupMenuButton<String>(
                          onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'all', child: Text('All statuses')),
                            PopupMenuItem(value: 'pending', child: Text('Pending')),
                            PopupMenuItem(value: 'approved', child: Text('Approved')),
                            PopupMenuItem(value: 'scheduled', child: Text('Scheduled')),
                            PopupMenuItem(value: 'rejected', child: Text('Rejected')),
                            PopupMenuItem(value: 'completed', child: Text('Completed')),
                          ],
                          child: OutlinedButton(
                              onPressed: null,
                              child: Text(_statusFilter == 'all' ? 'Filter' : titleCase(_statusFilter))),
                        ),
                        const SizedBox(width: 10),
                        if (_canCreate) FilledButton(onPressed: () => _openForm(), child: const Text('New Request')),
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
                    PopupMenuItem(value: 'scheduled', child: Text('Scheduled')),
                    PopupMenuItem(value: 'rejected', child: Text('Rejected')),
                    PopupMenuItem(value: 'completed', child: Text('Completed')),
                  ],
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.filter_list, size: 16),
                    label: Text(_statusFilter == 'all' ? 'Filter' : titleCase(_statusFilter)),
                  ),
                ),
              ),
              if (_canCreate) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(onPressed: () => _openForm(), child: const Text('+ Request')),
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
              ? const Center(child: Text('No move requests yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)))
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
                                  Text('#${r['request_number'] ?? r['id']} · ${_name(r['resident'] as Map<String, dynamic>?)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  const SizedBox(height: 3),
                                  Text('${titleCase((r['request_type'] ?? '').toString())} · ${(r['move_date'] ?? '').toString()}',
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

  /// Status count cards, used on desktop and mobile.
  Widget _statCards() {
    return responsiveStatCards((w) => [
          DashboardStatCard(icon: Icons.pending_actions_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Pending', value: '${_count('pending')}', width: w, selected: _statusFilter == 'pending', onTap: () => _tapStatus('pending')),
          DashboardStatCard(icon: Icons.check_circle_outline, iconBg: const Color(0xFFE3F1E9), label: 'Approved', value: '${_count('approved')}', width: w, selected: _statusFilter == 'approved', onTap: () => _tapStatus('approved')),
          DashboardStatCard(icon: Icons.event_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Scheduled', value: '${_count('scheduled')}', width: w, selected: _statusFilter == 'scheduled', onTap: () => _tapStatus('scheduled')),
          DashboardStatCard(icon: Icons.cancel_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Rejected', value: '${_count('rejected')}', width: w, selected: _statusFilter == 'rejected', onTap: () => _tapStatus('rejected')),
          DashboardStatCard(icon: Icons.task_alt_outlined, iconBg: const Color(0xFFEDEFF2), label: 'Completed', value: '${_count('completed')}', width: w, selected: _statusFilter == 'completed', onTap: () => _tapStatus('completed')),
        ]);
  }

  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return const Center(child: Text('No move requests yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
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
              DataColumn(label: const Text('REQUEST #'), onSort: onSort),
              DataColumn(label: const Text('RESIDENT'), onSort: onSort),
              DataColumn(label: const Text('TYPE'), onSort: onSort),
              DataColumn(label: const Text('MOVE DATE'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
              const DataColumn(label: Text('ACTIONS')),
            ],
            rows: [
              for (final r in pageSlice(pinFocused(sortRows(rows)), _page))
                DataRow(color: focusRowColor(r), cells: [
                  DataCell(Text('#${r['request_number'] ?? r['id']}')),
                  DataCell(Text(_name(r['resident'] as Map<String, dynamic>?))),
                  DataCell(StatusBadge((r['request_type'] ?? '').toString())),
                  DataCell(Text((r['move_date'] ?? '').toString())),
                  DataCell(StatusBadge((r['status'] ?? '').toString())),
                  DataCell(TextButton(onPressed: () => _openDetail(r), child: const Text('View'))),
                ]),
            ],
          ),
      ),
    );
  }
}
