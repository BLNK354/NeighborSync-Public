import '../core/app_locale.dart' show tr;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/permissions.dart';
import '../core/roles.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/member_shell.dart';
import '../widgets/responsive_officer_shell.dart';
import '../core/safe_state.dart';

/// One tile in the Services grid: an icon, a label and the screen it opens.
///
/// The grid is what the phone's middle bottom tab opens. Tiles are filtered
/// by the person's permissions, same as the side menu.
class _Service {
  final String label;
  final IconData icon;
  final String route;
  final Color tint;
  final Color ink;

  /// Access to any one of these modules shows the tile. Empty means everyone.
  final List<String> modules;

  /// Hidden for guests (no address or household).
  final bool residentsOnly;

  const _Service(this.label, this.icon, this.route, this.tint, this.ink,
      {this.modules = const [], this.residentsOnly = false});
}

const _green = (Color(0xFFE3F1E9), Color(0xFF1A6B43));
const _blue = (Color(0xFFE2F0F7), Color(0xFF0C5C84));
const _amber = (Color(0xFFFBEFD6), Color(0xFF8A6300));
const _red = (Color(0xFFFBE4E4), Color(0xFFA82F2F));
const _purple = (Color(0xFFF2E9FB), Color(0xFF6B21A8));

_Service _s(String label, IconData icon, String route, (Color, Color) c,
        {List<String> modules = const [], bool residentsOnly = false}) =>
    _Service(label, icon, route, c.$1, c.$2, modules: modules, residentsOnly: residentsOnly);

final _officerSections = <(String, List<_Service>)>[
  ('Community Concerns', [
    _s('Complaints & Cases', Icons.report_outlined, '/admin/community-concern', _red,
        modules: ['complaints', 'violations']),
    _s('Assigned to Me', Icons.assignment_ind_outlined, '/admin/assigned', _purple,
        modules: ['complaints', 'security_incidents']),
    _s('Security', Icons.shield_outlined, '/admin/security', _blue, modules: ['security_incidents']),
    _s('Visitor Log', Icons.badge_outlined, '/admin/visitors', _amber, modules: ['visitor_logs']),
  ]),
  ('Requests & Services', [
    _s('Permits', Icons.description_outlined, '/admin/permits', _green, modules: ['permits']),
    _s('Vehicles', Icons.directions_car_outlined, '/admin/vehicles', _blue, modules: ['vehicles']),
    _s('Gate Passes', Icons.qr_code_2_outlined, '/admin/gate_passes', _amber, modules: ['gate_passes']),
    _s('Move In/Out', Icons.local_shipping_outlined, '/admin/move-requests', _purple,
        modules: ['move_requests']),
    _s('Reservations', Icons.event_available_outlined, '/admin/reservations', _green,
        modules: ['reservations']),
  ]),
];

final _memberSections = <(String, List<_Service>)>[
  ('My Requests', [
    _s('Complaints', Icons.forum_outlined, '/me/complaints', _red, modules: ['complaints']),
    _s('Permits', Icons.description_outlined, '/me/permits', _green, modules: ['permits']),
    _s('Visitors', Icons.qr_code_2_outlined, '/me/visitors', _amber, modules: ['gate_passes']),
    _s('Vehicles', Icons.directions_car_outlined, '/me/vehicles', _blue, modules: ['vehicles']),
    _s('Move In/Out', Icons.local_shipping_outlined, '/me/move-requests', _purple,
        modules: ['move_requests']),
    _s('Reservations', Icons.event_available_outlined, '/me/reservations', _green, residentsOnly: true),
    _s('Violations', Icons.gavel_outlined, '/me/violations', _red, modules: ['violations']),
    _s('Household', Icons.family_restroom_outlined, '/me/household', _blue,
        modules: ['household_members']),
  ]),
  ('Payments', [
    _s('My Payments', Icons.receipt_long_outlined, '/me/billing', _green, modules: ['bills']),
    _s('How to Pay', Icons.qr_code_scanner_outlined, '/me/how-to-pay', _amber, modules: ['bills']),
  ]),
];

class OfficerServicesScreen extends StatelessWidget {
  const OfficerServicesScreen({super.key});
  @override
  Widget build(BuildContext context) => const ResponsiveOfficerShell(
        title: 'Services',
        activeItem: 'Services',
        activeTab: 'Services',
        desktopChild: _ServicesBody(officer: true),
      );
}

class MemberServicesScreen extends StatelessWidget {
  const MemberServicesScreen({super.key});
  @override
  Widget build(BuildContext context) => const MemberShell(
        title: 'Services',
        activeItem: 'Services',
        child: _ServicesBody(officer: false),
      );
}

class _ServicesBody extends StatefulWidget {
  final bool officer;
  const _ServicesBody({required this.officer});
  @override
  State<_ServicesBody> createState() => _ServicesBodyState();
}

class _ServicesBodyState extends State<_ServicesBody> with SafeSetState<_ServicesBody> {
  Map<String, Set<String>>? _perms;
  String? _role;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final perms = await SupabaseService.instance.getMyPermissions();
    final role = await SupabaseService.instance.getMyRole();
    if (!mounted) return;
    setState(() {
      _perms = perms;
      _role = role;
    });
  }

  bool _allowed(_Service s) {
    final p = _perms ?? const {};
    if (s.residentsOnly && outsiderRoles.contains(_role)) return false;
    if (s.modules.isEmpty) return true;
    return s.modules.any((m) => canAccessModule(p, m));
  }

  @override
  Widget build(BuildContext context) {
    if (_perms == null) return const Center(child: CircularProgressIndicator());
    final sections = (widget.officer ? _officerSections : _memberSections)
        .map((sec) => (sec.$1, sec.$2.where(_allowed).toList()))
        .where((sec) => sec.$2.isNotEmpty)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sections.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('No services are available for your account.',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  ),
                ),
              for (final sec in sections) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(tr(sec.$1),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                _card(sec.$2),
                const SizedBox(height: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(List<_Service> items) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.cardShadow,
      ),
      child: LayoutBuilder(builder: (context, c) {
        // Four tiles per row, five on wide screens.
        final cols = c.maxWidth >= 560 ? 5 : 4;
        final w = (c.maxWidth / cols).floorToDouble();
        return Wrap(
          runSpacing: 14,
          children: [for (final s in items) SizedBox(width: w, child: _tile(s))],
        );
      }),
    );
  }

  Widget _tile(_Service s) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push(s.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: s.tint, borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.center,
              child: Icon(s.icon, size: 24, color: s.ink),
            ),
            const SizedBox(height: 8),
            Text(tr(s.label),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, height: 1.25, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
