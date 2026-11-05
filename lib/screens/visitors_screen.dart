import 'dart:async';
import '../core/card_filter.dart';
import 'package:flutter/material.dart';
import '../core/fetch_all.dart';
import 'package:go_router/go_router.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/permissions.dart';
import '../core/module_registry.dart';
import '../widgets/module_detail_dialog.dart';
import '../core/visitor_rules.dart';
import '../core/local_time.dart';
import '../offline/connectivity_service.dart';
import '../offline/offline_repository.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/responsive_officer_shell.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Officer-facing Visitors screen: stat cards computed from visitor
/// logs and gate passes, plus a visitor log table.
///
/// "Expected" means a valid gate pass with no arrival logged yet.
/// "Overstayed" means still inside past the time allowed for that visit's
/// purpose (see core/visitor_rules.dart).
class AdminVisitorsScreen extends StatefulWidget {
  const AdminVisitorsScreen({super.key});

  @override
  State<AdminVisitorsScreen> createState() => _AdminVisitorsScreenState();
}

class _AdminVisitorsScreenState extends State<AdminVisitorsScreen>
    with SafeSetState<AdminVisitorsScreen>, TableSortState {
  // 1-based page for the 10-row pager (pagination_footer.dart).
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];

  /// Set by tapping a stat card: 'all', 'today', 'inside' or 'overstayed'.
  String _filter = 'all';
  int _expected = 0;
  bool _loading = true;
  String? _error;

  /// Whether this officer may log a visitor. Read-only roles must not see
  /// a button RLS would reject (visitor_logs:create).
  bool _canCreate = false;
  // True when the data came from the local cache instead of a live read.
  bool _offlineData = false;

  // Own cache keys: these queries return different shapes than other
  // visitor_logs/gate_passes fetches, so sharing a key would overwrite them.
  static const _visitorCacheKey = 'visitor_logs_officer_view';
  static const _gatePassCacheKey = 'gate_passes_active';

  @override
  void initState() {
    super.initState();
    // A dashboard card may have sent us here already narrowed (card_filter.dart).
    _filter = CardFilter.take('visitors') ?? _filter;
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads visitor logs and valid gate passes; uses the cache when offline.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!ConnectivityService.instance.isOnline.value) {
      await _loadFromCache();
      return;
    }
    try {
      final c = SupabaseService.instance.client;
      final now = DateTime.now();
      final perms = await SupabaseService.instance.getMyPermissions();
      final results = await Future.wait<dynamic>([
        fetchAllRows((from, to) => c
            .from('visitor_logs')
            .select('*, host:host_user_id(first_name, last_name)')
            .order('time_in', ascending: false)
            .order('id', ascending: false)
            .range(from, to)),
        c
            .from('gate_passes')
            .select('id')
            // Approved or pending passes still valid count, including ones for later today.
            .inFilter('status', const ['approved', 'pending'])
            .gte('valid_until', now.toIso8601String()),
      ]);
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(results[0] as List);
      final approvedPasses = List<Map<String, dynamic>>.from(results[1] as List);
      unawaited(OfflineRepository.instance.cacheRows(_visitorCacheKey, rows));
      unawaited(OfflineRepository.instance.cacheRows(_gatePassCacheKey, approvedPasses));
      final arrivedPassIds = rows.map((v) => v['gate_pass_id']).whereType<int>().toSet();
      setState(() {
        _rows = rows;
        _canCreate = canPerform(perms, 'visitor_logs', 'create');
        _expected = approvedPasses.where((p) => !arrivedPassIds.contains(p['id'])).length;
        _offlineData = false;
        _loading = false;
      });
    } catch (e) {
      await _loadFromCache(liveError: friendlyError(e));
    }
  }

  /// Shows the last cached data. Only errors if nothing is cached.
  Future<void> _loadFromCache({String? liveError}) async {
    final rows = await OfflineRepository.instance.cachedRows(_visitorCacheKey);
    final approvedPasses = await OfflineRepository.instance.cachedRows(_gatePassCacheKey);
    if (!mounted) return;
    final arrivedPassIds = rows.map((v) => v['gate_pass_id']).whereType<int>().toSet();
    setState(() {
      _rows = rows;
      _expected = approvedPasses.where((p) => !arrivedPassIds.contains(p['id'])).length;
      _offlineData = true;
      _loading = false;
      _error = rows.isEmpty ? (liveError ?? 'Offline, and nothing cached yet.') : null;
    });
  }

  /// `time_in` arrives as UTC, so this compares LOCAL days
  /// (core/local_time.dart); UTC would miscount early-morning visitors.
  bool _isToday(Map<String, dynamic> v) => isToday(v['time_in']);

  int get _today => _rows.where(_isToday).length;
  int get _insideNow => _rows.where((v) => v['time_out'] == null).length;
  // Same rule as _status(), so the count matches the badges.
  int get _overstayed => _rows.where(isOverstaying).length;

  /// The visitors the list shows, narrowed by the tapped card.
  List<Map<String, dynamic>> get _shown => switch (_filter) {
        'today' => _rows.where(_isToday).toList(),
        'inside' => _rows.where((v) => v['time_out'] == null).toList(),
        'overstayed' => _rows.where(isOverstaying).toList(),
        _ => _rows,
      };

  void _tapCard(String v) => setState(() {
        _filter = _filter == v ? 'all' : v;
        _page = 1;
      });

  String get _emptyText =>
      _rows.isEmpty ? 'No visitors logged yet.' : 'No visitors match the selected card.';

  /// Opens a read-only detail card; Edit only appears for roles that may
  /// update visitors.
  Future<void> _openDetail(Map<String, dynamic> r) async {
    final edit = await showModuleDetailDialog(
      context,
      visitors,
      r,
      subtitle: [ 'Host: ${_name(r['host'] as Map<String, dynamic>?)}' ]
          .where((s) => s.trim().isNotEmpty && !s.endsWith('—'))
          .join(' · '),
    );
    if (edit == true && mounted) await _openForm(r);
  }

  /// Opens the visitor form (new when [initial] is null) and reloads on save.
  Future<void> _openForm([Map<String, dynamic>? initial]) async {
    final saved = await showModuleFormDialog(context, visitors, initial: initial);
    if (saved == true) _load();
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return '—';
    return [p['first_name'], p['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
  }

  /// Status badge value: checked_out, overstayed or inside. Overstay is
  /// judged by the visit's purpose (core/visitor_rules.dart).
  String _status(Map<String, dynamic> v) {
    if (v['time_out'] != null) return 'checked_out';
    return isOverstaying(v) ? 'overstayed' : 'inside';
  }

  /// Purpose column: the category, with any typed detail underneath.
  /// Deliveries are tinted so they stand out.
  Widget _purposeCell(Map<String, dynamic> v) {
    final type = v['purpose_type']?.toString();
    final detail = (v['purpose'] ?? '').toString().trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDelivery(type))
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(Icons.local_shipping_outlined,
                    size: 14, color: Color(0xFF8A6300)),
              ),
            Text(visitorPurposeLabel(type),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isDelivery(type) ? FontWeight.w600 : FontWeight.w400,
                    color: isDelivery(type)
                        ? const Color(0xFF8A6300)
                        : AppColors.textPrimary)),
          ],
        ),
        if (detail.isNotEmpty)
          Text(detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }

  /// Formats a timestamp as a local 12-hour time; must be local, not raw UTC.
  String _time(String? iso) {
    final t = localTime(iso);
    if (t == null) return '—';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final period = t.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
  }

  /// 0 Visitor · 1 Host · 2 Purpose · 3 Vehicle · 4 Time in · 5 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> v, int col) {
    switch (col) {
      case 0:
        return text(v['visitor_name']);
      case 1:
        return text(_name(v['host'] as Map<String, dynamic>?));
      case 2:
        return text(visitorPurposeLabel(v['purpose_type']?.toString()));
      case 3:
        return text(v['vehicle_plate']);
      case 4:
        return date(v['time_in']);
      case 5:
        return rankedKey(_status(v), kStatusRank);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: 'Visitor Management',
      activeItem: 'Visitors',
      activeTab: 'Services',
      desktopChild: _desktopBody(),
      mobileChild: _mobileBody(),
    );
  }

  /// Notice shown while displaying cached data.
  Widget _offlineBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFBEFD6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      child: const Text(
        "Offline — showing the last synced data. New visitors will send once you're back online.",
        style: TextStyle(fontSize: 12, color: Color(0xFF8A6300)),
      ),
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
                    if (_offlineData) _offlineBanner(),
                    Row(
                      children: [
                        const Text('Visitor log',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                        const Spacer(),
                        if (_canCreate) FilledButton(onPressed: () => _openForm(), child: const Text('Register Visitor')),
                      ],
                    ),
                    const SizedBox(height: 18),
                    responsiveStatCards((w) => [
                      DashboardStatCard(icon: Icons.today_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Today', value: '$_today', width: w, selected: _filter == 'today', onTap: () => _tapCard('today')),
                      DashboardStatCard(icon: Icons.login_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Inside Now', value: '$_insideNow', width: w, selected: _filter == 'inside', onTap: () => _tapCard('inside')),
                      DashboardStatCard(icon: Icons.event_available_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Expected', value: '$_expected', width: w, caption: 'Approved gate passes', hint: 'Gate Passes', onTap: () => context.push('/admin/gate_passes')),
                      DashboardStatCard(icon: Icons.warning_amber_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Overstayed', value: '$_overstayed', width: w, selected: _filter == 'overstayed', onTap: () => _tapCard('overstayed')),
                    ]),
                    const SizedBox(height: 20),
                    Expanded(child: _buildTable()),
                  ],
                ),
              );
  }

  // ---------- mobile body ----------
  //
  /// Phone layout: stat cards plus a card per visitor.
  Widget _mobileBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    return Column(
      children: [
        if (_offlineData) _offlineBanner(),
        if (_canCreate)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton(
              onPressed: () => _openForm(),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
              child: const Text('Register Visitor'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: responsiveStatCards((w) => [
            DashboardStatCard(icon: Icons.today_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Today', value: '$_today', width: w, selected: _filter == 'today', onTap: () => _tapCard('today')),
            DashboardStatCard(icon: Icons.login_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Inside Now', value: '$_insideNow', width: w, selected: _filter == 'inside', onTap: () => _tapCard('inside')),
            DashboardStatCard(icon: Icons.event_available_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Expected', value: '$_expected', width: w, caption: 'Approved gate passes', hint: 'Gate Passes', onTap: () => context.push('/admin/gate_passes')),
            DashboardStatCard(icon: Icons.warning_amber_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Overstayed', value: '$_overstayed', width: w, selected: _filter == 'overstayed', onTap: () => _tapCard('overstayed')),
          ]),
        ),
        Expanded(
          child: _shown.isEmpty
              ? Center(
                  child: Text(_emptyText, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: pageSlice(_shown, _page).length + (pageCountFor(_shown.length) > 1 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= pageSlice(_shown, _page).length) {
                      return pagerFor(_shown.length, _page, (p) => setState(() => _page = p));
                    }
                    final v = pageSlice(_shown, _page)[i];
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
                                  Text((v['visitor_name'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  const SizedBox(height: 3),
                                  Text('Host: ${_name(v['host'] as Map<String, dynamic>?)} · ${_time(v['time_in']?.toString())}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            StatusBadge(_status(v)),
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

  /// Desktop visitor table for the filtered, sorted, paged rows.
  Widget _buildTable() {
    if (_shown.isEmpty) {
      return Center(child: Text(_emptyText, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)));
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: fullWidthTable(
            footer: pagerFor(_shown.length, _page, (p) => setState(() => _page = p)),
            
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
              DataColumn(label: const Text('VISITOR'), onSort: onSort),
              DataColumn(label: const Text('HOST'), onSort: onSort),
              DataColumn(label: const Text('PURPOSE'), onSort: onSort),
              DataColumn(label: const Text('VEHICLE'), onSort: onSort),
              DataColumn(label: const Text('TIME IN'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
            ],
            rows: [
              for (final v in pageSlice(sortRows(_shown), _page))
                DataRow(
                  onSelectChanged: (_) => _openDetail(v),
                  cells: [
                    DataCell(Text((v['visitor_name'] ?? '').toString())),
                    DataCell(Text(_name(v['host'] as Map<String, dynamic>?))),
                    DataCell(_purposeCell(v)),
                    DataCell(Text((v['vehicle_plate'] ?? '—').toString())),
                    DataCell(Text(_time(v['time_in']?.toString()))),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBadge(_status(v)),
                        // How far past the allowed time.
                        if (isOverstaying(v)) ...[
                          const SizedBox(width: 6),
                          Text(overstayLabel(v),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFA82F2F))),
                        ],
                      ],
                    )),
                  ],
                ),
            ],
          ),
      ),
    );
  }
}
