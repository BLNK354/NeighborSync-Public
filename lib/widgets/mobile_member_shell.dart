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
import '../theme/resident_theme.dart';
import '../theme/app_theme.dart';
import '../core/roles.dart';
import 'sign_out_confirm.dart';
import 'help_button.dart';
import '../core/safe_state.dart';

/// Phone layout for residents and tenants: top bar, bottom tab bar, and a
/// slide-in menu for everything else. Menu items and tabs show or hide by
/// the user's permissions.
///
/// Accounts waiting on approval get only Map + Profile tabs and no menu
/// items. The router redirect in main.dart enforces this; the shell just
/// avoids showing links that would bounce back.
class MobileMemberShell extends StatefulWidget {
  final String title;
  final Widget child;
  const MobileMemberShell({super.key, required this.title, required this.child});

  @override
  State<MobileMemberShell> createState() => _MobileMemberShellState();
}

class _MobileMemberShellState extends State<MobileMemberShell> with SafeSetState<MobileMemberShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  // Seeded from the cache so a pending account never flashes the full menu.
  bool _pending = SupabaseService.cachedStatus == 'pending_verification';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await SupabaseService.instance.getMyStatus();
    if (mounted) setState(() => _pending = status == 'pending_verification');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: ResidentColors.contentBg,
      // Slide-in menu: opens with the hamburger, an edge-swipe from the
      // left, and closes by dragging left / tapping outside / the X.
      drawer: Drawer(
        width: (MediaQuery.of(context).size.width * 0.86).clamp(280.0, 360.0),
        child: _MemberMobileMenu(pending: _pending),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              // Compact buttons for every screen inside the phone shell.
              child: Theme(
                data: compactButtonTheme(Theme.of(context)),
                child: PortalBackground(child: widget.child),
              ),
            ),
          ],
        ),
      ),
      // Tour anchor covers the whole bar, since visible tabs vary by role.
      bottomNavigationBar: TourAnchor(
        id: TourAnchorId.tabs,
        child: _BottomTabBar(pending: _pending),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Container(
      height: 72,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: ResidentColors.textPrimary),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          Expanded(
            child: Text(tr(widget.title),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
          ),
          // "How do I…?" guides, beside the bell on every shell.
          const TourAnchor(
            id: TourAnchorId.help,
            child: HelpButton(iconColor: ResidentColors.textSecondary),
          ),
          const TourAnchor(
            id: TourAnchorId.bell,
            child: NotificationsBell(iconColor: ResidentColors.textSecondary),
          ),
          const SizedBox(width: 8),
          TourAnchor(
            id: TourAnchorId.avatar,
            child: InkWell(
              onTap: () => context.go('/me/profile'),
              borderRadius: BorderRadius.circular(17),
              child: const ProfileAvatar(
                radius: 17,
                background: ResidentColors.iconGrayBg,
                iconColor: ResidentColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab in the bottom bar.
class _BottomTabItem {
  final String label;
  final IconData icon;
  final String route;

  /// Permission module behind the screen this tab opens. Null means
  /// "everyone signed in" (Home and Profile).
  final String? permissionModule;

  const _BottomTabItem(this.label, this.icon, this.route, {this.permissionModule});
}

// Candidate bottom tabs in display order; _BottomTabBar filters them by
// permission, so roles may see fewer than five. The active highlight
// matches on route, not position.
const _tabs = <_BottomTabItem>[
  _BottomTabItem('Payments', Icons.receipt_long_outlined, '/me/billing',
      permissionModule: 'bills'),
  _BottomTabItem('Services', Icons.apps_rounded, '/me/services',
      permissionModule: 'complaints'),
  _BottomTabItem('Home', Icons.space_dashboard_outlined, '/dashboard'),
  _BottomTabItem('News', Icons.campaign_outlined, '/me/announcements',
      permissionModule: 'announcements'),
  _BottomTabItem('Profile', Icons.person_outline, '/me/profile'),
];

// Tabs for an account still waiting on approval.
const _pendingTabs = <_BottomTabItem>[
  _BottomTabItem('Map', Icons.map_outlined, '/me/community'),
  _BottomTabItem('Profile', Icons.person_outline, '/me/profile'),
];

/// Bottom tab bar; shows only the tabs the user may open.
class _BottomTabBar extends StatefulWidget {
  final bool pending;
  const _BottomTabBar({required this.pending});

  @override
  State<_BottomTabBar> createState() => _BottomTabBarState();
}

class _BottomTabBarState extends State<_BottomTabBar> with SafeSetState<_BottomTabBar> {
  // Seeded from the cache so the first build already knows the permissions.
  Map<String, Set<String>>? _perms = SupabaseService.cachedPermissions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final perms = await SupabaseService.instance.getMyPermissions();
    if (mounted) setState(() => _perms = perms);
  }

  /// Gated tabs stay hidden until permissions are known, so a forbidden
  /// tab never flashes.
  bool _visible(_BottomTabItem tab) {
    if (tab.permissionModule == null) return true;
    if (_perms == null) return false;
    return canAccessModule(_perms!, tab.permissionModule!);
  }

  @override
  Widget build(BuildContext context) {
    // Pages reached only from the menu leave every tab unhighlighted.
    final path = GoRouterState.of(context).uri.path;
    final tabs = widget.pending ? _pendingTabs : _tabs.where(_visible).toList();
    return Container(
      height: 68,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: ResidentColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final tab in tabs)
              Expanded(
                child: InkWell(
                  onTap: path == tab.route ? null : () => context.go(tab.route),
                  child: _tabColumn(tab, active: path == tab.route),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tabColumn(_BottomTabItem tab, {required bool active}) {
    final color = active ? ResidentColors.sidebarActiveText : ResidentColors.textSecondary;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(tab.icon, size: 22, color: color),
        const SizedBox(height: 4),
        Text(tr(tab.label), style: TextStyle(fontSize: 10.5, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: color)),
      ],
    );
  }
}

/// One link in the slide-in menu.
class _MemberMenuItem {
  final String label;
  final IconData icon;
  final String? permissionModule;
  final String route;
  /// Roles that must never see this entry (same field as MemberShell's
  /// _NavItem).
  final List<String>? hiddenForRoles;
  const _MemberMenuItem(this.label, this.icon, this.permissionModule, this.route,
      [this.hiddenForRoles]);
}

/// A titled group of menu links.
class _MemberMenuSection {
  final String label;
  final List<_MemberMenuItem> items;

  /// A one-item section has nothing to fold, so it renders without a
  /// chevron rather than offering a control that changes nothing.
  final bool collapsible;

  const _MemberMenuSection(this.label, this.items, {this.collapsible = true});
}

/// Hamburger slide-in menu. Items already on the bottom tab bar are not
/// repeated here.
class _MemberMobileMenu extends StatefulWidget {
  final bool pending;
  const _MemberMobileMenu({required this.pending});

  @override
  State<_MemberMobileMenu> createState() => _MemberMobileMenuState();
}

class _MemberMobileMenuState extends State<_MemberMobileMenu> with SafeSetState<_MemberMobileMenu> {
  static const _sections = <_MemberMenuSection>[
    _MemberMenuSection('COMMUNITY', [
      _MemberMenuItem('Community Map', Icons.map_outlined, null, '/me/community'),
      _MemberMenuItem('Events', Icons.event_outlined, 'events', '/me/events'),
      _MemberMenuItem('Waste Schedule', Icons.delete_outline, null, '/me/waste-schedule', outsiderRoleNames),
      _MemberMenuItem('Community Rules', Icons.menu_book_outlined, null, '/me/rules'),
    ]),
    _MemberMenuSection('MY REQUESTS', [
      // Where to send dues; reachable even with nothing outstanding.
      _MemberMenuItem('How to Pay', Icons.qr_code_2_outlined, 'bills', '/me/how-to-pay'),
      _MemberMenuItem('My Complaints', Icons.forum_outlined, 'complaints', '/me/complaints'),
      _MemberMenuItem('My Permits', Icons.description_outlined, 'permits', '/me/permits'),
      _MemberMenuItem('My Visitors', Icons.qr_code_outlined, 'gate_passes', '/me/visitors'),
      _MemberMenuItem('My Vehicles', Icons.directions_car_outlined, 'vehicles', '/me/vehicles'),
      _MemberMenuItem('Move In/Out', Icons.moving_outlined, 'move_requests', '/me/move-requests'),
      // No permission module, matching member_shell: the screen shows only
      // the user's own bookings.
      _MemberMenuItem('Reservations', Icons.event_available_outlined, null, '/me/reservations', outsiderRoleNames),
      _MemberMenuItem('My Violations', Icons.gavel_outlined, 'violations', '/me/violations'),
      _MemberMenuItem('My Household', Icons.family_restroom_outlined, 'household_members', '/me/household'),
    ]),
    _MemberMenuSection('ACCOUNT', [
      // No permission module: folder visibility decides what each user sees.
      _MemberMenuItem('Documents', Icons.folder_open_outlined, null, '/me/documents', outsiderRoleNames),
      // The user's own uploads.
      _MemberMenuItem('My Files', Icons.folder_special_outlined, null, '/me/files', outsiderRoleNames),
      _MemberMenuItem('Settings', Icons.settings_outlined, null, '/me/settings'),
    ]),
  ];

  // Seeded from the cache so the first build already knows the answers.
  Map<String, Set<String>>? _perms = SupabaseService.cachedPermissions;
  String? _roleName = SupabaseService.cachedRole;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final perms = await SupabaseService.instance.getMyPermissions();
    final role = await SupabaseService.instance.getMyRole();
    if (mounted) {
      setState(() {
        _perms = perms;
        _roleName = role;
      });
    }
  }

  bool _visible(_MemberMenuItem item) {
    // Pending accounts: Map + Profile are on the tab bar, nothing else is reachable.
    if (widget.pending) return false;
    if (item.hiddenForRoles != null &&
        _roleName != null &&
        item.hiddenForRoles!.contains(_roleName)) {
      return false;
    }
    if (item.permissionModule == null) return true;
    // Permissions unknown: hide, so a forbidden item never flashes.
    if (_perms == null) return false;
    return canAccessModule(_perms!, item.permissionModule!);
  }

  /// Folded section headers. Static because the menu is rebuilt each time
  /// it opens, and an instance field would forget the choice. Sections
  /// start open.
  static final Set<String> _collapsedSections = <String>{};

  List<_MemberMenuSection> get _visibleSections => _sections
      .map((s) {
        final items = s.items.where(_visible).toList();
        return _MemberMenuSection(s.label, items,
            collapsible: items.length > 1);
      })
      .where((s) => s.items.isNotEmpty)
      .toList();

  /// Unlike the sidebar, this does not open the current page's section;
  /// the menu does not know which page is underneath.
  bool _isExpanded(_MemberMenuSection s) =>
      !s.collapsible || !_collapsedSections.contains(s.label);

  void _toggleSection(String label) {
    setState(() {
      if (_collapsedSections.contains(label)) {
        _collapsedSections.remove(label);
      } else {
        _collapsedSections.add(label);
      }
    });
  }

  /// Section label that folds on tap; the whole row is the tap target.
  Widget _sectionHeader(_MemberMenuSection section) {
    final expanded = _isExpanded(section);
    return InkWell(
      onTap: section.collapsible ? () => _toggleSection(section.label) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(section.label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: AppColors.textMuted)),
            ),
            if (section.collapsible)
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 18,
                color: AppColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }

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
                  _sectionHeader(section),
                  if (_isExpanded(section))
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
