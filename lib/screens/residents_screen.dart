import 'package:flutter/material.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/module_registry.dart';
import '../core/permissions.dart';
import '../core/roles.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/admin_shell.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/person_files_dialog.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../widgets/reset_password_action.dart';
import '../widgets/person_link.dart';
import '../core/safe_state.dart';

/// Officer directory of residents with stat cards (Total/Active/Pending/
/// Officers). No Add button: residents self-register and officers approve
/// them on the Approvals screen. Edit opens the account form.
class AdminResidentsScreen extends StatefulWidget {
  const AdminResidentsScreen({super.key});

  @override
  State<AdminResidentsScreen> createState() => _AdminResidentsScreenState();
}

class _AdminResidentsScreenState extends State<AdminResidentsScreen>
    with SafeSetState<AdminResidentsScreen>, TableSortState {
  // Current page, starting at 1.
  int _page = 1;

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _lots = [];

  bool _canApproveAddress = false;
  // Edit needs users:update; viewing files needs documents:update. With
  // neither, the ACTIONS column is hidden.
  bool _canEditResidents = false;
  bool _canReviewFiles = false;

  /// Names link to /admin/people/:id, which needs accounts:read.
  bool _canOpenPerson = false;
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    // Names A-Z until a header is clicked.
    sortColumn = 0;
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads users, lots and the current officer's permissions.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        SupabaseService.instance.client
            .from('users')
            .select('id, first_name, last_name, email, phone, status, role_id, '
                'lot_id, requested_lot_id, account_label, roles(name, display_name)')
            .order('created_at', ascending: false)
            .limit(1000),
        SupabaseService.instance.client
            .from('lots')
            .select('id, lot_number, street_address, blocks(block_name, phase)'),
        SupabaseService.instance.getMyPermissions(),
      ]);
      if (!mounted) return;
      setState(() {
        _allUsers = List<Map<String, dynamic>>.from(results[0] as List);
        _lots = List<Map<String, dynamic>>.from(results[1] as List);
        // Address approval uses the users/update permission.
        final perms = results[2] as Map<String, Set<String>>;
        _canApproveAddress = canPerform(perms, 'users', 'update');
        _canEditResidents = canPerform(perms, 'users', 'update');
        _canReviewFiles = canPerform(perms, 'documents', 'update');
        _canOpenPerson = canAccessModule(perms, 'accounts');
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

  /// "Phase 4 · Block A · Lot 12 — Hillview".
  ///
  /// Phase and street are added only when the record has them. The phase
  /// comes from the lot's block. Same format as listings_screen.
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

  /// Approves a requested address: sets lot_id (the database allows this only
  /// for users/update), copies the label to the address column, clears the
  /// request and marks the lot occupied.
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

  /// Rejects a requested address by clearing the request.
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

  String _roleName(Map<String, dynamic> u) => (u['roles'] as Map<String, dynamic>?)?['name']?.toString() ?? '';

  List<Map<String, dynamic>> get _residents =>
      _allUsers.where((u) => _roleName(u) == 'member_resident').toList();

  int get _total => _residents.length;
  int get _active => _residents.where((u) => u['status'] == 'active').length;
  int get _pending => _residents.where((u) => u['status'] == 'pending_verification').length;
  int get _officers => _allUsers.where((u) => officerRoles.contains(_roleName(u))).length;

  /// Rows for the current filter. 'officers' shows officer accounts, which
  /// are otherwise not listed.
  List<Map<String, dynamic>> get _visible => switch (_statusFilter) {
        'all' => _residents,
        'officers' => _allUsers.where((u) => officerRoles.contains(_roleName(u))).toList(),
        _ => _residents.where((u) => u['status'] == _statusFilter).toList(),
      };

  void _tapCard(String v) => setState(() {
        _statusFilter = _statusFilter == v ? 'all' : v;
        _page = 1;
      });

  Future<void> _openForm(Map<String, dynamic> initial) async {
    final saved = await showModuleFormDialog(context, residents, initial: initial);
    if (saved == true) _load();
  }

  /// 0 Name · 1 Email · 2 Phone · 3 Address · 4 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> u, int col) {
    switch (col) {
      case 0:
        return text([u['first_name'], u['last_name']].where((s) => s != null).join(' '));
      case 1:
        return text(u['email']);
      case 2:
        return text(u['phone']);
      case 3:
        // Sort on the label the cell shows; users.address is not selected
        // and can be stale.
        return text(_lotLabel(u['lot_id']));
      case 4:
        return rankedKey(u['status'], kStatusRank);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Residents',
      activeItem: 'Residents',
      child: _loading
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
                          const Expanded(
                            child: Text('All residents',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                          ),
                          const SizedBox(width: 10),
                          PopupMenuButton<String>(
                            onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'all', child: Text('All statuses')),
                              PopupMenuItem(value: 'active', child: Text('Active')),
                              PopupMenuItem(value: 'pending_verification', child: Text('Pending')),
                              PopupMenuItem(value: 'suspended', child: Text('Suspended')),
                              PopupMenuItem(value: 'inactive', child: Text('Inactive')),
                            ],
                            child: OutlinedButton(
                                onPressed: null,
                                child: Text(_statusFilter == 'all' ? 'Filter' : titleCase(_statusFilter))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      responsiveStatCards((w) => [
                            DashboardStatCard(icon: Icons.people_outline, iconBg: const Color(0xFFE3F1E9), label: 'Total', value: '$_total', width: w, hint: 'Show all', onTap: () => setState(() { _statusFilter = 'all'; _page = 1; })),
                            DashboardStatCard(icon: Icons.check_circle_outline, iconBg: const Color(0xFFE2F0F7), label: 'Active', value: '$_active', width: w, selected: _statusFilter == 'active', onTap: () => _tapCard('active')),
                            DashboardStatCard(icon: Icons.hourglass_top_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Pending', value: '$_pending', width: w, selected: _statusFilter == 'pending_verification', onTap: () => _tapCard('pending_verification')),
                            DashboardStatCard(icon: Icons.shield_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Officers', value: '$_officers', width: w, selected: _statusFilter == 'officers', onTap: () => _tapCard('officers')),
                          ]),
                      const SizedBox(height: 20),
                      // Under 700px wide, show cards so the actions stay on screen.
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


  /// Approved address, or the pending request with inline Approve/Reject
  /// for officers holding users/update (Secretary/President/Super Admin).
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

  /// Opens a resident's private "My Files" uploads (also used by Tenants).
  Future<void> _viewResidentFiles(Map<String, dynamic> u) => showPersonFilesDialog(
        context,
        userId: u['id'] as Object,
        personName: [u['first_name'], u['last_name']].where((s) => s != null).join(' '),
      );

  static const _emptyState = Center(
      child: Text('No residents yet.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted)));

  /// Phone layout: one card per resident with the same actions as the table.
  /// Uses _addressBlock, not _addressCell, which overflows a narrow card.
  Widget _cards() {
    final all = sortRows(_visible);
    if (all.isEmpty) return _emptyState;
    // Paged like the table.
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
        final name =
            [u['first_name'], u['last_name']].where((s) => s != null).join(' ').trim();
        final phone = (u['phone'] ?? '').toString().trim();
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
                  StatusBadge((u['status'] ?? '').toString()),
                ],
              ),
              const SizedBox(height: 4),
              Text((u['email'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textSecondary)),
              if (phone.isNotEmpty)
                Text(phone,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              _addressBlock(u),
              if (_canEditResidents || _canReviewFiles) ...[
                const Divider(height: 18),
                Row(
                  children: [
                    if (_canEditResidents)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openForm(u),
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: const Text('Edit'),
                        ),
                      ),
                    if (_canEditResidents && _canReviewFiles)
                      const SizedBox(width: 8),
                    if (_canReviewFiles)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _viewResidentFiles(u),
                          icon: const Icon(Icons.folder_outlined, size: 15),
                          label: const Text('Files'),
                        ),
                      ),
                  ],
                ),
                // Own full-width row; "Reset password" is too wide beside the others.
                if (_canEditResidents) ...[
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

  /// Card address: the label, or the pending request with Approve and
  /// Reject underneath.
  Widget _addressBlock(Map<String, dynamic> u) {
    if (u['lot_id'] != null) {
      return Text(_lotLabel(u['lot_id']),
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary));
    }
    if (u['requested_lot_id'] == null) {
      return const Text('No address on record',
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Requested: ${_lotLabel(u['requested_lot_id'])}',
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textSecondary)),
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

  /// Desktop layout: sortable, paged table of residents.
  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) return _emptyState;
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
              DataColumn(label: const Text('NAME'), onSort: onSort),
              DataColumn(label: const Text('EMAIL'), onSort: onSort),
              DataColumn(label: const Text('PHONE'), onSort: onSort),
              DataColumn(label: const Text('ADDRESS'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
              // Only shown to roles that can act.
              if (_canEditResidents || _canReviewFiles) const DataColumn(label: Text('ACTIONS')),
            ],
            rows: [
              for (final u in pageSlice(sortRows(rows), _page))
                DataRow(cells: [
                  DataCell(PersonNameLink(
                      userId: u['id'],
                      name: [u['first_name'], u['last_name']].where((s) => s != null).join(' '),
                      enabled: _canOpenPerson,
                      accountLabel: u['account_label'])),
                  DataCell(Text((u['email'] ?? '').toString())),
                  DataCell(Text((u['phone'] ?? '—').toString())),
                  DataCell(_addressCell(u)),
                  DataCell(StatusBadge((u['status'] ?? '').toString())),
                  if (_canEditResidents || _canReviewFiles)
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_canEditResidents)
                        TextButton(onPressed: () => _openForm(u), child: const Text('Edit')),
                      if (_canReviewFiles)
                        TextButton(onPressed: () => _viewResidentFiles(u), child: const Text('Files')),
                      // Same permission as Edit. A row action, not a form
                      // field: the form is shared by every registry module.
                      if (_canEditResidents)
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
