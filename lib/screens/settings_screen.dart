import '../widgets/language_picker.dart';
import '../core/app_locale.dart' show tr;
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:flutter/material.dart';
import '../core/address_sort.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/guided_tour.dart';
import '../core/form_helpers.dart';
import '../core/image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Factor, FactorStatus, FileOptions, PostgrestException;
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_shell.dart';
import '../widgets/app_toast.dart';
import '../widgets/integrations_panel.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../widgets/searchable_picker.dart';
import '../core/tour_anchors.dart';
import '../core/safe_state.dart';

/// Officer Settings screen. General and Notifications edit `system_settings`
/// rows; Phases manages phases (super_admin); Roles, Integrations and Security
/// are read-only panels. The email toggle is saved but sends nothing yet.
/// Officers without system_settings see only the language and tutorial rows.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> with SafeSetState<AdminSettingsScreen> {
  // Tab names. The order must match [_tabIcons] and the switch in
  // _buildTabContent, or a tab opens the wrong page.
  static const _tabs = [
    'General',
    'Phases',
    'Roles & Permissions',
    'Notifications',
    'Integrations',
    'Security'
  ];

  /// Index of the Phases tab in [_tabs].
  static const _phasesTabIndex = 1;

  /// Index of the Roles & Permissions tab in [_tabs].
  static const _rolesTabIndex = 2;

  /// Phases and Roles & Permissions are shown to super_admin only.
  bool _tabVisible(int i) =>
      (i != _phasesTabIndex && i != _rolesTabIndex) || _isSuperAdmin;
  /// Icons for [_tabs], in the same order.
  static const _tabIcons = [
    Icons.tune_outlined,
    Icons.layers_outlined,
    Icons.admin_panel_settings_outlined,
    Icons.notifications_outlined,
    Icons.extension_outlined,
    Icons.shield_outlined,
  ];

  int _tab = 0;

  // Phase list and head counts. Only super_admin may create or split a phase.
  List<Map<String, dynamic>> _phases = [];
  Map<String, int> _phaseUserCounts = {};
  bool _isSuperAdmin = false;

  /// False for officers without system_settings (treasurer, security). They
  /// see only the language and tutorial rows, and the load skips other reads.
  bool _hasSettingsAccess = true;
  bool _phaseBusy = false;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _emailNotif = true;
  bool _maintenanceMode = false;

  List<Map<String, dynamic>> _rolePermissions = [];
  bool _mfaEnabled = false;
  String? _myEmail;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  /// Loads the general settings, role grants, 2FA status and phases.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final perms = await SupabaseService.instance.getMyPermissions();
      if (!perms.containsKey('system_settings')) {
        if (!mounted) return;
        setState(() {
          _hasSettingsAccess = false;
          _loading = false;
        });
        return;
      }
      final c = SupabaseService.instance.client;
      final results = await Future.wait<dynamic>([
        c
            .from('system_settings')
            .select('setting_key, value')
            .eq('category', 'general'),
        c
            .from('role_permissions')
            .select('roles(name, display_name), permissions(module, action)')
            .order('role_id'),
        SupabaseService.instance.listMfaFactors(),
        c
            .from('phases')
            .select('code, number, letter, name, is_active, map_image_url')
            .order('code'),
        SupabaseService.instance.getMyRole(),
      ]);

      final rows = List<Map<String, dynamic>>.from(results[0] as List);
      final settings = {
        for (final r in rows) r['setting_key'] as String: r['value'] as String?
      };
      _nameCtrl.text = settings['general.association_name'] ?? '';
      _emailCtrl.text = settings['general.contact_email'] ?? '';
      _phoneCtrl.text = settings['general.contact_phone'] ?? '';
      _addressCtrl.text = settings['general.address'] ?? '';
      _emailNotif = settings['general.email_notifications_enabled'] == 'true';
      _maintenanceMode = settings['general.maintenance_mode'] == 'true';

      final rp = List<Map<String, dynamic>>.from(results[1] as List);
      final factors = results[2] as List<Factor>;

      final phaseRows = sortPhaseRows(results[3] as List);
      final myRole = results[4] as String?;

      // People per phase. Uses the RPC, not `users`: that table is
      // phase-scoped, so other phases would count as zero.
      final counts = <String, int>{};
      if (myRole == 'super_admin') {
        try {
          final rows = await c.rpc('phase_household_counts');
          for (final r in List<Map<String, dynamic>>.from(rows as List)) {
            counts[(r['phase'] ?? '').toString()] =
                (r['people'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {
          // The phase list still works without the totals.
        }
      }

      if (!mounted) return;
      setState(() {
        _rolePermissions = rp;
        _phases = phaseRows;
        _phaseUserCounts = counts;
        _isSuperAdmin = myRole == 'super_admin';
        _mfaEnabled = factors.any((f) => f.status == FactorStatus.verified);
        _myEmail = SupabaseService.instance.client.auth.currentUser?.email;
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

  /// Permissions grouped by role display name, each as "module:action".
  Map<String, List<String>> get _permsByRole {
    final map = <String, List<String>>{};
    for (final row in _rolePermissions) {
      final role =
          (row['roles'] as Map?)?['display_name']?.toString() ?? 'Unknown role';
      final module = (row['permissions'] as Map?)?['module']?.toString() ?? '';
      final action = (row['permissions'] as Map?)?['action']?.toString() ?? '';
      if (module.isEmpty) continue;
      (map[role] ??= []).add('$module:$action');
    }
    return map;
  }

  /// Saves the General and Notifications tabs together in one upsert.
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updatedBy = await SupabaseService.instance.getMyUserId();
      final rows = [
        {
          'setting_key': 'general.association_name',
          'value': _nameCtrl.text.trim(),
          'type': 'string',
          'category': 'general',
          'is_public': true,
          if (updatedBy != null) 'updated_by': updatedBy
        },
        {
          'setting_key': 'general.contact_email',
          'value': _emailCtrl.text.trim(),
          'type': 'string',
          'category': 'general',
          'is_public': true,
          if (updatedBy != null) 'updated_by': updatedBy
        },
        {
          'setting_key': 'general.contact_phone',
          'value': _phoneCtrl.text.trim(),
          'type': 'string',
          'category': 'general',
          'is_public': true,
          if (updatedBy != null) 'updated_by': updatedBy
        },
        {
          'setting_key': 'general.address',
          'value': _addressCtrl.text.trim(),
          'type': 'string',
          'category': 'general',
          'is_public': true,
          if (updatedBy != null) 'updated_by': updatedBy
        },
        {
          'setting_key': 'general.email_notifications_enabled',
          'value': '$_emailNotif',
          'type': 'boolean',
          'category': 'general',
          'is_public': false,
          if (updatedBy != null) 'updated_by': updatedBy
        },
        // Every row must state is_public: a multi-row upsert writes NULL for
        // a key a row leaves out, which hides it from the public landing page.
        {
          'setting_key': 'general.maintenance_mode',
          'value': '$_maintenanceMode',
          'type': 'boolean',
          'category': 'general',
          'is_public': true,
          if (updatedBy != null) 'updated_by': updatedBy
        },
      ];
      await SupabaseService.instance.client
          .from('system_settings')
          .upsert(rows, onConflict: 'setting_key');
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.success(context, message: 'Settings saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, message: 'Save failed. ${friendlyError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Settings',
      activeItem: 'Settings',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)))
              : !_hasSettingsAccess
                  ? _tutorialOnly()
                  : Padding(
                      padding: EdgeInsets.all(
                          MediaQuery.sizeOf(context).width < 600 ? 16 : 24),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 900;
                        // Narrow screens get a scrolling strip of chips.
                        final tabList =
                            narrow ? _buildTabStrip() : _buildTabList();
                        final content = _buildTabContent();
                        // Tabs can be tall, so the whole page scrolls.
                        return SingleChildScrollView(
                          child: narrow
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                      tabList,
                                      const SizedBox(height: 16),
                                      content
                                    ])
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(width: 260, child: tabList),
                                    const SizedBox(width: 20),
                                    Expanded(child: content),
                                  ],
                                ),
                        );
                      }),
                    ),
    );
  }

  /// Tab chips for narrow screens.
  Widget _buildTabStrip() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            if (_tabVisible(i))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TourAnchor(
                  id: i == _phasesTabIndex
                      ? TourAnchorId.phasesTab
                      : 'settings_tab_$i',
                  child: ChoiceChip(
                    avatar: Icon(_tabIcons[i],
                        size: 16,
                        color: _tab == i
                            ? AppColors.sidebarActiveText
                            : AppColors.textMuted),
                    label: Text(_tabs[i]),
                    selected: _tab == i,
                    showCheckmark: false,
                    selectedColor: const Color(0xFFEFF6F1),
                    labelStyle: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            _tab == i ? FontWeight.w600 : FontWeight.w500,
                        color: _tab == i
                            ? AppColors.sidebarActiveText
                            : AppColors.textPrimary),
                    onSelected: (_) => setState(() => _tab = i),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// Vertical tab list for wide screens.
  Widget _buildTabList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            if (_tabVisible(i))
              TourAnchor(
                id: i == _phasesTabIndex
                    ? TourAnchorId.phasesTab
                    : 'settings_tab_$i',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _tab = i),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: _tab == i
                          ? const Color(0xFFEFF6F1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(_tabIcons[i],
                            size: 18,
                            color: _tab == i
                                ? AppColors.sidebarActiveText
                                : AppColors.textMuted),
                        const SizedBox(width: 10),
                        Text(_tabs[i],
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: _tab == i
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: _tab == i
                                    ? AppColors.sidebarActiveText
                                    : AppColors.textPrimary)),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// White card holding the selected tab.
  Widget _buildTabContent() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))
        ],
      ),
      // A hidden tab falls back to General, in case the role loads after the
      // tab was selected.
      child: switch (_tabVisible(_tab) ? _tab : 0) {
        0 => _generalTab(),
        1 => _phasesTab(),
        2 => _rolesTab(),
        3 => _notificationsTab(),
        4 => _integrationsTab(),
        _ => _securityTab(),
      },
    );
  }

  /// Text box with a small label above it.
  Widget _field(String label, TextEditingController ctrl,
      {List<TextInputFormatter>? inputFormatters}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          inputFormatters: inputFormatters,
          decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
        ),
      ],
    );
  }

  /// Switch with a label and an optional note.
  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged,
      {String? note}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: const Color(0xFFF7F9F8),
          borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13.5, color: AppColors.textPrimary)),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(note,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// Association details, maintenance mode, language and tutorial replay.
  Widget _generalTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('General Settings',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 20),
        _field('Association Name', _nameCtrl),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _field('Contact Email', _emailCtrl)),
          const SizedBox(width: 16),
          Expanded(child: _field('Contact Phone', _phoneCtrl, inputFormatters: phoneInputFormatters)),
        ]),
        const SizedBox(height: 16),
        _field('Address', _addressCtrl),
        const SizedBox(height: 20),
        _toggleRow('Maintenance Mode', _maintenanceMode,
            (v) => setState(() => _maintenanceMode = v),
            note:
                'Residents, tenants and guests cannot sign in while this is on. HOA officers can still sign in.'),
        const SizedBox(height: 8),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save Settings')),
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 16),
        // No permission needed: replaying the tutorial grants nothing.
        _languageRow(),
                const SizedBox(height: 16),
                _replayRow(),
      ],
    );
  }

  /// Settings for an officer without system_settings: language and tutorial.
  Widget _tutorialOnly() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x1A0D2617),
                    blurRadius: 24,
                    offset: Offset(0, 8))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Settings',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                const Text(
                  'The association-wide settings are managed by the President and the Secretary.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                _languageRow(),
                const SizedBox(height: 16),
                _replayRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Language picker; it changes this officer's account only.
  Widget _languageRow() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        const LanguagePicker(),
        Text(tr('Only changes the language for your account.'),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ],
    );
  }

  /// Button that replays the first-time walkthrough and screen tips.
  Widget _replayRow() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Replay the tutorial',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              SizedBox(height: 2),
              Text(
                  'The first-time walkthrough for your role, plus the tips each screen shows on your first visit.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: TourController.replay,
          icon: const Icon(Icons.play_circle_outline, size: 16),
          label: const Text('Replay'),
        ),
      ],
    );
  }

  /// Email notification toggle, saved with the General settings.
  Widget _notificationsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Notifications',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        const Text(
          'These toggles record intent only -- no email provider is connected for these yet, so enabling them does not send anything. In-app notifications (the bell icon) are separate and already fully live.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 18),
        _toggleRow('Email Notifications', _emailNotif,
            (v) => setState(() => _emailNotif = v)),
        const SizedBox(height: 8),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save Settings')),
      ],
    );
  }

  /// Lists the phases by number. A super_admin can also add a phase or move a
  /// household. Nobody types a phase code: they give a number and a part count,
  /// and the letters are generated.
  Widget _phasesTab() {
    final byNumber = <String, List<Map<String, dynamic>>>{};
    for (final p in _phases) {
      byNumber.putIfAbsent((p['number'] ?? '').toString(), () => []).add(p);
    }
    final numbers = byNumber.keys.toList()..sort(compareNatural);

    // Column, not ListView: the page's scroll view gives unbounded height,
    // and a ListView renders nothing there.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap, not Row: on a phone the buttons drop onto their own line.
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              const Text('Phases',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              if (_isSuperAdmin)
                Wrap(spacing: 10, runSpacing: 8, children: [
              // Opens the dialog that moves a household to another phase.
              FilledButton.tonalIcon(
                onPressed: _phaseBusy ? null : _moveHouseholdDialog,
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Move Household'),
              ),
              FilledButton.icon(
                onPressed: _phaseBusy ? null : _createPhaseDialog,
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Add Phase'),
              ),
                ]),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isSuperAdmin
              ? 'Each phase runs itself: its own officers, its own dues, its own '
                  'records. Officers only ever see the phase they belong to — '
                  'which is why moving a household between phases is yours '
                  'alone, and why their old bills stay with the phase that '
                  'issued them.'
              : 'Each phase runs itself. Only the system administrator can add '
                  'or divide one, or move a household between them.',
          style: const TextStyle(
              fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 18),
        if (numbers.isEmpty)
          const Text('No phases set up yet.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))
        else
          for (final n in numbers) ...[
            _phaseGroupCard(n, byNumber[n]!),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  /// Card for one phase number: its parts, head counts and admin actions.
  Widget _phaseGroupCard(String number, List<Map<String, dynamic>> parts) {
    parts.sort((a, b) =>
        (a['code'] ?? '').toString().compareTo((b['code'] ?? '').toString()));
    final divided = parts.length > 1 || parts.any((p) => p['letter'] != null);
    // A phase counts as active only if all of its parts are.
    final active = parts.every((p) => p['is_active'] != false);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text('Phase $number',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: active
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted)),
                    ),
                    if (!active) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.badgeGrayBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Inactive',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ],
                ),
              ),
              if (_isSuperAdmin && !divided && active)
                OutlinedButton(
                  onPressed:
                      _phaseBusy ? null : () => _splitPhaseDialog(number),
                  child: const Text('Divide'),
                ),
              if (_isSuperAdmin) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  tooltip: 'Phase actions',
                  enabled: !_phaseBusy,
                  icon: const Icon(Icons.more_horiz,
                      size: 18, color: AppColors.textSecondary),
                  onSelected: (v) {
                    if (v == 'map') _phaseMapDialog(parts);
                    if (v == 'deactivate') _setPhaseActive(number, false);
                    if (v == 'reactivate') _setPhaseActive(number, true);
                    if (v == 'delete') _deletePhaseDialog(number, parts);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'map',
                      child: Row(children: [
                        Icon(Icons.map_outlined, size: 16),
                        SizedBox(width: 8),
                        Text('Community map'),
                      ]),
                    ),
                    PopupMenuItem(
                      value: active ? 'deactivate' : 'reactivate',
                      child: Row(children: [
                        Icon(
                            active
                                ? Icons.archive_outlined
                                : Icons.unarchive_outlined,
                            size: 16),
                        const SizedBox(width: 8),
                        Text(active ? 'Deactivate phase' : 'Reactivate phase'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline,
                            size: 16, color: Color(0xFFA82F2F)),
                        SizedBox(width: 8),
                        Text('Delete phase',
                            style: TextStyle(color: Color(0xFFA82F2F))),
                      ]),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in parts)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.highlight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${p['code']}  ·  ${_phaseUserCounts[p['code']] ?? 0} '
                    '${(_phaseUserCounts[p['code']] ?? 0) == 1 ? 'person' : 'people'}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
          if (divided) ...[
            const SizedBox(height: 8),
            const Text(
              'Divided into parts. These share one set of officers — the letters '
              'say which part of the phase a household lives in.',
              style: TextStyle(
                  fontSize: 11.5, color: AppColors.textMuted, height: 1.45),
            ),
          ],
          if (!active) ...[
            const SizedBox(height: 8),
            const Text(
              'Retired. Its records are untouched and its officers still see them, '
              'but it is hidden from the phase switcher and from new assignments.',
              style: TextStyle(
                  fontSize: 11.5, color: AppColors.textMuted, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }

  /// Asks for a number and part count, then calls `create_phase`.
  Future<void> _createPhaseDialog() async {
    final numberCtrl = TextEditingController();
    var divided = false;
    var parts = 2;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add a phase'),
          content: SizedBox(
            width: dialogContentWidth(context, 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: numberCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Phase number',
                      hintText: '5',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Divided into parts',
                      style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                      'e.g. 5A, 5B — one set of officers for all of them',
                      style: TextStyle(fontSize: 11.5)),
                  value: divided,
                  onChanged: (v) => setLocal(() => divided = v),
                ),
                if (divided) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('How many parts?',
                          style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: parts,
                        items: [
                          for (var i = 2; i <= 8; i++)
                            DropdownMenuItem(value: i, child: Text('$i'))
                        ],
                        onChanged: (v) => setLocal(() => parts = v ?? 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Creates ${List.generate(parts, (i) => '${numberCtrl.text.trim().isEmpty ? 'N' : numberCtrl.text.trim()}${String.fromCharCode(65 + i)}').join(', ')}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _phaseBusy = true);
    try {
      await SupabaseService.instance.client.rpc('create_phase', params: {
        'p_number': numberCtrl.text.trim(),
        'p_divisions': divided ? parts : 1,
      });
      if (!mounted) return;
      AppToast.success(context, message: 'Phase created.');
      await _load();
    } catch (e) {
      if (mounted) AppToast.error(context, message: _phaseError(e));
    } finally {
      if (mounted) setState(() => _phaseBusy = false);
    }
  }

  /// Asks how many parts, then divides the phase with `split_phase`.
  Future<void> _splitPhaseDialog(String number) async {
    var parts = 2;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Divide Phase $number'),
          content: SizedBox(
            width: dialogContentWidth(context, 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('How many parts?',
                        style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: parts,
                      items: [
                        for (var i = 2; i <= 8; i++)
                          DropdownMenuItem(value: i, child: Text('$i'))
                      ],
                      onChanged: (v) => setLocal(() => parts = v ?? 2),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Everything currently in Phase $number moves to ${number}A. '
                  'The other parts start empty, and blocks can be moved into them '
                  'from the Community Map.\n\n'
                  'Nobody loses access: the parts share one set of officers.',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Divide')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _phaseBusy = true);
    try {
      await SupabaseService.instance.client.rpc('split_phase',
          params: {'p_number': number, 'p_divisions': parts});
      if (!mounted) return;
      AppToast.success(context,
          message: 'Phase $number divided into $parts parts.');
      await _load();
    } catch (e) {
      if (mounted) AppToast.error(context, message: _phaseError(e));
    } finally {
      if (mounted) setState(() => _phaseBusy = false);
    }
  }

  /// Moves one household to a lot in another phase. super_admin only.
  /// Never write `phase` here: setting `lot_id` makes `trg_sync_user_phase`
  /// derive it, and the privilege guard refuses a hand-written one. That only
  /// works if the guard fires before the sync, so keep the trigger order.
  /// Existing records stay with the old phase, and the dialog says so.
  Future<void> _moveHouseholdDialog() async {
    setState(() => _phaseBusy = true);
    List<Map<String, dynamic>> people;
    List<Map<String, dynamic>> lots;
    String? viewing;
    try {
      final c = SupabaseService.instance.client;
      final res = await Future.wait<dynamic>([
        // Filtered to residents and tenants below: an officer's phase is set
        // at approval, not derived from a lot.
        c
            .from('users')
            .select(
                'id, first_name, last_name, phase, lot_id, role:role_id(name)')
            .not('lot_id', 'is', null)
            .order('first_name')
            .order('last_name'),
        c
            .from('lots')
            .select('id, lot_number, phase, blocks(block_name)')
            .order('phase'),
        // Null check and maybeSingle: this only feeds a warning, so an expired
        // session must lose the warning, not crash the dialog.
        if (SupabaseService.instance.client.auth.currentUser == null)
          Future.value(null)
        else
          c
              .from('users')
              .select('viewing_phase')
              .eq('supabase_uid',
                  SupabaseService.instance.client.auth.currentUser!.id)
              .maybeSingle(),
      ]);
      people = List<Map<String, dynamic>>.from(res[0] as List).where((u) {
        final r = (u['role'] as Map<String, dynamic>?)?['name']?.toString();
        return r == 'member_resident' || r == 'tenant';
      }).toList();
      lots = List<Map<String, dynamic>>.from(res[1] as List)..sort(compareLotRows);
      viewing = (res[2] as Map<String, dynamic>?)?['viewing_phase']?.toString();
    } catch (e) {
      if (mounted) {
        setState(() => _phaseBusy = false);
        AppToast.error(context, message: _phaseError(e));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _phaseBusy = false);

    // The phase is part of the label, so searching a name or "Phase 3" both
    // find the row.
    String personLabel(Map<String, dynamic> p) {
      final name = [p['first_name'], p['last_name']]
          .where((s) => s != null && s.toString().trim().isNotEmpty)
          .join(' ');
      return p['phase'] == null ? name : '$name  ·  Phase ${p['phase']}';
    }

    String lotLabel(Map<String, dynamic> l) {
      final block = (l['blocks'] as Map<String, dynamic>?)?['block_name'];
      final parts = [
        if (l['phase'] != null) 'Phase ${l['phase']}',
        if (block != null) 'Block $block',
        'Lot ${l['lot_number'] ?? l['id']}',
      ];
      return parts.join(' · ');
    }

    int? personId;
    int? lotId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final person = people.firstWhere((p) => p['id'] == personId,
              orElse: () => <String, dynamic>{});
          final lot = lots.firstWhere((l) => l['id'] == lotId,
              orElse: () => <String, dynamic>{});
          final from = person['phase']?.toString();
          final to = lot['phase']?.toString();
          final crossing = from != null && to != null && from != to;

          return AlertDialog(
            title: const Text('Move household to another phase'),
            content: SizedBox(
              width: dialogContentWidth(context, 460),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // `users` and `lots` follow viewing_phase, so with a phase
                    // selected both pickers list only that phase. Warn the admin.
                    if (viewing != null && viewing.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.badgeAmberBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'You are viewing Phase ${viewing.replaceAll(RegExp('[^0-9]'), '')}, '
                          'so the lists below show only that phase. Switch the '
                          'phase selector to "All phases" to move a household '
                          'between two of them.',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.badgeAmberText,
                              height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    // Searchable pickers: these lists can run to hundreds of rows.
                    PickerField(
                      label: 'Household',
                      value: personId == null ? null : personLabel(person),
                      placeholder: 'Search by name or phase',
                      onTap: () async {
                        final picked =
                            await showSearchablePicker<Map<String, dynamic>>(
                          context: context,
                          title: 'Choose a household',
                          items: people,
                          labelOf: personLabel,
                          hintText: 'Search name or phase...',
                          selected: personId == null ? null : person,
                        );
                        if (picked != null) {
                          setLocal(() => personId = picked['id'] as int);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    PickerField(
                      label: 'New address',
                      value: lotId == null ? null : lotLabel(lot),
                      placeholder: 'Search by phase, block or lot',
                      onTap: () async {
                        final picked =
                            await showSearchablePicker<Map<String, dynamic>>(
                          context: context,
                          title: 'Choose the new address',
                          items: lots,
                          labelOf: lotLabel,
                          hintText: 'Search phase, block or lot...',
                          selected: lotId == null ? null : lot,
                        );
                        if (picked != null) {
                          setLocal(() => lotId = picked['id'] as int);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    if (crossing)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.badgeAmberBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Phase $from → Phase $to. These are separate '
                          'associations, so:\n\n'
                          '• Their existing bills, payments and cases STAY with '
                          'Phase $from — that is Phase $from\'s receivable and '
                          'Phase $to\'s officers will not see it.\n'
                          '• The household keeps sight of its own history.\n'
                          '• Phase $to\'s officers see the person from now on, '
                          'with no back ledger.',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.badgeAmberText,
                              height: 1.5),
                        ),
                      )
                    else
                      const Text(
                        'Pick a household and the address they are moving to. '
                        'If the new address is in another phase, this dialog '
                        'will say what moves with them and what does not.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.5),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: personId == null || lotId == null
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Move'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || personId == null || lotId == null) return;

    final person = people.firstWhere((p) => p['id'] == personId);
    final lot = lots.firstWhere((l) => l['id'] == lotId);
    final oldLotId = person['lot_id'];

    setState(() => _phaseBusy = true);
    try {
      final c = SupabaseService.instance.client;
      await c.from('users').update({
        'lot_id': lotId,
        'requested_lot_id': null,
        'address': lotLabel(lot),
      }).eq('id', personId as Object);
      await c
          .from('lots')
          .update({'status': 'occupied'}).eq('id', lotId as Object);

      // Mark the old lot vacant only if nobody is left on it and it read
      // 'occupied': a tenant may share the lot, and other statuses such as
      // `owned` or `rented` must be kept.
      if (oldLotId != null && oldLotId != lotId) {
        final stillThere = await c
            .from('users')
            .select('id')
            .eq('lot_id', oldLotId as Object)
            .limit(1);
        if ((stillThere as List).isEmpty) {
          await c
              .from('lots')
              .update({'status': 'vacant'})
              .eq('id', oldLotId)
              .eq('status', 'occupied');
        }
      }

      if (!mounted) return;
      final name = [person['first_name'], person['last_name']]
          .where((s) => s != null)
          .join(' ');
      AppToast.success(context, message: '$name moved to ${lotLabel(lot)}.');
      await _load();
    } catch (e) {
      if (mounted) AppToast.error(context, message: _phaseError(e));
    } finally {
      if (mounted) setState(() => _phaseBusy = false);
    }
  }

  /// Error text for phase actions. Prefers the server's own message, which
  /// names the reason; friendlyError could replace it with a generic line.
  String _phaseError(Object e) {
    if (e is PostgrestException) {
      final m = e.message.trim();
      if (m.isNotEmpty) return m;
    }
    return friendlyError(e);
  }

  /// Uploads, replaces or removes the community map for each part of a phase.
  /// A part left blank uses the fallback in `map_image_for_phase()`.
  Future<void> _phaseMapDialog(List<Map<String, dynamic>> parts) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> pick(String code) async {
            final result = await FilePicker.platform
                .pickFiles(type: FileType.image, withData: true);
            if (result == null || result.files.isEmpty) return;
            final file = result.files.first;
            final bytes = file.bytes;
            if (bytes == null) {
              if (context.mounted) {
                AppToast.error(context,
                    message: 'Could not read that image — try another one.');
              }
              return;
            }
            // Keep the large size cap: survey plans are read by zooming in on
            // small print, which a smaller image would lose.
            final shrunk = compressImageBytes(bytes, file.name,
                maxEdge: kMaxSurveyPlanEdge, quality: 88);
            final dot = shrunk.filename.lastIndexOf('.');
            final ext = dot < 0
                ? (file.extension ?? 'png').toLowerCase()
                : shrunk.filename.substring(dot + 1).toLowerCase();
            // One file per phase code, overwritten when the map is replaced.
            final path = 'map/phase-$code.$ext';
            try {
              final client = SupabaseService.instance.client;
              await client.storage.from('branding').uploadBinary(
                    path,
                    shrunk.bytes,
                    fileOptions: FileOptions(
                      upsert: true,
                      contentType: ext == 'jpg' || ext == 'jpeg'
                          ? 'image/jpeg'
                          : ext == 'webp'
                              ? 'image/webp'
                              : 'image/png',
                    ),
                  );
              // Cache-buster: the path never changes, so without this the
              // browser keeps showing the previous map.
              final url =
                  '${client.storage.from('branding').getPublicUrl(path)}'
                  '?v=${DateTime.now().millisecondsSinceEpoch}';
              await client
                  .from('phases')
                  .update({'map_image_url': url}).eq('code', code);
              setLocal(() {
                for (final p in parts) {
                  if (p['code'] == code) p['map_image_url'] = url;
                }
              });
            } catch (e) {
              if (context.mounted) {
                AppToast.error(context,
                    message: 'Upload failed. ${_phaseError(e)}');
              }
            }
          }

          Future<void> clear(String code) async {
            try {
              await SupabaseService.instance.client
                  .from('phases')
                  .update({'map_image_url': null}).eq('code', code);
              setLocal(() {
                for (final p in parts) {
                  if (p['code'] == code) p['map_image_url'] = null;
                }
              });
            } catch (e) {
              if (context.mounted) {
                AppToast.error(context, message: _phaseError(e));
              }
            }
          }

          return AlertDialog(
            title: const Text('Community map'),
            content: SizedBox(
              width: dialogContentWidth(context, 460),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Each phase is a different piece of ground, so each one has its '
                      'own map. Pins are placed relative to the picture they were '
                      'dropped on.\n\n'
                      'Leave a part blank and it will use the other part\'s map, or '
                      'the community-wide map from the CMS.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    for (final p in parts) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text('Phase ${p['code']}',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          if ((p['map_image_url'] ?? '').toString().isNotEmpty)
                            TextButton(
                              onPressed: () => clear(p['code'] as String),
                              child: const Text('Remove'),
                            ),
                          const SizedBox(width: 4),
                          OutlinedButton(
                            onPressed: () => pick(p['code'] as String),
                            child: Text(
                                (p['map_image_url'] ?? '').toString().isEmpty
                                    ? 'Upload'
                                    : 'Replace'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if ((p['map_image_url'] ?? '').toString().isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(p['map_image_url'] as String,
                              height: 130,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              semanticLabel:
                                  'Survey plan currently set for Phase ${p['code']}'),
                        )
                      else
                        Container(
                          height: 60,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                              'No map for this part — using the fallback.',
                              style: TextStyle(
                                  fontSize: 11.5, color: AppColors.textMuted)),
                        ),
                      const SizedBox(height: 16),
                    ],
                    const Text(
                      'Replacing a map does not move existing pins. Re-check them on '
                      'the Community Map afterwards using "Adjust Pins".',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFB07D18),
                          height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done')),
            ],
          );
        },
      ),
    );
    if (changed == true) await _load();
  }

  /// Deactivates or reactivates a phase. Records and officer access stay as
  /// they are; a deactivated phase just leaves the switcher and new assignments.
  Future<void> _setPhaseActive(String number, bool active) async {
    if (!active) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Deactivate Phase $number?'),
          content: SizedBox(
            width: dialogContentWidth(context, 380),
            child: Text(
              'Nothing is deleted. Phase $number keeps every record it has, and '
              'its officers keep their access.\n\n'
              'It stops appearing in the phase switcher and cannot be assigned '
              'to new officers. You can reactivate it at any time.',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Deactivate')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _phaseBusy = true);
    try {
      // All parts of one phase number change together.
      await SupabaseService.instance.client
          .from('phases')
          .update({'is_active': active}).eq('number', number);
      if (!mounted) return;
      AppToast.success(context,
          message: active
              ? 'Phase $number reactivated.'
              : 'Phase $number deactivated.');
      await _load();
    } catch (e) {
      if (mounted) AppToast.error(context, message: _phaseError(e));
    } finally {
      if (mounted) setState(() => _phaseBusy = false);
    }
  }

  /// Permanently deletes a phase and all of its parts, after a confirmation.
  /// Only an empty phase can go: `delete_phase()` refuses otherwise and names
  /// what still belongs to it.
  Future<void> _deletePhaseDialog(
      String number, List<Map<String, dynamic>> parts) async {
    final people = parts.fold<int>(
        0, (sum, p) => sum + (_phaseUserCounts[p['code']] ?? 0));
    final codes = parts.map((p) => p['code']).join(', ');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Phase $number?'),
        content: SizedBox(
          width: dialogContentWidth(context, 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parts.length > 1
                    ? 'This removes all of its parts ($codes). They are one '
                        'association, so they go together.'
                    : 'This removes Phase $number.',
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.5),
              ),
              const SizedBox(height: 12),
              Text(
                people > 0
                    ? 'Phase $number currently has $people ${people == 1 ? 'person' : 'people'} '
                        'assigned, so this will be refused. Deactivate it instead — that '
                        'keeps every record and hides the phase from the switcher.'
                    : 'Only an empty phase can be deleted. If anything at all still '
                        'belongs to it, the deletion is refused and nothing changes.',
                style: TextStyle(
                    fontSize: 12,
                    color: people > 0
                        ? const Color(0xFFB07D18)
                        : AppColors.textMuted,
                    height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFA82F2F)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _phaseBusy = true);
    try {
      await SupabaseService.instance.client
          .rpc('delete_phase', params: {'p_number': number});
      if (!mounted) return;
      AppToast.success(context, message: 'Phase $number deleted.');
      await _load();
    } catch (e) {
      if (mounted) AppToast.error(context, message: _phaseError(e));
    } finally {
      if (mounted) setState(() => _phaseBusy = false);
    }
  }

  /// Read-only list of the permissions each role holds.
  Widget _rolesTab() {
    final byRole = _permsByRole;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Roles & Permissions',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        const Text(
            'Read-only view of what each role is actually granted in the database.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        // Inlined, not a ListView: the page's scroll view cannot give a nested
        // ListView a bounded height.
        for (final entry in byRole.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in entry.value)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF0F3F1),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(p,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary)),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _integrationsTab() => const IntegrationsPanel();

  /// Shows the signed-in email and 2FA status, with a link to 2FA setup.
  Widget _securityTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Security',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFFF7F9F8),
              borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Signed in as',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                    Text(_myEmail ?? '—',
                        style: const TextStyle(
                            fontSize: 13.5, color: AppColors.textPrimary)),
                    const SizedBox(height: 10),
                    const Text('Two-factor authentication',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                    Text(_mfaEnabled ? 'Enabled' : 'Not enabled',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _mfaEnabled
                                ? AppColors.sidebarActiveText
                                : Colors.redAccent)),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => context.push('/mfa-setup'),
                child: Text(_mfaEnabled ? 'Manage 2FA' : 'Set Up 2FA'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
