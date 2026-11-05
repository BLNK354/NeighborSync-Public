import 'profile_avatar.dart';
import '../core/app_locale.dart' show tr;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/tour_anchors.dart';
import '../core/branding.dart';
import '../core/permissions.dart';
import '../core/ui_prefs.dart';
import '../services/supabase_service.dart';
import 'portal_background.dart';
import '../theme/resident_theme.dart';
import 'community_logo.dart';
import 'mobile_member_shell.dart';
import 'notifications_bell.dart';
import '../core/roles.dart';
import 'sign_out_confirm.dart';
import 'help_button.dart';
import '../core/safe_state.dart';

/// One entry in the resident/tenant sidebar. [permissionModule] is the
/// permission that gates it; null means always visible.
class _NavItem {
  final String label;
  final IconData icon;
  final String? permissionModule;
  final String? route;
  /// Roles that never see this entry, used for household-only items.
  final List<String>? hiddenForRoles;
  const _NavItem(this.label, this.icon, this.permissionModule,
      [this.route, this.hiddenForRoles]);
}

/// A titled group of sidebar entries.
class _NavSection {
  final String label;
  final List<_NavItem> items;

  /// False hides the chevron; a one-item section has nothing to fold.
  final bool collapsible;

  const _NavSection(this.label, this.items, {this.collapsible = true});
}

/// Sidebar and top-bar layout for resident and tenant screens. The menu is
/// filtered by the user's real permissions, and the top bar shows the page
/// title, role badge, help, notifications and avatar. Phones get
/// [MobileMemberShell] instead.
class MemberShell extends StatefulWidget {
  final String title;
  final String activeItem;
  final Widget child;

  const MemberShell({
    super.key,
    required this.title,
    required this.activeItem,
    required this.child,
  });

  static const _sections = <_NavSection>[
    _NavSection('OVERVIEW', [
      _NavItem('Dashboard', Icons.space_dashboard_outlined, null, '/dashboard'),
      _NavItem('Community Map', Icons.map_outlined, null, '/me/community'),
    ]),
    _NavSection('MY FINANCES', [
      _NavItem('My Payments', Icons.receipt_long_outlined, 'bills', '/me/billing'),
      // Where to send dues; reachable even with no unpaid bill.
      _NavItem('How to Pay', Icons.qr_code_2_outlined, 'bills', '/me/how-to-pay'),
    ]),
    _NavSection('COMMUNITY', [
      _NavItem('Announcements', Icons.campaign_outlined, 'announcements', '/me/announcements'),
      _NavItem('Events', Icons.event_outlined, 'events', '/me/events'),
      _NavItem('Waste Schedule', Icons.delete_outline, null, '/me/waste-schedule', outsiderRoleNames),
      // Read-only house rules, written by officers in the CMS.
      _NavItem('Community Rules', Icons.menu_book_outlined, null, '/me/rules'),
    ]),
    _NavSection('MY REQUESTS', [
      _NavItem('My Complaints', Icons.forum_outlined, 'complaints', '/me/complaints'),
      // Tenants hold no permits permission, so this is hidden for them.
      _NavItem('My Permits', Icons.description_outlined, 'permits', '/me/permits'),
      // Gated on gate_passes, not visitor_logs: this screen creates passes,
      // and visitor logs are written by staff at the gate.
      _NavItem('My Visitors', Icons.qr_code_outlined, 'gate_passes', '/me/visitors'),
      _NavItem('My Vehicles', Icons.directions_car_outlined, 'vehicles', '/me/vehicles'),
      _NavItem('Move In/Out', Icons.moving_outlined, 'move_requests', '/me/move-requests'),
      _NavItem('Reservations', Icons.event_available_outlined, null, '/me/reservations', outsiderRoleNames),
      _NavItem('My Violations', Icons.gavel_outlined, 'violations', '/me/violations'),
      _NavItem('My Household', Icons.family_restroom_outlined, 'household_members', '/me/household'),
    ]),
    _NavSection('ACCOUNT', [
      // What a resident sees inside is set per folder by officers.
      _NavItem('Documents', Icons.folder_open_outlined, null, '/me/documents', outsiderRoleNames),
      // The resident's own uploads.
      _NavItem('My Files', Icons.folder_special_outlined, null, '/me/files', outsiderRoleNames),
      // Profile opens from the avatar in the top bar, so it is not listed.
      _NavItem('Settings', Icons.settings_outlined, null, '/me/settings'),
    ]),
  ];

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> with SafeSetState<MemberShell> {
  // Seeded from the cache so the menu is right on the first build,
  // instead of visibly changing a frame later.
  Map<String, Set<String>>? _perms = SupabaseService.cachedPermissions;
  String _roleLabel = 'Resident';
  String? _roleName = SupabaseService.cachedRole;
  // True until an officer approves this account. Seeded from the cache
  // for the same reason as _perms; see _pendingAllowedRoutes.
  bool _pending = SupabaseService.cachedStatus == 'pending_verification';

  /// True when the sidebar is shrunk to an icon rail. Must stay static: the
  /// shell is rebuilt on every navigation and an instance field would reset.
  static bool _collapsed = readSidebarCollapsed();

  /// Section labels the user has folded shut; every section starts open.
  /// Must stay static: the shell is rebuilt on every navigation.
  static final Set<String> _collapsedSections = <String>{};

  static const double _railWidth = 64;
  static const double _sidebarWidth = 256;

  void _toggleSidebar() {
    setState(() => _collapsed = !_collapsed);
    writeSidebarCollapsed(_collapsed);
  }

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
    _loadProfile();
  }

