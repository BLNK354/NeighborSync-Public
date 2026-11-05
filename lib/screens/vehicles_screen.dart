import 'package:flutter/material.dart';
import '../core/fetch_all.dart';
import '../core/card_filter.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/permissions.dart';
import '../core/module_registry.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/responsive_officer_shell.dart';
import '../widgets/module_detail_dialog.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Officer Vehicles screen: status cards plus a table. The STICKER column
/// shows Valid or Expired from the sticker expiry date.
class AdminVehiclesScreen extends StatefulWidget {
  const AdminVehiclesScreen({super.key});

  @override
  State<AdminVehiclesScreen> createState() => _AdminVehiclesScreenState();
}

class _AdminVehiclesScreenState extends State<AdminVehiclesScreen>
    with SafeSetState<AdminVehiclesScreen>, TableSortState {
  // 1-based page for the 10-row pager (pagination_footer.dart).
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  /// Whether to show the create button. The database requires
  /// vehicles:create, so read-only roles must not see it.
  bool _canCreate = false;
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
    _statusFilter = CardFilter.take('vehicles') ?? _statusFilter;
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads all vehicles with their owner names, plus the officer's permissions.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final perms = await SupabaseService.instance.getMyPermissions();
      final data = await fetchAllRows((from, to) => SupabaseService.instance.client
          .from('vehicles')
          .select('*, owner:user_id(first_name, last_name)')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(from, to));
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
        _canCreate = canPerform(perms, 'vehicles', 'create');
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

  int _count(String status) => _rows.where((v) => v['status'] == status).length;

  List<Map<String, dynamic>> get _visible =>
      _statusFilter == 'all' ? _rows : _rows.where((v) => v['status'] == _statusFilter).toList();

  /// Opens the register/edit form and reloads if saved.
  Future<void> _openForm([Map<String, dynamic>? initial]) async {
    final saved = await showModuleFormDialog(context, vehicles, initial: initial);
    if (saved == true) _load();
  }

  /// Shows a read-only detail card; Edit is offered only to those allowed.
  /// The owner name goes in the subtitle, since it comes from this
  /// screen's `owner:user_id(...)` embed.
  Future<void> _openDetail(Map<String, dynamic> v) async {
    final edit = await showModuleDetailDialog(
      context,
      vehicles,
      v,
      subtitle: [
        _name(v['owner'] as Map<String, dynamic>?),
        [v['make'], v['model']]
            .where((s) => s != null && s.toString().isNotEmpty)
            .join(' '),
      ].where((s) => s.isNotEmpty && s != '—').join(' · '),
    );
    if (edit == true && mounted) await _openForm(v);
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return '—';
    return [p['first_name'], p['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
  }

  /// Valid or Expired badge from the sticker expiry; a dash if none is set.
  Widget _stickerBadge(Map<String, dynamic> v) {
    final expiry = DateTime.tryParse((v['sticker_expiry'] ?? '').toString());
    if (expiry == null) {
      return const Text('—', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted));
    }
    final valid = !expiry.isBefore(DateTime.now());
    return StatusBadge(valid ? 'valid' : 'expired');
  }

  /// 0 Plate · 1 Owner · 2 Make/Model · 3 Colour · 4 Sticker · 5 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> v, int col) {
    switch (col) {
      case 0:
        return text(v['plate_number']);
      case 1:
        return text(_name(v['owner'] as Map<String, dynamic>?));
      case 2:
        return text([v['make'], v['model']]
            .where((s) => s != null && s.toString().isNotEmpty)
            .join(' '));
      case 3:
        return text(v['color']);
      case 4:
        // Sort by the expiry date behind the badge.
        return date(v['sticker_expiry']);
      case 5:
        return rankedKey(v['status'], kStatusRank);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: 'Vehicles',
      activeItem: 'Vehicles',
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
                        const Text('Registered vehicles',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                        const Spacer(),
                        PopupMenuButton<String>(
                          onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'all', child: Text('All statuses')),
                            PopupMenuItem(value: 'registered', child: Text('Registered')),
                            PopupMenuItem(value: 'active', child: Text('Active')),
                            PopupMenuItem(value: 'pending', child: Text('Pending')),
                            PopupMenuItem(value: 'flagged', child: Text('Flagged')),
                            PopupMenuItem(value: 'sold', child: Text('Sold')),
                          ],
                          child: OutlinedButton(
                              onPressed: null,
                              child: Text(_statusFilter == 'all' ? 'Filter' : titleCase(_statusFilter))),
                        ),
                        const SizedBox(width: 10),
                        if (_canCreate) FilledButton(onPressed: () => _openForm(), child: const Text('Register Vehicle')),
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
                    PopupMenuItem(value: 'registered', child: Text('Registered')),
                    PopupMenuItem(value: 'active', child: Text('Active')),
                    PopupMenuItem(value: 'pending', child: Text('Pending')),
                    PopupMenuItem(value: 'flagged', child: Text('Flagged')),
                    PopupMenuItem(value: 'sold', child: Text('Sold')),
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
                  child: FilledButton(onPressed: () => _openForm(), child: const Text('+ Vehicle')),
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
              ? const Center(child: Text('No vehicles yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: pageSlice(rows, _page).length + (pageCountFor(rows.length) > 1 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= pageSlice(rows, _page).length) {
                      return pagerFor(rows.length, _page, (p) => setState(() => _page = p));
                    }
                    final v = pageSlice(rows, _page)[i];
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
                                  Text((v['plate_number'] ?? '').toString(),
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  const SizedBox(height: 3),
                                  Text(
                                      '${_name(v['owner'] as Map<String, dynamic>?)} · ${[v['make'], v['model']].where((s) => s != null && s.toString().isNotEmpty).join(' ')}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                StatusBadge((v['status'] ?? '').toString()),
                                const SizedBox(height: 6),
                                _stickerBadge(v),
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

  /// Status cards shared by desktop and mobile. Tap one to filter the list.
  Widget _statCards() {
    return responsiveStatCards((w) => [
          DashboardStatCard(icon: Icons.directions_car_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Registered', value: '${_count('registered')}', width: w, selected: _statusFilter == 'registered', onTap: () => _tapStatus('registered')),
          DashboardStatCard(icon: Icons.check_circle_outline, iconBg: const Color(0xFFE3F1E9), label: 'Active', value: '${_count('active')}', width: w, selected: _statusFilter == 'active', onTap: () => _tapStatus('active')),
          DashboardStatCard(icon: Icons.pending_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Pending', value: '${_count('pending')}', width: w, selected: _statusFilter == 'pending', onTap: () => _tapStatus('pending')),
          DashboardStatCard(icon: Icons.flag_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Flagged', value: '${_count('flagged')}', width: w, selected: _statusFilter == 'flagged', onTap: () => _tapStatus('flagged')),
          DashboardStatCard(icon: Icons.sell_outlined, iconBg: const Color(0xFFEDEFF2), label: 'Sold', value: '${_count('sold')}', width: w, selected: _statusFilter == 'sold', onTap: () => _tapStatus('sold')),
        ]);
  }

  /// Desktop table of the visible vehicles, sortable and paged.
  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return const Center(child: Text('No vehicles yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
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
              DataColumn(label: const Text('PLATE #'), onSort: onSort),
              DataColumn(label: const Text('OWNER'), onSort: onSort),
              DataColumn(label: const Text('MAKE / MODEL'), onSort: onSort),
              DataColumn(label: const Text('COLOR'), onSort: onSort),
              DataColumn(label: const Text('STICKER'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
            ],
            rows: [
              for (final v in pageSlice(sortRows(rows), _page))
                DataRow(
                  onSelectChanged: (_) => _openDetail(v),
                  cells: [
                    DataCell(Text((v['plate_number'] ?? '').toString())),
                    DataCell(Text(_name(v['owner'] as Map<String, dynamic>?))),
                    DataCell(Text([v['make'], v['model']].where((s) => s != null && s.toString().isNotEmpty).join(' '))),
                    DataCell(Text((v['color'] ?? '—').toString())),
                    DataCell(_stickerBadge(v)),
                    DataCell(StatusBadge((v['status'] ?? '').toString())),
                  ],
                ),
            ],
          ),
      ),
    );
  }
}
