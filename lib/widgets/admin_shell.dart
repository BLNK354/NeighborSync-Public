import 'profile_avatar.dart';
import '../core/app_locale.dart' show tr;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/branding.dart';
import '../core/tour_anchors.dart';
import 'portal_background.dart';
import '../core/permissions.dart';
import '../core/ui_prefs.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'community_logo.dart';
import 'global_search.dart';
import 'mobile_admin_shell.dart';
import 'notifications_bell.dart';
import 'phase_scope.dart';
import 'sign_out_confirm.dart';
import 'help_button.dart';
import '../core/safe_state.dart';

/// One sidebar entry. [permissionModule] gates it (null = every officer);
/// [requiredAction] narrows that check to one action.
/// [anyModules] is for tabbed screens like Finance: the item shows if the
/// officer can access any one of them. It takes priority over [permissionModule].
class _NavItem {
  final String label;
  final IconData icon;
  final String? permissionModule;
  final String? requiredAction;
  final String? route;
  final List<String>? anyModules;

  /// Roles that never see this item, even if their permissions allow it.
  final List<String>? hiddenForRoles;
  const _NavItem(this.label, this.icon, this.permissionModule,
      [this.route, this.requiredAction, this.anyModules, this.hiddenForRoles]);
}

/// One group of sidebar entries. [collapsible] adds a chevron that folds the
/// group; [showHeader] decides whether a header row is drawn at all.
class _NavSection {
  final String label;
  final List<_NavItem> items;
  final bool collapsible;
  final bool showHeader;
  const _NavSection(this.label, this.items,
      {this.collapsible = true, this.showHeader = true});
}

/// Desktop layout for officer screens: a dark sidebar with grouped menu items,
/// and a top bar with the page title, search, help, alerts and profile photo.
/// Menu items are filtered by the officer's permissions and role.
/// Below 700px wide it hands over to [MobileAdminShell].
class AdminShell extends StatefulWidget {
  final String title;
  final String activeItem;
  final Widget child;

  const AdminShell({
    super.key,
    required this.title,
    required this.activeItem,
    required this.child,
  });