  Future<void> _loadPerms() async {
    final perms = await SupabaseService.instance.getMyPermissions();
    if (mounted) setState(() => _perms = perms);
  }

  Future<void> _loadProfile() async {
    final profile = await SupabaseService.instance.getMyProfile();
    final roles = profile?['roles'] as Map<String, dynamic>?;
    final label = (roles?['display_name'] ?? roles?['name'])?.toString();
    if (!mounted) return;
    setState(() {
      if (label != null) _roleLabel = label;
      _roleName = roles?['name']?.toString();
      _pending = profile?['status'] == 'pending_verification';
    });
  }

  // The only pages an unapproved account may open. This only trims the menu;
  // the router redirect in main.dart is what enforces it.
  static const _pendingAllowedRoutes = {'/me/community', '/me/profile'};

  bool _visible(_NavItem item) {
    if (_pending) return item.route != null && _pendingAllowedRoutes.contains(item.route);
    if (item.hiddenForRoles != null &&
        _roleName != null &&
        item.hiddenForRoles!.contains(_roleName)) {
      return false;
    }
    if (item.permissionModule == null) return true;
    // Permissions not loaded yet: hide, so no one briefly sees a screen
    // they cannot open.
    if (_perms == null) return false;
    return canAccessModule(_perms!, item.permissionModule!);
  }

  List<_NavSection> get _visibleSections {
    return MemberShell._sections
        .map((s) {
          final items = s.items.where(_visible).toList();
          // Filtering can leave one item, which needs no chevron.
          return _NavSection(s.label, items, collapsible: items.length > 1);
        })
        .where((s) => s.items.isNotEmpty)
        .toList();
  }

  bool _sectionHasActiveItem(_NavSection section) =>
      section.items.any((i) => i.label == widget.activeItem);

  /// Open when it cannot fold, is not folded, or holds the current page.
  bool _isExpanded(_NavSection section) =>
      !section.collapsible ||
      !_collapsedSections.contains(section.label) ||
      _sectionHasActiveItem(section);

  void _toggleSection(String label) {
    setState(() {
      if (_collapsedSections.contains(label)) {
        _collapsedSections.remove(label);
      } else {
        _collapsedSections.add(label);
      }
    });
  }

