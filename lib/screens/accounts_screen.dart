import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/permissions.dart';
import '../core/roles.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/admin_shell.dart';
import '../widgets/app_toast.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/pending_approvals_view.dart';
import '../widgets/roster_import_dialog.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../widgets/person_link.dart';
import '../widgets/reset_password_action.dart';
import '../core/dialog_sizing.dart';
import '../core/tour_anchors.dart';
import '../core/dialog_controllers.dart';
import '../core/safe_state.dart';

/// All Accounts: a directory of every user account, with edit, role change,
/// delete and roster import for officers who hold those permissions.
class AllAccountsScreen extends StatefulWidget {
  /// 0 = All Accounts tab, 1 = Pending Approvals tab.
  final int initialTab;
  const AllAccountsScreen({super.key, this.initialTab = 0});

  @override
  State<AllAccountsScreen> createState() => _AllAccountsScreenState();
}

class _AllAccountsScreenState extends State<AllAccountsScreen>
    with SafeSetState<AllAccountsScreen>, TableSortState {
  // 1-based page for the 10-row pager.
  int _page = 1;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _roles = []; // id, name, display_name
  bool _canEdit = false;

  /// Needs users:delete, checked separately from users:update.
  bool _canDelete = false;

  /// Roster import needs users:create.
  bool _canImport = false;

  /// Names link to /admin/people/:id only when the role holds accounts:read.
  bool _canOpenPerson = false;
  bool _loading = true;
  String? _error;
  String _roleFilter = 'all';

  /// Set by a stat card: 'all', 'officers', 'residents' or 'pending'.
  /// Picking a role from the menu clears it.
  String _cardFilter = 'all';

  /// Retired accounts are hidden unless this is on.
  bool _showRetired = false;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    // Sort by name A-Z until a header is clicked.
    sortColumn = 0;
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads users, roles and the officer's permissions.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = SupabaseService.instance.client;
      final results = await Future.wait<dynamic>([
        c
            .from('users')
            .select('id, first_name, last_name, email, phone, status, created_at, '
                'role_id, deleted_at, account_label, roles(name, display_name)')
            .order('created_at', ascending: false)
            .limit(2000),
        c.from('roles').select('id, name, display_name').order('id'),
        SupabaseService.instance.getMyPermissions(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = List<Map<String, dynamic>>.from(results[0] as List);
        _roles = List<Map<String, dynamic>>.from(results[1] as List);
        _canEdit = canPerform(results[2] as Map<String, Set<String>>, 'users', 'update');
        _canDelete = canPerform(results[2] as Map<String, Set<String>>, 'users', 'delete');
        // Matches the permission import_homeowners() checks on the server.
        _canImport = canPerform(results[2] as Map<String, Set<String>>, 'users', 'create');
        _canOpenPerson =
            canAccessModule(results[2] as Map<String, Set<String>>, 'accounts');
        _pendingCount = _pending;
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

  String _roleKey(Map<String, dynamic> u) => (u['roles'] as Map?)?['name']?.toString() ?? '';
  String _roleLabel(Map<String, dynamic> u) =>
      (u['roles'] as Map?)?['display_name']?.toString() ?? _roleKey(u);
  String _fullName(Map<String, dynamic> u) =>
      [u['first_name'], u['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');

  /// (key, label) for each role in use, sorted by label.
  List<(String, String)> get _roleOptions {
    final seen = <String, String>{};
    for (final u in _users) {
      final k = _roleKey(u);
      if (k.isNotEmpty) seen[k] = _roleLabel(u);
    }
    final list = seen.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  /// A retired account: removed, but kept because records still point to it.
  /// Marked by deleted_at, or by a placeholder @deleted.invalid email.
  bool _isRetired(Map<String, dynamic> u) =>
      u['deleted_at'] != null ||
      (u['email']?.toString().endsWith('@deleted.invalid') ?? false);

  int get _retiredCount => _users.where(_isRetired).length;

  /// Accounts still in use (retired ones excluded from the counts).
  List<Map<String, dynamic>> get _activeUsers =>
      _users.where((u) => !_isRetired(u)).toList();

  /// Rows left after the retired, role and stat card filters.
  List<Map<String, dynamic>> get _visible {
    return _users.where((u) {
      if (!_showRetired && _isRetired(u)) return false;
      if (_roleFilter != 'all' && _roleKey(u) != _roleFilter) return false;
      switch (_cardFilter) {
        case 'officers':
          if (!officerRoles.contains(_roleKey(u))) return false;
        case 'residents':
          if (!{'member_resident', 'tenant'}.contains(_roleKey(u))) return false;
        case 'pending':
          if (u['status'] != 'pending_verification') return false;
      }
      return true;
    }).toList();
  }

  int get _total => _activeUsers.length;
  int get _officers => _activeUsers.where((u) => officerRoles.contains(_roleKey(u))).length;
  int get _residentsTenants =>
      _activeUsers.where((u) => {'member_resident', 'tenant'}.contains(_roleKey(u))).length;
  int get _pending => _users.where((u) => u['status'] == 'pending_verification').length;

  /// Account editor: name, phone, status, role and account type in one place.
  /// Email is read-only here because it is the login.
  Future<void> _editAccount(Map<String, dynamic> u) async {
    final firstCtrl = TextEditingController(text: (u['first_name'] ?? '').toString());
    final lastCtrl = TextEditingController(text: (u['last_name'] ?? '').toString());
    final phoneCtrl = TextEditingController(text: (u['phone'] ?? '').toString());
    int? roleId = u['role_id'] as int?;
    // A dropdown value not in its items throws, so clear an unknown role.
    if (!_roles.any((r) => r['id'] == roleId)) roleId = null;
    const statuses = ['active', 'pending_verification', 'suspended', 'inactive'];
    String status = (u['status'] ?? 'active').toString();
    if (!statuses.contains(status)) status = 'active';
    // null = a real account. 'test' / 'evaluation' put a tag beside the name.
    String? accountLabel = u['account_label'] as String?;

    const dec = InputDecoration(border: OutlineInputBorder(), isDense: true);
    Widget lbl(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 12),
          child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
        );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Edit account — ${_fullName(u).isEmpty ? (u['email'] ?? 'account') : _fullName(u)}'),
          content: SizedBox(
            width: dialogContentWidth(context, 380),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  lbl('First name'),
                  TextField(controller: firstCtrl, inputFormatters: nameInputFormatters, decoration: dec),
                  lbl('Last name'),
                  TextField(controller: lastCtrl, inputFormatters: nameInputFormatters, decoration: dec),
                  lbl('Phone'),
                  TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, inputFormatters: phoneInputFormatters, decoration: dec),
                  lbl('Email (login — changed via password reset)'),
                  Text((u['email'] ?? '—').toString(),
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  // Sends a reset email right away, independent of Save.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ResetPasswordButton(account: u, dense: true),
                    ),
                  ),
                  lbl('Status'),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    isExpanded: true,
                    decoration: dec,
                    items: [
                      for (final s in statuses)
                        DropdownMenuItem(value: s, child: Text(titleCase(s.replaceAll('_', ' ')))),
                    ],
                    onChanged: (v) => setLocal(() => status = v ?? status),
                  ),
                  lbl('Role'),
                  DropdownButtonFormField<int>(
                    initialValue: roleId,
                    isExpanded: true,
                    decoration: dec,
                    items: [
                      for (final r in _roles)
                        DropdownMenuItem(
                          value: r['id'] as int,
                          child: Text((r['display_name'] ?? r['name']).toString(),
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => roleId = v),
                  ),
                  lbl('Account type'),
                  DropdownButtonFormField<String?>(
                    initialValue: accountLabel,
                    isExpanded: true,
                    decoration: dec,
                    items: const [
                      DropdownMenuItem<String?>(value: null, child: Text('Real account')),
                      DropdownMenuItem<String?>(value: 'test', child: Text('Test account')),
                      DropdownMenuItem<String?>(value: 'evaluation', child: Text('Evaluation account')),
                    ],
                    onChanged: (v) => setLocal(() => accountLabel = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save changes')),
          ],
        ),
      ),
    );

    if (saved == true) {
      try {
        await SupabaseService.instance.client.from('users').update({
          'first_name': firstCtrl.text.trim(),
          'last_name': lastCtrl.text.trim(),
          'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
          'status': status,
          'role_id': roleId,
          'account_label': accountLabel,
        }).eq('id', u['id']);
        if (mounted) AppToast.success(context, message: 'Account updated.');
        _load();
      } catch (e) {
        if (mounted) AppToast.error(context, message: 'Could not update account. ${friendlyError(e)}');
      }
    }
    disposeAfterDialogCloses([firstCtrl, lastCtrl, phoneCtrl]);
  }

  /// Deletes an account via the `delete-account` Edge Function (service
  /// role). Revokes their login and either removes the row or anonymizes it
  /// when linked history (bills, complaints, etc.) blocks a hard delete.
  Future<void> _deleteAccount(Map<String, dynamic> u) async {
    final name = _fullName(u).isEmpty ? (u['email'] ?? 'this account').toString() : _fullName(u);

    // Dry run first, so the dialog can show what will be erased and kept.
    Map<String, dynamic>? preview;
    try {
      final res = await SupabaseService.instance.client.functions
          .invoke('delete-account', body: {'user_id': u['id'], 'dry_run': true});
      preview = res.data as Map<String, dynamic>?;
      if (preview?['error'] != null) throw Exception(preview!['error']);
    } catch (e) {
      if (mounted) {
        AppToast.error(context, message: 'Could not check this account. ${_deleteError(e)}');
      }
      return;
    }
    if (!mounted) return;

    final willRetire = preview?['mode'] == 'retired';
    final personal = Map<String, dynamic>.from(preview?['personal'] as Map? ?? {});
    final retained = Map<String, dynamic>.from(preview?['retained'] as Map? ?? {});
    final tenantCount = (preview?['tenants_under_this_landlord'] as num?)?.toInt() ?? 0;

    String summarize(Map<String, dynamic> m) {
      const labels = {
        'household_members': 'household member',
        'vehicles': 'vehicle',
        'gate_passes': 'gate pass',
        'move_requests': 'move request',
        'documents': 'document',
        'notifications': 'notification',
        'bills': 'bill',
        'payments': 'payment',
        'complaints': 'complaint',
        'violations': 'violation',
        'permits': 'permit',
      };
      final parts = <String>[];
      m.forEach((k, v) {
        final n = (v as num?)?.toInt() ?? 0;
        if (n > 0) parts.add('$n ${labels[k] ?? k}${n == 1 ? '' : 's'}');
      });
      return parts.join(', ');
    }

    final erased = summarize(personal);
    final kept = summarize(retained);

    // A retire keeps the records, so one click confirms it. A hard delete
    // cannot be undone, so the officer must type the name.
    final typeToConfirm = !willRetire;
    final confirmCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final typed = confirmCtrl.text.trim().toLowerCase();
          final matches = typed == name.trim().toLowerCase();
          final canProceed = !typeToConfirm || matches;

          return AlertDialog(
            title: Text(willRetire ? 'Remove account?' : 'Delete account?'),
            content: SizedBox(
              width: dialogContentWidth(context, 400),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      willRetire
                          ? '$name has HOA records that must be kept for the '
                              'association\'s books, so the account will be retired '
                              'rather than fully deleted.'
                          : '$name has no HOA records, so the account and everything '
                              'belonging to it will be permanently deleted.',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    _deleteBullet(
                      icon: Icons.delete_outline,
                      color: const Color(0xFFA82F2F),
                      title: 'Permanently erased',
                      body: erased.isEmpty
                          ? 'Login access, and any personal data on file.'
                          : 'Login access, $erased, and their uploaded files.',
                    ),
                    if (willRetire) ...[
                      const SizedBox(height: 8),
                      _deleteBullet(
                        icon: Icons.inventory_2_outlined,
                        color: const Color(0xFF1A6B43),
                        title: 'Kept for HOA records',
                        body: kept.isEmpty
                            ? 'Existing association records stay intact.'
                            : '$kept. Their name stays on these so the treasurer '
                                'can still reconcile who paid what. Contact details, '
                                'address and photo are cleared.',
                      ),
                    ],
                    if (tenantCount > 0) ...[
                      const SizedBox(height: 8),
                      _deleteBullet(
                        icon: Icons.link_off,
                        color: const Color(0xFFB07D18),
                        title: 'Tenants detached',
                        body: '$tenantCount tenant account${tenantCount == 1 ? '' : 's'} '
                            'listed under this landlord will be unlinked, not deleted.',
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text('This cannot be undone.',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFA82F2F))),
                    if (typeToConfirm) ...[
                      const SizedBox(height: 14),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                          children: [
                            const TextSpan(text: 'Type '),
                            TextSpan(
                              text: name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                            const TextSpan(text: ' below to confirm.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: confirmCtrl,
                        autofocus: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: name,
                          errorText: typed.isEmpty || matches ? null : "That doesn't match.",
                        ),
                        onChanged: (_) => setLocal(() {}),
                        onSubmitted: (_) {
                          if (matches) Navigator.pop(context, true);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA82F2F)),
                onPressed: canProceed ? () => Navigator.pop(context, true) : null,
                child: Text(willRetire ? 'Remove' : 'Delete'),
              ),
            ],
          );
        },
      ),
    );
    disposeAfterDialogCloses([confirmCtrl]);
    if (confirm != true) return;

    try {
      final res = await SupabaseService.instance.client.functions
          .invoke('delete-account', body: {'user_id': u['id']});
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data['error'] != null) {
        throw Exception(data['error']);
      }
      if (mounted) {
        AppToast.success(
          context,
          message: data?['mode'] == 'retired'
              ? 'Account removed. HOA records kept under their name.'
              : 'Account and all related data deleted.',
        );
      }
      _load();
    } catch (e) {
      if (mounted) AppToast.error(context, message: 'Could not delete account. ${_deleteError(e)}');
    }
  }

  /// Gets the message from a refused delete (the function's own "error" text)
  /// instead of the generic one friendlyError() would give.
  String _deleteError(Object e) {
    if (e is FunctionException) {
      final d = e.details;
      if (d is Map && d['error'] != null) return d['error'].toString();
    }
    final msg = e.toString().replaceFirst('Exception: ', '');
    return e is Exception && !msg.contains('FunctionException') && msg.length < 200
        ? msg
        : friendlyError(e);
  }

  /// One labelled line in the delete-confirmation breakdown.
  Widget _deleteBullet({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              Text(body,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }

  /// 0 Name · 1 Email · 2 Role · 3 Status · 4 Joined
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> u, int col) {
    switch (col) {
      case 0:
        return text(_fullName(u));
      case 1:
        return text(u['email']);
      case 2:
        return text(_roleLabel(u));
      case 3:
        return rankedKey(u['status'], kStatusRank);
      case 4:
        return date(u['created_at']);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'People',
      activeItem: 'All Accounts',
      child: DefaultTabController(
        length: 2,
        initialIndex: widget.initialTab,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.sidebarActiveText,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.sidebarActiveText,
                labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                tabs: [
                  const Tab(text: 'All Accounts'),
                  TourAnchor(
                    id: TourAnchorId.pendingTab,
                    child: Tab(text: _pendingCount > 0 ? 'Pending Approvals ($_pendingCount)' : 'Pending Approvals'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: TabBarView(
                children: [
                  _accountsTab(),
                  // An approval or rejection also reloads the directory, so the
                  // stat cards and list match the tab count.
                  PendingApprovalsView(onCount: (n) {
                    final changed = n != _pendingCount;
                    setState(() => _pendingCount = n);
                    if (changed && _pending != n) _load();
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRosterImport() async {
    final imported = await showRosterImportDialog(context);
    // Reload only if rows were imported.
    if (imported == true) _load();
  }

  Widget _accountsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    }
    // Whole tab scrolls, so short/narrow windows never overflow.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerRow(),
          const SizedBox(height: 18),
          _statCards(),
          const SizedBox(height: 20),
          _tableCard(),
        ],
      ),
    );
  }

  /// Role filter, removed-accounts toggle and Import Roster button.
  Widget _headerRow() {
    return LayoutBuilder(builder: (context, c) {
      // Role filter menu; picking a role clears any stat card filter.
      final filter = PopupMenuButton<String>(
        onSelected: (v) => setState(() {
          _roleFilter = v;
          _cardFilter = 'all';
          _page = 1;
        }),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'all', child: Text('All roles')),
          for (final r in _roleOptions) PopupMenuItem(value: r.$1, child: Text(r.$2)),
        ],
        child: OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.filter_list, size: 16),
          label: Text(_roleFilter == 'all'
              ? 'All roles'
              : _roleOptions.firstWhere((r) => r.$1 == _roleFilter, orElse: () => (_roleFilter, _roleFilter)).$2),
        ),
      );
      // Only offer the toggle when there is something to reveal.
      final retiredToggle = _retiredCount == 0
          ? const SizedBox.shrink()
          : TextButton.icon(
              onPressed: () => setState(() => _showRetired = !_showRetired),
              icon: Icon(_showRetired ? Icons.visibility_off_outlined : Icons.history,
                  size: 16),
              label: Text(_showRetired
                  ? 'Hide removed ($_retiredCount)'
                  : 'Show removed ($_retiredCount)'),
            );

      final importButton = OutlinedButton.icon(
        onPressed: _openRosterImport,
        icon: const Icon(Icons.upload_file_outlined, size: 16),
        label: const Text('Import Roster'),
      );

      // Narrow: let the controls wrap rather than clipping.
      if (c.maxWidth < 520) {
        return Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            retiredToggle,
            filter,
            if (_canImport) importButton,
          ],
        );
      }
      return Row(children: [
        const Spacer(),
        retiredToggle,
        const SizedBox(width: 8),
        filter,
        if (_canImport) ...[
          const SizedBox(width: 8),
          importButton,
        ],
      ]);
    });
  }

  void _tapCard(String v) => setState(() {
        _cardFilter = _cardFilter == v ? 'all' : v;
        _roleFilter = 'all';
        _page = 1;
      });

  /// Count cards; tapping one filters the table (tap again to clear).
  Widget _statCards() {
    return responsiveStatCards((w) => [
      DashboardStatCard(icon: Icons.badge_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Total Accounts', value: '$_total', width: w, hint: 'Show all', onTap: () => setState(() { _cardFilter = 'all'; _roleFilter = 'all'; _page = 1; })),
      DashboardStatCard(icon: Icons.shield_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Officers', value: '$_officers', width: w, selected: _cardFilter == 'officers', onTap: () => _tapCard('officers')),
      DashboardStatCard(icon: Icons.people_outline, iconBg: const Color(0xFFE2F0F7), label: 'Residents + Tenants', value: '$_residentsTenants', width: w, selected: _cardFilter == 'residents', onTap: () => _tapCard('residents')),
      DashboardStatCard(icon: Icons.hourglass_top_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Pending', value: '$_pending', width: w, selected: _cardFilter == 'pending', onTap: () => _tapCard('pending')),
    ]);
  }

  /// The sortable, paged accounts table.
  Widget _tableCard() {
    final rows = _visible;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('No accounts match.', style: TextStyle(fontSize: 13, color: AppColors.textMuted))),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                // Keep the table at least as wide as the card so it fills the
                // space, but let it grow (and scroll) when columns need more.
                constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 340),
                child: DataTable(
                  showCheckboxColumn: false,
                  sortColumnIndex: sortColumn,
                  sortAscending: sortAsc,
                  columnSpacing: 28,
                  headingRowHeight: 40,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 58,
                  headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                  dataTextStyle: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                  columns: [
                    DataColumn(label: const Text('NAME'), onSort: onSort),
                    DataColumn(label: const Text('EMAIL'), onSort: onSort),
                    DataColumn(label: const Text('ROLE'), onSort: onSort),
                    DataColumn(label: const Text('STATUS'), onSort: onSort),
                    DataColumn(label: const Text('JOINED'), onSort: onSort),
                    if (_canEdit || _canDelete) const DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final u in pageSlice(sortRows(rows), _page))
                      DataRow(cells: [
                        DataCell(PersonNameLink(
                            userId: u['id'], name: _fullName(u), enabled: _canOpenPerson,
                            accountLabel: u['account_label'])),
                        DataCell(Text((u['email'] ?? '—').toString())),
                        DataCell(_roleChip(_roleLabel(u))),
                        DataCell(StatusBadge((u['status'] ?? '').toString())),
                        DataCell(Text((u['created_at'] ?? '').toString().split('T').first)),
                        if (_canEdit || _canDelete)
                          DataCell(PopupMenuButton<String>(
                            tooltip: 'Account actions',
                            icon: const Icon(Icons.more_horiz, size: 18, color: AppColors.textSecondary),
                            onSelected: (v) {
                              if (v == 'edit') _editAccount(u);
                              if (v == 'delete') _deleteAccount(u);
                            },
                            itemBuilder: (context) => [
                              if (_canEdit)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(children: [
                                    Icon(Icons.edit_outlined, size: 16),
                                    SizedBox(width: 8),
                                    Text('Edit account'),
                                  ]),
                                ),
                              if (_canDelete)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(children: [
                                    Icon(Icons.delete_outline, size: 16, color: Color(0xFFA82F2F)),
                                    SizedBox(width: 8),
                                    Text('Delete account', style: TextStyle(color: Color(0xFFA82F2F))),
                                  ]),
                                ),
                            ],
                          )),
                      ]),
                  ],
                ),
              ),
            ),
              pagerFor(rows.length, _page, (p) => setState(() => _page = p)),
              ],
            ),
    );
  }

  /// Small grey tag showing a role name.
  Widget _roleChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFF0F3F1), borderRadius: BorderRadius.circular(6)),
      child: Text(label.isEmpty ? '—' : label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    );
  }
}
