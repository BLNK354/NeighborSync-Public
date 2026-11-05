import 'profile_avatar.dart';
import '../core/app_locale.dart' show tr;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/tour_anchors.dart';
import '../core/permissions.dart';
import '../services/supabase_service.dart';
import 'portal_background.dart';
import 'mobile_menu_ui.dart';
import 'notifications_bell.dart';
import 'phase_scope.dart';
import '../theme/app_theme.dart';
import 'sign_out_confirm.dart';
import 'help_button.dart';
import '../core/safe_state.dart';

/// Phone-width officer layout: a top bar (menu button, title, help, bell,
/// avatar) and a bottom tab bar. Everything else is in the slide-out
/// [MobileMenu].
///
/// Separate from [AdminShell] because phones use tabs plus a slide-out menu
/// instead of a sidebar. widgets/responsive_officer_shell.dart picks which
/// one to show.
class MobileAdminShell extends StatefulWidget {
  final String title;
  final String activeTab;
  final Widget child;

  const MobileAdminShell({
    super.key,
    required this.title,
    required this.activeTab,
    required this.child,
  });

  @override
  State<MobileAdminShell> createState() => _MobileAdminShellState();
}

class _MobileAdminShellState extends State<MobileAdminShell> with SafeSetState<MobileAdminShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // The role's permissions; used to pick which tabs to show.
  Map<String, Set<String>>? _perms = SupabaseService.cachedPermissions;

  @override
  void initState() {
    super.initState();
    _loadPerms();
  }

  Future<void> _loadPerms() async {
    final perms = await SupabaseService.instance.getMyPermissions();
    if (mounted) setState(() => _perms = perms);
  }

  bool _hasAny(List<String> modules) {
    final p = _perms;
    if (p == null) return false;
    return modules.any((m) => canAccessModule(p, m));
  }

  /// Home and Profile always show. Up to 3 more tabs are filled, in
  /// priority order, with modules this role can access. Home sits in the
  /// middle slot; the position is computed because the tab count varies.
  List<({String label, IconData icon, String route})> get _visibleTabs {
    const home = (label: 'Home', icon: Icons.space_dashboard_outlined, route: '/admin');
    const profile = (label: 'Profile', icon: Icons.account_circle_outlined, route: '/admin/profile');
    final candidates = <({String label, IconData icon, String route, List<String> modules})>[
      (label: 'Finance', icon: Icons.account_balance_wallet_outlined, route: '/admin/finance', modules: ['bills', 'payments', 'budget']),
      // Opens the grid of all request screens.
      (label: 'Services', icon: Icons.apps_rounded, route: '/admin/services', modules: ['complaints', 'violations', 'permits', 'vehicles', 'gate_passes', 'move_requests', 'reservations']),
      // Announcements & Events.
      (label: 'News', icon: Icons.campaign_outlined, route: '/admin/announcements', modules: ['announcements']),
      (label: 'Visitors', icon: Icons.badge_outlined, route: '/admin/visitors', modules: ['visitor_logs']),
      (label: 'Vehicles', icon: Icons.directions_car_outlined, route: '/admin/vehicles', modules: ['vehicles']),
      (label: 'Security', icon: Icons.shield_outlined, route: '/admin/security', modules: ['security_incidents']),
    ];
    final middle = candidates.where((c) => _hasAny(c.modules)).take(3).map(
        (c) => (label: c.label, icon: c.icon, route: c.route));
    final others = [...middle, profile];
    final homeIndex = others.length ~/ 2;
    return [...others.take(homeIndex), home, ...others.skip(homeIndex)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.contentBg,
      // Slide-in menu, the same permission-filtered list on every screen.
      drawer: Drawer(
        width: (MediaQuery.of(context).size.width * 0.86).clamp(280.0, 360.0),
        child: const MobileMenu(),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              // Smaller buttons for every screen inside the phone layout.
              child: Theme(
                data: compactButtonTheme(Theme.of(context)),
                child: PortalBackground(child: widget.child),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _bottomNav(context),
    );
  }

  Widget _topBar(BuildContext context) {
    return Container(
      height: 72,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Menu button; the tour points at it as the way into navigation.
          TourAnchor(
            id: TourAnchorId.nav,
            child: IconButton(
              icon: const Icon(Icons.menu, color: AppColors.textPrimary),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          ),
          // Title, with the phase control underneath.
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(widget.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                // Shows nothing for an officer with no phase.
                const TourAnchor(
                  id: TourAnchorId.phase,
                  child: PhaseScopeControl(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          // Help guides.
          const TourAnchor(
            id: TourAnchorId.help,
            child: HelpButton(iconColor: AppColors.textSecondary),
          ),
          const TourAnchor(
            id: TourAnchorId.bell,
            child: NotificationsBell(iconColor: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          TourAnchor(
            id: TourAnchorId.avatar,
            child: InkWell(
              onTap: () => context.go('/admin/profile'),
              borderRadius: BorderRadius.circular(17),
              child: ProfileAvatar(
                radius: 17,
                background: AppColors.badgeGreenBg,
                iconColor: AppColors.sidebarActiveText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomNav(BuildContext context) {
    // The tour anchors the whole bar, not one tab, because the tabs vary by role.
    return TourAnchor(
      id: TourAnchorId.tabs,
      child: Container(
        height: 68,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            for (final tab in _visibleTabs)
              Expanded(
                child: InkWell(
                  // Does nothing only on the tab's own page, so Services still
                  // returns to the grid from a screen opened out of it.
                  onTap: GoRouterState.of(context).uri.path == tab.route
                      ? null
                      : () => context.go(tab.route),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(tab.icon,
                          size: 20,
                          color: tab.label == widget.activeTab
                              ? AppColors.sidebarActiveText
                              : AppColors.textMuted),
                      const SizedBox(height: 4),
                      Text(tr(tab.label),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight:
                                  tab.label == widget.activeTab ? FontWeight.w600 : FontWeight.w400,
                              color: tab.label == widget.activeTab
                                  ? AppColors.sidebarActiveText
                                  : AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One entry in the slide-out menu.
class _MenuItem {
  final String label;
  final IconData icon;
  final String? permissionModule;
  final String route;

  /// Roles that never see this item even if their permissions allow it.
  final List<String>? hiddenForRoles;
  const _MenuItem(this.label, this.icon, this.permissionModule, this.route, [this.hiddenForRoles]);
}

/// A labelled group of menu entries.
class _MenuSection {
  final String label;
  final List<_MenuItem> items;
  const _MenuSection(this.label, this.items);
}

/// Slide-out module list opened by the menu button, filtered by permission.
/// Mirrors [AdminShell]'s sidebar without sharing code: update both when a
/// module's permission or route changes.
class MobileMenu extends StatefulWidget {
  const MobileMenu({super.key});

  @override
  State<MobileMenu> createState() => _MobileMenuState();
}

class _MobileMenuState extends State<MobileMenu> with SafeSetState<MobileMenu> {
  static const _sections = <_MenuSection>[
    _MenuSection('COMMUNITY', [
      _MenuItem('Community Map', Icons.map_outlined, null, '/admin/community'),
      _MenuItem('Waste Schedule', Icons.delete_outline, null, '/admin/waste-schedule'),
    ]),
    _MenuSection('REQUESTS & SERVICES', [
      _MenuItem('Community Concern', Icons.report_outlined, 'complaints|violations',
          '/admin/community-concern'),
      _MenuItem('Permits', Icons.description_outlined, 'permits', '/admin/permits'),
      _MenuItem('Vehicles', Icons.directions_car_outlined, 'vehicles', '/admin/vehicles'),
      _MenuItem('Gate Passes', Icons.qr_code_outlined, 'gate_passes', '/admin/gate_passes'),
      _MenuItem('Move In/Out', Icons.local_shipping_outlined, 'move_requests', '/admin/move-requests'),
      _MenuItem('Reservations', Icons.event_available_outlined, 'reservations', '/admin/reservations'),
    ]),
    _MenuSection('SECURITY & PEOPLE', [
      // Any officer can be assigned concerns; hidden for audit_officer, who
      // never receives any.
      _MenuItem('Assigned to Me', Icons.assignment_ind_outlined, null, '/admin/assigned',
          ['audit_officer']),
      _MenuItem('Security', Icons.shield_outlined, 'security_incidents', '/admin/security'),
      _MenuItem('Visitors', Icons.badge_outlined, 'visitor_logs', '/admin/visitors'),
      _MenuItem('All Accounts', Icons.manage_accounts_outlined, 'accounts', '/admin/accounts'),
      _MenuItem('Residents', Icons.people_outline, 'users', '/admin/residents', ['treasurer']),
      _MenuItem('Tenants', Icons.groups_outlined, 'users', '/admin/tenants', ['treasurer']),
      _MenuItem('Household Members', Icons.family_restroom_outlined, 'household_members',
          '/admin/household_members'),
    ]),
    _MenuSection('ADMIN', [
      _MenuItem('CMS', Icons.palette_outlined, 'system_settings', '/admin/branding'),
      _MenuItem('Documents', Icons.folder_outlined, 'documents', '/admin/documents'),
      _MenuItem('My Files', Icons.folder_special_outlined, null, '/admin/my-files'),
      // 'a|b' means either module is enough.
      _MenuItem('Reports', Icons.bar_chart_outlined, 'audit_logs|bills', '/admin/reports'),
      _MenuItem('Audit Logs', Icons.history_outlined, 'audit_logs', '/admin/audit_logs'),
      _MenuItem('Backup', Icons.backup_outlined, 'backup', '/admin/backup'),
      // Shown to every officer.
      _MenuItem('Settings', Icons.settings_outlined, null, '/admin/system_settings'),
    ]),
  ];

  Map<String, Set<String>>? _perms = SupabaseService.cachedPermissions;
  String? _role = SupabaseService.cachedRole;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      SupabaseService.instance.getMyPermissions(),
      SupabaseService.instance.getMyRole(),
    ]);
    if (mounted) {
      setState(() {
        _perms = results[0] as Map<String, Set<String>>;
        _role = results[1] as String?;
      });
    }
  }

  /// Whether this role may see the item.
  bool _visible(_MenuItem item) {
    if (item.hiddenForRoles != null && _role != null && item.hiddenForRoles!.contains(_role)) {
      return false;
    }
    if (item.permissionModule == null) return true;
    // Permissions not loaded yet: hide, so forbidden entries never flash.
    if (_perms == null) return false;
    return item.permissionModule!
        .split('|')
        .any((m) => canAccessModule(_perms!, m));
  }

  List<_MenuSection> get _visibleSections => _sections
      .map((s) => _MenuSection(s.label, s.items.where(_visible).toList()))
      .where((s) => s.items.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          MobileMenuHeader(onClose: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final section in _visibleSections) ...[
                  MobileMenuSectionLabel(section.label),
                  for (final item in section.items)
                    MobileMenuTile(
                      icon: item.icon,
                      label: item.label,
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go(item.route);
                      },
                    ),
                ],
                MobileMenuLogout(
                  onTap: () => signOutWithConfirm(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