  /// Section title; tapping anywhere on the row folds or opens it.
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
                      color: ResidentColors.sidebarSectionLabel)),
            ),
            if (section.collapsible)
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 16,
                color: ResidentColors.sidebarSectionLabel,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Phones get the mobile shell; the fixed sidebar would crush the content.
    if (MediaQuery.of(context).size.width < 700) {
      return MobileMemberShell(title: widget.title, child: widget.child);
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The tour highlights the whole sidebar, never one nav item.
          TourAnchor(id: TourAnchorId.nav, child: _buildSidebar(context)),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context),
                Expanded(
                  child: PortalBackground(child: widget.child),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: _collapsed ? _railWidth : _sidebarWidth,
      color: ResidentColors.sidebarBg,
      // Clips rows that are briefly wider than the rail during the animation.
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo row
          Padding(
            padding: _collapsed
                ? const EdgeInsets.fromLTRB(15, 22, 15, 14)
                : const EdgeInsets.fromLTRB(24, 22, 20, 14),
            child: Row(
              children: [
                CommunityLogo(size: 34, monogramColor: ResidentColors.sidebarBg),
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
                        const Text('Resident Portal',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: ResidentColors.sidebarLogoSub)),
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
                  // On the narrow rail a thin divider replaces the label.
                  if (_collapsed)
                    const Divider(
                        height: 14,
                        thickness: 1,
                        indent: 10,
                        endIndent: 10,
                        color: Color(0x1AFFFFFF))
                  else
                    _sectionHeader(section),
                  // The rail ignores folding: its items would be unreachable
                  // with no header to reopen them.
                  if (_collapsed || _isExpanded(section))
                    for (final item in section.items) _navTile(context, item),
                ],
              ],
            ),
          ),
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
                          size: 16, color: ResidentColors.sidebarInactiveText),
                      if (!_collapsed) ...[
                        const SizedBox(width: 10),
                        const Text('Log Out',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: ResidentColors.sidebarInactiveText)),
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
                        ? ResidentColors.sidebarActiveText
                        : ResidentColors.sidebarInactiveText),
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
                                ? ResidentColors.sidebarActiveText
                                : ResidentColors.sidebarInactiveText)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: ResidentColors.border)),
      ),
      padding: EdgeInsets.only(left: _collapsed ? 16 : 20, right: 32),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggleSidebar,
            tooltip: _collapsed ? 'Expand menu' : 'Collapse menu',
            visualDensity: VisualDensity.compact,
            icon: Icon(_collapsed ? Icons.menu : Icons.menu_open,
                size: 20, color: ResidentColors.textSecondary),
          ),
          const SizedBox(width: 6),
          // Do not add a Spacer here: it would split the free space and pull
          // the right-hand controls off the edge.
          Expanded(
            child: Text(tr(widget.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: ResidentColors.textPrimary)),
          ),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              // Amber "Pending Approval" pill instead of the role until approved.
              color: _pending ? ResidentColors.iconAmberBg : ResidentColors.badgeBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.white,
                  child: Icon(_pending ? Icons.hourglass_empty : Icons.person,
                      size: 14,
                      color: _pending ? ResidentColors.iconAmberText : ResidentColors.badgeText),
                ),
                const SizedBox(width: 8),
                Text(_pending ? 'Pending Approval' : _roleLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _pending ? ResidentColors.iconAmberText : ResidentColors.badgeText)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // "How do I…?" guides, beside the bell on every shell.
          const TourAnchor(
            id: TourAnchorId.help,
            child: HelpButton(iconColor: ResidentColors.textSecondary),
          ),
          const TourAnchor(
            id: TourAnchorId.bell,
            child: NotificationsBell(iconColor: ResidentColors.textSecondary),
          ),
          const SizedBox(width: 12),
          TourAnchor(
            id: TourAnchorId.avatar,
            child: InkWell(
              onTap: () => context.go('/me/profile'),
              borderRadius: BorderRadius.circular(20),
              child: const ProfileAvatar(
                radius: 20,
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
