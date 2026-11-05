import 'package:flutter/material.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/module_registry.dart';
import '../core/permissions.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/admin_shell.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/person_files_dialog.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../widgets/person_link.dart';
import '../widgets/reset_password_action.dart';
import '../core/safe_state.dart';

/// Officer Tenants directory with Total, Active Leases and Expiring Soon
/// cards. Expiring Soon means the lease ends within 30 days.
class AdminTenantsScreen extends StatefulWidget {
  const AdminTenantsScreen({super.key});

  @override
  State<AdminTenantsScreen> createState() => _AdminTenantsScreenState();
}

class _AdminTenantsScreenState extends State<AdminTenantsScreen>
    with SafeSetState<AdminTenantsScreen>, TableSortState {
  // 1-based page for the 10-row pager (pagination_footer.dart).
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];

  /// Set by tapping a stat card: 'all', 'active' or 'expiring'.
  String _filter = 'all';
  List<Map<String, dynamic>> _lots = [];

  bool _canApproveAddress = false;
  bool _canReviewFiles = false;

  /// Names link to the person page only with accounts:read.
  bool _canOpenPerson = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Names A-Z until a header is clicked.
    sortColumn = 0;
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads tenants, lots and the officer's permissions together.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        SupabaseService.instance.client
            .from('users')
            .select('id, first_name, last_name, email, status, lease_end_date, '
                'lot_id, requested_lot_id, account_label, '
                'landlord:landlord_id(first_name, last_name), roles!inner(name)')
            .eq('roles.name', 'tenant')
            .order('created_at', ascending: false)
            .limit(500),
        SupabaseService.instance.client
            .from('lots')
            .select('id, lot_number, street_address, blocks(block_name, phase)'),
        SupabaseService.instance.getMyPermissions(),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(results[0] as List);
        _lots = List<Map<String, dynamic>>.from(results[1] as List);
        // Address approval needs users:update.
        _canApproveAddress =
            canPerform(results[2] as Map<String, Set<String>>, 'users', 'update');
        // Reviewing a tenant's uploaded files needs documents:update.
        _canReviewFiles =
            canPerform(results[2] as Map<String, Set<String>>, 'documents', 'update');
        _canOpenPerson =
            canAccessModule(results[2] as Map<String, Set<String>>, 'accounts');
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

  /// Readable lot name, like "Phase 4 · Block A · Lot 12 — Hillview".
  String _lotLabel(dynamic lotId) {
    if (lotId == null) return '—';
    for (final l in _lots) {
      if (l['id'] == lotId) {
        final blocks = l['blocks'] as Map<String, dynamic>?;
        final block = blocks?['block_name'] ?? '—';
        final phase = (blocks?['phase'] ?? '').toString().trim();
        var base = 'Block $block · Lot ${l['lot_number'] ?? ''}';
        if (phase.isNotEmpty) base = 'Phase $phase · $base';
        final street = (l['street_address'] ?? '').toString().trim();
        return street.isEmpty ? base : '$base — $street';
      }
    }
    return '—';
  }

  /// Gives the tenant the requested lot and marks that lot occupied.
  Future<void> _approveAddress(Map<String, dynamic> u) async {
    final requested = u['requested_lot_id'];
    if (requested == null) return;
    try {
      final client = SupabaseService.instance.client;
      await client.from('users').update({
        'lot_id': requested,
        'requested_lot_id': null,
        'address': _lotLabel(requested),
      }).eq('id', u['id']);
      await client.from('lots').update({'status': 'occupied'}).eq('id', requested);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not approve. ${friendlyError(e)}')));
      }
    }
  }

  /// Clears the tenant's pending address request.
  Future<void> _rejectAddress(Map<String, dynamic> u) async {
    try {
      await SupabaseService.instance.client
          .from('users')
          .update({'requested_lot_id': null}).eq('id', u['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not reject. ${friendlyError(e)}')));
      }
    }
  }

  /// Table address cell: the lot, or the pending request with approve/reject.
  Widget _addressCell(Map<String, dynamic> u) {
    if (u['lot_id'] != null) return Text(_lotLabel(u['lot_id']));
    if (u['requested_lot_id'] == null) {
      return const Text('—', style: TextStyle(color: AppColors.textMuted));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Requested: ${_lotLabel(u['requested_lot_id'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        if (_canApproveAddress) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Approve address',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF1A6B43)),
            onPressed: () => _approveAddress(u),
          ),
          IconButton(
            tooltip: 'Reject request',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.redAccent),
            onPressed: () => _rejectAddress(u),
          ),
        ],
      ],
    );
  }

  DateTime? _leaseEnd(Map<String, dynamic> u) => DateTime.tryParse((u['lease_end_date'] ?? '').toString());

  int get _total => _rows.length;
  // Active means the lease end date has not passed.
  int get _activeLeases => _rows.where(_leaseActive).length;
  int get _expiringSoon => _rows.where((u) => _leaseStatus(u) == 'expiring').length;

  bool _leaseActive(Map<String, dynamic> u) {
    final st = _leaseStatus(u);
    return st == 'active' || st == 'expiring';
  }

  /// The rows the list shows, narrowed by the tapped card.
  List<Map<String, dynamic>> get _shown => switch (_filter) {
        'active' => _rows.where(_leaseActive).toList(),
        'expiring' => _rows.where((u) => _leaseStatus(u) == 'expiring').toList(),
        _ => _rows,
      };

  void _tapCard(String v) => setState(() {
        _filter = _filter == v ? 'all' : v;
        _page = 1;
      });

  /// 'expired', 'expiring' (within 30 days), 'active', or a dash if no end date.
  String _leaseStatus(Map<String, dynamic> u) {
    final d = _leaseEnd(u);
    if (d == null) return '—';
    final days = d.difference(DateTime.now()).inDays;
    if (days < 0) return 'expired';
    if (days <= 30) return 'expiring';
    return 'active';
  }

  Future<void> _openForm(Map<String, dynamic> initial) async {
    final saved = await showModuleFormDialog(context, tenants, initial: initial);
    if (saved == true) _load();
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return '—';
    return [p['first_name'], p['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
  }

  /// 0 Name · 1 Landlord · 2 Address · 3 Lease end · 4 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> u, int col) {
    switch (col) {
      case 0:
        return text([u['first_name'], u['last_name']].where((s) => s != null).join(' '));
      case 1:
        return text(_name(u['landlord'] as Map<String, dynamic>?));
      case 2:
        // Sort on the lot label; the query does not select `address`.
        return text(_lotLabel(u['lot_id']));
      case 3:
        return date(u['lease_end_date']);
      case 4:
        return rankedKey(_leaseStatus(u), kStatusRank);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Tenants',
      activeItem: 'Tenants',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text('All tenants',
                              style: TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 18),
                      responsiveStatCards((w) => [
                            DashboardStatCard(icon: Icons.groups_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Total Tenants', value: '$_total', width: w, hint: 'Show all', onTap: () => setState(() { _filter = 'all'; _page = 1; })),
                            DashboardStatCard(icon: Icons.description_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Active Leases', value: '$_activeLeases', width: w, selected: _filter == 'active', onTap: () => _tapCard('active')),
                            DashboardStatCard(icon: Icons.event_busy_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Expiring Soon', value: '$_expiringSoon', width: w, selected: _filter == 'expiring', onTap: () => _tapCard('expiring')),
                          ]),
                      const SizedBox(height: 20),
                      // Cards on narrow screens, so actions stay in reach.
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) =>
                              box.maxWidth < 700 ? _cards() : _buildTable(),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }


  Widget get _emptyState => Center(
      child: Text(_rows.isEmpty ? 'No tenants yet.' : 'No tenants match the selected card.',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted)));

  /// Opens the tenant's uploaded files.
  Future<void> _viewTenantFiles(Map<String, dynamic> u) => showPersonFilesDialog(
        context,
        userId: u['id'] as Object,
        personName:
            [u['first_name'], u['last_name']].where((s) => s != null).join(' '),
        roleLabel: 'tenant',
      );

  /// Phone layout: one card per tenant with the same actions as the table.
  Widget _cards() {
    final all = sortRows(_shown);
    if (all.isEmpty) return _emptyState;
    // Paged like the desktop table, so a phone does not render every row.
    final rows = pageSlice(all, _page);
    final paged = pageCountFor(all.length) > 1;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: rows.length + (paged ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i >= rows.length) {
          return pagerFor(all.length, _page, (p) => setState(() => _page = p));
        }
        final u = rows[i];
        final name = [u['first_name'], u['last_name']]
            .where((s) => s != null)
            .join(' ')
            .trim();
        final landlord = _name(u['landlord'] as Map<String, dynamic>?);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PersonNameLink(
                      userId: u['id'],
                      name: name,
                      enabled: _canOpenPerson,
                      accountLabel: u['account_label'],
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  StatusBadge(_leaseStatus(u)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Landlord: $landlord',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary)),
              Text('Lease ends: ${(u['lease_end_date'] ?? '—')}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              _addressBlock(u),
              if (_canApproveAddress || _canReviewFiles) ...[
                const Divider(height: 18),
                Row(
                  children: [
                    if (_canApproveAddress)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openForm(u),
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: const Text('Edit'),
                        ),
                      ),
                    if (_canApproveAddress && _canReviewFiles)
                      const SizedBox(width: 8),
                    if (_canReviewFiles)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _viewTenantFiles(u),
                          icon: const Icon(Icons.folder_outlined, size: 15),
                          label: const Text('Files'),
                        ),
                      ),
                  ],
                ),
                // Own row: three buttons across a phone card are too narrow.
                if (_canApproveAddress) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ResetPasswordButton(account: u),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  /// Card address, stacked because `_addressCell` overflows a narrow card.
  Widget _addressBlock(Map<String, dynamic> u) {
    if (u['lot_id'] != null) {
      return Text(_lotLabel(u['lot_id']),
          style:
              const TextStyle(fontSize: 11.5, color: AppColors.textSecondary));
    }
    if (u['requested_lot_id'] == null) {
      return const Text('No address on record',
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Requested: ${_lotLabel(u['requested_lot_id'])}',
            style:
                const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        if (_canApproveAddress)
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _approveAddress(u),
                icon: const Icon(Icons.check_circle_outline,
                    size: 16, color: Color(0xFF1A6B43)),
                label: const Text('Approve',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1A6B43))),
              ),
              TextButton.icon(
                onPressed: () => _rejectAddress(u),
                icon: const Icon(Icons.cancel_outlined,
                    size: 16, color: Colors.redAccent),
                label: const Text('Reject',
                    style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              ),
            ],
          ),
      ],
    );
  }

  /// Desktop table of the shown tenants, sortable and paged.
  Widget _buildTable() {
    if (_shown.isEmpty) return _emptyState;
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
              DataColumn(label: const Text('NAME'), onSort: onSort),
              DataColumn(label: const Text('LANDLORD'), onSort: onSort),
              DataColumn(label: const Text('ADDRESS'), onSort: onSort),
              DataColumn(label: const Text('LEASE END'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
              // Hidden for read-only roles.
              if (_canApproveAddress || _canReviewFiles)
                const DataColumn(label: Text('ACTIONS')),
            ],
            rows: [
              for (final u in pageSlice(sortRows(_shown), _page))
                DataRow(cells: [
                  DataCell(PersonNameLink(
                      userId: u['id'],
                      name: [u['first_name'], u['last_name']].where((s) => s != null).join(' '),
                      enabled: _canOpenPerson,
                      accountLabel: u['account_label'])),
                  DataCell(Text(_name(u['landlord'] as Map<String, dynamic>?))),
                  DataCell(_addressCell(u)),
                  DataCell(Text((u['lease_end_date'] ?? '—').toString())),
                  DataCell(StatusBadge(_leaseStatus(u))),
                  if (_canApproveAddress || _canReviewFiles)
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_canApproveAddress)
                        TextButton(
                            onPressed: () => _openForm(u), child: const Text('Edit')),
                      if (_canReviewFiles)
                        TextButton(
                          onPressed: () => _viewTenantFiles(u),
                          child: const Text('Files'),
                        ),
                      // Needs users:update; the Edge Function checks it again.
                      if (_canApproveAddress)
                        TextButton(
                          onPressed: () => sendPasswordResetFor(context, u),
                          child: const Text('Reset password'),
                        ),
                    ])),
                ]),
            ],
          ),
      ),
    );
  }
}
