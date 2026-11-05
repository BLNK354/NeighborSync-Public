import 'package:flutter/material.dart';
import '../core/fetch_all.dart';
import '../core/record_focus.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/permissions.dart';
import '../core/module_registry.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/admin_shell.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/responsive_bits.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Officer view of all permits: status cards that filter the list, plus a
/// table (cards on phones). "Review" opens the edit form to change status and add notes.
class AdminPermitsScreen extends StatefulWidget {
  const AdminPermitsScreen({super.key});

  @override
  State<AdminPermitsScreen> createState() => _AdminPermitsScreenState();
}

class _AdminPermitsScreenState extends State<AdminPermitsScreen>
    with SafeSetState<AdminPermitsScreen>, TableSortState, RecordFocusTarget {
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  /// Whether this officer may add permits; read-only roles must not see a button the database rejects.
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
          .from('permits')
          .select('*, applicant:applicant_id(first_name, last_name), '
              'permit_type:permit_type_id(name)')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(from, to));
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
        _canCreate = canPerform(perms, 'permits', 'create');
        _loading = false;
      });
      // When opened from a notification, show and highlight that record.
      takeRecordFocus('permits',
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

  int _count(List<String> statuses) => _rows.where((p) => statuses.contains(p['status'])).length;

  List<Map<String, dynamic>> get _visible =>
      _statusFilter == 'all' ? _rows : _rows.where((p) => p['status'] == _statusFilter).toList();

  Future<void> _openForm([Map<String, dynamic>? initial]) async {
    final saved = await showModuleFormDialog(context, permits, initial: initial);
    if (saved == true) _load();
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return '—';
    return [p['first_name'], p['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
  }

  /// 0 Permit# · 1 Resident · 2 Type · 3 Status · 4 Submitted
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> p, int col) {
    switch (col) {
      case 0:
        return text(p['permit_number'] ?? p['id']);
      case 1:
        return text(_name(p['applicant'] as Map<String, dynamic>?));
      case 2:
        return text((p['permit_type'] as Map<String, dynamic>?)?['name'] ?? p['title']);
      case 3:
        return rankedKey(p['status'], kStatusRank);
      case 4:
        return date(p['created_at']);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Permits',
      activeItem: 'Permits',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TitleActionRow(
                        title: const Text('All permits',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                        actions: [
                          PopupMenuButton<String>(
                            onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'all', child: Text('All statuses')),
                              PopupMenuItem(value: 'submitted', child: Text('Submitted')),
                              PopupMenuItem(value: 'under_review', child: Text('Under Review')),
                              PopupMenuItem(value: 'approved', child: Text('Approved')),
                              PopupMenuItem(value: 'rejected', child: Text('Rejected')),
                              PopupMenuItem(value: 'expired', child: Text('Expired')),
                            ],
                            child: OutlinedButton(
                                onPressed: null,
                                child: Text(_statusFilter == 'all' ? 'Filter' : titleCase(_statusFilter))),
                          ),
                          if (_canCreate) FilledButton(onPressed: () => _openForm(), child: const Text('Apply for Permit')),
                        ],
                      ),
                      const SizedBox(height: 18),
                      responsiveStatCards((w) => [
                            DashboardStatCard(icon: Icons.upload_file_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Submitted', value: '${_count([
                                  'submitted',
                                  'draft'
                                ])}', width: w, selected: _statusFilter == 'submitted', onTap: () => _tapStatus('submitted')),
                            DashboardStatCard(icon: Icons.rate_review_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Under Review', value: '${_count([
                                  'under_review'
                                ])}', width: w, selected: _statusFilter == 'under_review', onTap: () => _tapStatus('under_review')),
                            DashboardStatCard(icon: Icons.verified_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Approved', value: '${_count([
                                  'approved'
                                ])}', width: w, selected: _statusFilter == 'approved', onTap: () => _tapStatus('approved')),
                            DashboardStatCard(icon: Icons.cancel_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Rejected', value: '${_count([
                                  'rejected'
                                ])}', width: w, selected: _statusFilter == 'rejected', onTap: () => _tapStatus('rejected')),
                            DashboardStatCard(icon: Icons.timer_off_outlined, iconBg: const Color(0xFFEDEFF2), label: 'Expired', value: '${_count([
                                  'expired'
                                ])}', width: w, selected: _statusFilter == 'expired', onTap: () => _tapStatus('expired')),
                          ]),
                      const SizedBox(height: 20),
                      Expanded(child: _buildTable()),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return const Center(child: Text('No permits yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    }
    // Narrow screens get cards because the table is too wide.
    if (MediaQuery.sizeOf(context).width < 700) return _cards(rows);
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
              DataColumn(label: const Text('PERMIT #'), onSort: onSort),
              DataColumn(label: const Text('RESIDENT'), onSort: onSort),
              DataColumn(label: const Text('TYPE'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
              DataColumn(label: const Text('SUBMITTED'), onSort: onSort),
              const DataColumn(label: Text('ACTIONS')),
            ],
            rows: [
              for (final p in pageSlice(pinFocused(sortRows(rows)), _page))
                DataRow(color: focusRowColor(p), cells: [
                  DataCell(Text('#${p['permit_number'] ?? p['id']}')),
                  DataCell(Text(_name(p['applicant'] as Map<String, dynamic>?))),
                  DataCell(Text(((p['permit_type'] as Map<String, dynamic>?)?['name'] ?? p['title'] ?? '—').toString())),
                  DataCell(StatusBadge((p['status'] ?? '').toString())),
                  DataCell(Text((p['created_at'] ?? '').toString().split('T').first)),
                  DataCell(TextButton(onPressed: () => _openForm(p), child: const Text('Review'))),
                ]),
            ],
          ),
      ),
    );
  }

  Widget _cards(List<Map<String, dynamic>> rows) {
    final page = pageSlice(pinFocused(sortRows(rows)), _page);
    final hasPager = pageCountFor(rows.length) > 1;
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: page.length + (hasPager ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= page.length) {
          return pagerFor(rows.length, _page, (p) => setState(() => _page = p));
        }
        final p = page[i];
        final type = ((p['permit_type'] as Map<String, dynamic>?)?['name'] ?? '').toString();
        return InkWell(
          onTap: () => _openForm(p),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isFocusedRow(p) ? kFocusRowColor : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppColors.cardShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((p['title'] ?? type).toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 3),
                      Text('#${p['permit_number'] ?? p['id']} · ${_name(p['applicant'] as Map<String, dynamic>?)}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      const SizedBox(height: 2),
                      Text([if (type.isNotEmpty) type, (p['created_at'] ?? '').toString().split('T').first].join(' · '),
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge((p['status'] ?? '').toString()),
              ],
            ),
          ),
        );
      },
    );
  }
}