  /// The full officer menu. A new screen must also be added to
  /// mobile_admin_shell.dart and to its route and guard in main.dart.
  static const _sections = <_NavSection>[
    _NavSection('OVERVIEW', [
      _NavItem('Dashboard', Icons.space_dashboard_outlined, null, '/admin'),
      // Shown to every officer. The route and screen are named "community".
      _NavItem('Community Map', Icons.map_outlined, null, '/admin/community'),
      // Tabbed screen: Billing, Payments and Budget (finance_screen.dart).
      _NavItem('Finance', Icons.account_balance_wallet_outlined, null, '/admin/finance', null,
          ['bills', 'payments', 'budget']),
      _NavItem('Security', Icons.shield_outlined, 'security_incidents', '/admin/security'),
      // Any officer can be assigned a concern. Hidden for audit_officer, who
      // is left out of concern routing and would always see an empty list.
      _NavItem('Assigned to Me', Icons.assignment_ind_outlined, null, '/admin/assigned',
          null, null, ['audit_officer']),
    ]),
    _NavSection('COMMUNITY', [
      // Tabbed screen: Announcements and Events.
      _NavItem('Announcements & Events', Icons.campaign_outlined, null, '/admin/announcements',
          null, ['announcements', 'events']),
      // Tabbed screen: Complaints and Cases (community_concern_screen.dart).
      _NavItem('Community Concern', Icons.report_outlined, null, '/admin/community-concern',
          null, ['complaints', 'violations']),
      // Shown to every officer; the screen itself limits who can edit.
      _NavItem('Waste Schedule', Icons.delete_outline, null, '/admin/waste-schedule'),
    ]),
    _NavSection('REQUESTS & SERVICES', [
      _NavItem('Permits', Icons.description_outlined, 'permits', '/admin/permits'),
      _NavItem('Vehicles', Icons.directions_car_outlined, 'vehicles', '/admin/vehicles'),
      _NavItem('Gate Passes', Icons.qr_code_outlined, 'gate_passes', '/admin/gate_passes'),
      _NavItem('Move In/Out', Icons.local_shipping_outlined, 'move_requests', '/admin/move-requests'),
      _NavItem('Reservations', Icons.event_available_outlined, 'reservations', '/admin/reservations'),
    ]),
    _NavSection('PEOPLE', [
      // Every account across all roles; needs the `accounts` permission.
      _NavItem('All Accounts', Icons.manage_accounts_outlined, 'accounts', '/admin/accounts'),
      // Hidden for treasurers, who hold users:read only to pick names on bills.
      _NavItem('Residents', Icons.people_outline, 'users', '/admin/residents', null, null, ['treasurer']),
      _NavItem('Tenants', Icons.groups_outlined, 'users', '/admin/tenants', null, null, ['treasurer']),
      _NavItem('Visitors', Icons.badge_outlined, 'visitor_logs', '/admin/visitors'),
      _NavItem('Household Members', Icons.family_restroom_outlined, 'household_members', '/admin/household_members'),
    ]),
    _NavSection('ADMIN', [
      _NavItem('Documents', Icons.folder_outlined, 'documents', '/admin/documents'),
      // Each officer's own private files.
      _NavItem('My Files', Icons.folder_special_outlined, null, '/admin/my-files'),
      // Holding bills is enough, for treasurers; reports_screen then offers
      // the Financial Summary only.
      _NavItem('Reports', Icons.bar_chart_outlined, 'audit_logs', '/admin/reports', null, ['audit_logs', 'bills']),
      _NavItem('Audit Logs', Icons.history_outlined, 'audit_logs', '/admin/audit_logs'),
      _NavItem('Backup', Icons.backup_outlined, 'backup', '/admin/backup'),
      // The route, file and class are named "branding".
      _NavItem('CMS', Icons.palette_outlined, 'system_settings', '/admin/branding'),
      // Every officer, for Replay the tutorial. Roles without system_settings
      // get a tutorial-only Settings page.
      _NavItem('Settings', Icons.settings_outlined, null, '/admin/system_settings'),
    ]),
    // My Profile is reached from the photo in the top bar.
  ];

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> with SafeSetState<AdminShell> {
  // Starts from the cache so the menu doesn't rearrange a frame after loading.
  Map<String, Set<String>>? _perms = SupabaseService.cachedPermissions;
  String? _role = SupabaseService.cachedRole;

  // Sections the user folded; all start open. Must stay static: the shell is
  // rebuilt on every navigation, and instance state would reset on each click.
  static final Set<String> _collapsedSections = <String>{};

  /// Whether the sidebar is shrunk to icons. Static for the same reason as
  /// [_collapsedSections]; starts from the saved per-device preference.
  static bool _collapsed = readSidebarCollapsed();

  static const double _railWidth = 64;
  static const double _sidebarWidth = 256;

  /// Switches between full sidebar and icon rail, and saves the choice.
  void _toggleSidebar() {
    setState(() => _collapsed = !_collapsed);
    writeSidebarCollapsed(_collapsed);
  }

  /// Adds a tooltip only while the rail is collapsed. The widget must be left
  /// out when expanded: an empty message still shows an empty bubble on hover.
  Widget _maybeTooltip(String message, Widget child) => _collapsed
      ? Tooltip(
          message: message,
          waitDuration: const Duration(milliseconds: 300),
          child: child,
        )
      : child;

  @override
  void initState() {
    super.initState();
    _loadPerms();
  }

  /// Loads the officer's permissions and role for filtering the menu.
  Future<void> _loadPerms() async {
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

  /// Whether this officer should see [item] in the menu.
  bool _visible(_NavItem item) {
    if (item.hiddenForRoles != null && _role != null && item.hiddenForRoles!.contains(_role)) {
      return false;
    }
    // Items with no permission gate always show, even while permissions load.
    if (item.anyModules == null && item.permissionModule == null) return true;
    // Permissions not known yet: hide, so entries the role can't open never flash.
    if (_perms == null) return false;
    if (item.anyModules != null) {
      return item.anyModules!.any((m) => canAccessModule(_perms!, m));
    }
    if (item.permissionModule == null) return true;
    return item.requiredAction == null
        ? canAccessModule(_perms!, item.permissionModule!)
        : canPerform(_perms!, item.permissionModule!, item.requiredAction!);
  }

  /// The menu with hidden items removed, and empty sections dropped.
  List<_NavSection> get _visibleSections {
    return AdminShell._sections
        .map((s) => _NavSection(s.label, s.items.where(_visible).toList(),
            collapsible: s.collapsible, showHeader: s.showHeader))
        .where((s) => s.items.isNotEmpty)
        .toList();
  }

  bool _sectionHasActiveItem(_NavSection section) =>
      section.items.any((i) => i.label == widget.activeItem);

  /// A section shows open if it can't fold, the user hasn't folded it, or it
  /// holds the current page.
  bool _isExpanded(_NavSection section) =>
      !section.collapsible ||
      !_collapsedSections.contains(section.label) ||
      _sectionHasActiveItem(section);

  /// Folds or unfolds the section named [label].
  void _toggleSection(String label) {
    setState(() {
      if (_collapsedSections.contains(label)) {
        _collapsedSections.remove(label);
      } else {
        _collapsedSections.add(label);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Phone width: use the mobile shell, or the fixed sidebar would squeeze
    // the page and overflow.
    if (MediaQuery.of(context).size.width < 700) {
      return MobileAdminShell(
        title: widget.title,
        // These request screens belong to the Services tab; others mark no tab.
        activeTab: const {'Permits', 'Reservations'}.contains(widget.activeItem) ? 'Services' : '',
        child: widget.child,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The tour points at the sidebar as a whole, never at one menu item.
          TourAnchor(id: TourAnchorId.nav, child: _buildSidebar(context)),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context),
                Expanded(
                  // Page background set in the CMS (a colour or a photo).
                  child: PortalBackground(child: widget.child),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The dark sidebar: logo and phase, the menu, and Log Out at the bottom.
  Widget _buildSidebar(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: _collapsed ? _railWidth : _sidebarWidth,
      color: AppColors.sidebarBg,
      // Clip, or the logo row overflows by a few pixels while the width animates.
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: _collapsed
                ? const EdgeInsets.fromLTRB(15, 22, 15, 14)
                : const EdgeInsets.fromLTRB(24, 22, 20, 14),
            child: Row(
              children: [
                CommunityLogo(size: 34, monogramColor: AppColors.sidebarBg),
                if (!_collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppBranding.instance.communityName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        const SizedBox(height: 2),
                        // The officer's phase, or the super_admin's switcher.
                        // Moves to the top bar when collapsed; only one of the
                        // two is mounted, so the tour's phase step finds it.
                        const TourAnchor(
                          id: TourAnchorId.phase,
                          child: PhaseScopeControl(
                            color: AppColors.sidebarLogoSub,
                            fallbackLabel: 'HOA Officers Portal',
                            prefixFallback: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: _collapsed ? 8 : 12),
              children: [
                for (final section in _visibleSections) ...[
                  // Collapsed: a thin divider replaces each header, and every
                  // item shows, because a folded group couldn't be opened here.
                  if (_collapsed)
                    const Divider(
                        height: 14,
                        thickness: 1,
                        indent: 10,
                        endIndent: 10,
                        color: Color(0x1AFFFFFF))
                  else if (section.showHeader)
                    _sectionHeader(section),
                  if (_collapsed || _isExpanded(section))
                    for (final item in section.items) _navTile(context, item),
                ],
              ],
            ),
          ),
          // Log Out stays pinned below the scrolling menu.
          Padding(
            padding: EdgeInsets.all(_collapsed ? 8 : 12),
            child: _maybeTooltip(
              'Log Out',
              InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => signOutWithConfirm(context),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: _collapsed ? 0 : 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: _collapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      const Icon(Icons.logout,
                          size: 16, color: AppColors.sidebarInactiveText),
                      if (!_collapsed) ...[
                        const SizedBox(width: 10),
                        const Text('Log Out',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.sidebarInactiveText)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A section's header row. Tapping anywhere on it folds or unfolds the section.
  Widget _sectionHeader(_NavSection section) {
    final expanded = _isExpanded(section);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: section.collapsible ? () => _toggleSection(section.label) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(tr(section.label),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: AppColors.sidebarSectionLabel)),
            ),
            if (section.collapsible)
              Icon(
                expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                size: 16,
                color: AppColors.sidebarSectionLabel,
              ),
          ],
        ),
      ),
    );
  }

  /// One menu row; highlighted when it is the current page.
  Widget _navTile(BuildContext context, _NavItem item) {
    final active = item.label == widget.activeItem;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: _maybeTooltip(
        item.label,
        InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: item.route == null ? null : () => context.go(item.route!),
          child: Container(
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: active
                  ? const [BoxShadow(color: Color(0x26000000), blurRadius: 8, offset: Offset(0, 2))]
                  : null,
            ),
            padding: EdgeInsets.symmetric(
                horizontal: _collapsed ? 0 : 12, vertical: 9),
            child: Row(
              mainAxisAlignment: _collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(item.icon,
                    size: 16,
                    color: active
                        ? AppColors.sidebarActiveText
                        : AppColors.sidebarInactiveText),
                if (!_collapsed) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(tr(item.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w400,
                            color: active
                                ? AppColors.sidebarActiveText
                                : AppColors.sidebarInactiveText)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The top bar: menu toggle, page title, search, help, alerts, profile photo.
  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: EdgeInsets.only(
          left: _collapsed ? 16 : 20, right: 32),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggleSidebar,
            tooltip: _collapsed ? 'Expand menu' : 'Collapse menu',
            visualDensity: VisualDensity.compact,
            icon: Icon(_collapsed ? Icons.menu : Icons.menu_open,
                size: 20, color: AppColors.textSub),
          ),
          const SizedBox(width: 6),
          // Do not add a Spacer here: it would split the free space with this
          // Expanded and pull search, bell and photo away from the right edge.
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(widget.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain)),
                // The rail has no room for the phase control, so it sits here
                // while collapsed. A super_admin needs it to change phase.
                if (_collapsed)
                  TourAnchor(
                    id: TourAnchorId.phase,
                    child: PhaseScopeControl(
                      color: AppColors.textSub,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          TourAnchor(
            id: TourAnchorId.search,
            child: InkWell(
              onTap: () => GlobalSearch.open(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 232,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.pageBg,
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 15, color: AppColors.textSub),
                    const SizedBox(width: 8),
                    Text('Search anything...',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textSub)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // "How do I…?" guides.
          const TourAnchor(
            id: TourAnchorId.help,
            child: HelpButton(iconColor: AppColors.textSecondary),
          ),
          const TourAnchor(
            id: TourAnchorId.bell,
            child: NotificationsBell(iconColor: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          TourAnchor(
            id: TourAnchorId.avatar,
            child: InkWell(
              onTap: () => context.go('/admin/profile'),
              borderRadius: BorderRadius.circular(20),
              child: ProfileAvatar(
                radius: 20,
                background: AppColors.badgeGreenBg,
                iconColor: AppColors.sidebarActiveText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
