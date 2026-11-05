import '../widgets/event_details_dialog.dart';
import '../core/app_locale.dart' show tr;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/branding.dart';
import '../core/roles.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/resident_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/member_shell.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
// Indexed by waste_schedules.day_of_week, which is 0 = Sunday.
const _dayAbbrev = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// Resident/tenant landing screen: stat cards, quick actions, and
/// announcements / my requests panels. Cards show only what the role may read.
class MemberDashboardScreen extends StatefulWidget {
  const MemberDashboardScreen({super.key});

  @override
  State<MemberDashboardScreen> createState() => _MemberDashboardScreenState();
}

class _MemberDashboardScreenState extends State<MemberDashboardScreen> with SafeSetState<MemberDashboardScreen> {
  Map<String, dynamic>? _profile;
  bool _pendingApproval = false;

  double? _totalDue;
  int? _openRequests;
  String? _nextEventLabel;
  String? _nextCollectionLabel;
  List<Map<String, dynamic>> _announcements = const [];
  List<Map<String, dynamic>> _upcomingEvents = const [];
  List<Map<String, dynamic>> _myRequests = const [];

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads the profile, permissions and every dashboard figure and list.
  Future<void> _load() async {
    final profile = await SupabaseService.instance.getMyProfile();
    final perms = await SupabaseService.instance.getMyPermissions();
    final myId = profile?['id'] as int?;
    final status = profile?['status'] as String?;
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _perms = perms;
      _pendingApproval = status == 'pending_verification';
    });
    if (myId == null) return;

    final c = SupabaseService.instance.client;
    try {
      final results = await Future.wait([
        c
            .from('bills')
            .select('amount, penalty_amount, discount_amount')
            .eq('user_id', myId)
            // Must match My Payments' Outstanding card: skip paid, cancelled
            // and waived bills.
            .not('status', 'in', '(paid,cancelled,waived)'),
        c
            .from('permits')
            .select('id')
            .eq('applicant_id', myId)
            .inFilter('status', ['draft', 'submitted', 'under_review']),
        c
            .from('events')
            .select('id, title, description, category, venue, start_datetime, end_datetime, '
                'max_attendees, image_url, status, phase')
            // Filter by date as well as status, so past events never show.
            .inFilter('status', ['upcoming', 'scheduled'])
            .gte('start_datetime', DateTime.now().toUtc().toIso8601String())
            .order('start_datetime', ascending: true)
            .limit(3),
        c
            .from('announcements')
            .select('id, title, content, category, image_url, publish_at, expire_at, created_at')
            .eq('status', 'published')
            // Hide announcements past their expiry date.
            .or('expire_at.is.null,expire_at.gt.${DateTime.now().toUtc().toIso8601String()}')
            .order('created_at', ascending: false)
            .limit(3),
        c
            .from('permits')
            .select('id, title, status, created_at')
            .eq('applicant_id', myId)
            .order('created_at', ascending: false)
            .limit(3),
        // "Open Requests" counts permits, complaints, and gate passes together.
        c
            .from('complaints')
            .select('id')
            .eq('complainant_id', myId)
            .inFilter('status', ['submitted', 'under_review', 'in_progress']),
        c
            .from('gate_passes')
            .select('id')
            .eq('requested_by', myId)
            .eq('status', 'pending'),
        c.from('waste_schedules').select('day_of_week, waste_type, collection_time').order('day_of_week'),
      ]);
      if (!mounted) return;

      final unpaid = List<Map<String, dynamic>>.from(results[0] as List? ?? const []);
      final total = unpaid.fold<double>(0, (sum, b) {
        final amt = num.tryParse(b['amount']?.toString() ?? '0') ?? 0;
        final pen = num.tryParse(b['penalty_amount']?.toString() ?? '0') ?? 0;
        final disc = num.tryParse(b['discount_amount']?.toString() ?? '0') ?? 0;
        return sum + amt + pen - disc;
      });

      final upcoming = List<Map<String, dynamic>>.from(results[2] as List? ?? const []);
      String? eventLabel;
      if (upcoming.isNotEmpty) {
        final dt = DateTime.tryParse(upcoming.first['start_datetime']?.toString() ?? '');
        if (dt != null) eventLabel = '${_months[dt.month - 1]} ${dt.day}';
      }

      final openPermits = (results[1] as List? ?? const []).length;
      final openComplaints = (results[5] as List? ?? const []).length;
      final openGatePasses = (results[6] as List? ?? const []).length;

      final wasteDays = List<Map<String, dynamic>>.from(results[7] as List? ?? const []);
      String? nextCollection;
      if (wasteDays.isNotEmpty) {
        final todayIdx = DateTime.now().weekday % 7; // 0 = Sunday, as stored
        for (var offset = 0; offset < 7; offset++) {
          final idx = (todayIdx + offset) % 7;
          final match = wasteDays.where((d) => d['day_of_week'] == idx);
          // A day may carry several collection types; any one counts.
          if (!match.any((d) => d['waste_type'] != 'rest_day')) continue;
          nextCollection = offset == 0 ? 'Today' : (offset == 1 ? 'Tomorrow' : _dayAbbrev[idx]);
          break;
        }
      }

      setState(() {
        _totalDue = total;
        _openRequests = openPermits + openComplaints + openGatePasses;
        _nextEventLabel = eventLabel;
        _nextCollectionLabel = nextCollection;
        _announcements = List<Map<String, dynamic>>.from(results[3] as List? ?? const []);
        _upcomingEvents = upcoming;
        _myRequests = List<Map<String, dynamic>>.from(results[4] as List? ?? const []);
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  String? get _roleName => _profile?['roles']?['name'] as String?;
  bool get _isTenant => _roleName == 'tenant';

  /// Guest, agent or visitor: signed in but has no lot, so address-based
  /// items (waste collection) are hidden. Matches the Waste Schedule nav gate.
  bool get _isOutsider => outsiderRoleNames.contains(_roleName);

  /// The caller's permissions, by module. Each quick action checks the
  /// permission behind the screen it links to.
  Map<String, Set<String>> _perms = const {};
  bool _can(String module, String action) =>
      _perms[module]?.contains(action) ?? false;

  /// True if any quick-action card shows. Keep in step with the cards,
  /// or the heading appears above an empty row.
  bool get _hasQuickActions =>
      _can('bills', 'read') ||
      _can('complaints', 'create') ||
      _can('gate_passes', 'create') ||
      _isTenant ||
      _can('permits', 'create') ||
      _can('household_members', 'create');

  @override
  Widget build(BuildContext context) {
    final firstName = _profile?['first_name'] ?? '';
    return MemberShell(
      title: 'Dashboard',
      activeItem: 'Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${tr('Welcome back')}, $firstName',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: ResidentColors.onPortalPrimary)),
            const SizedBox(height: 6),
            Text("Here's what's happening in ${AppBranding.instance.communityName} today.",
                style: TextStyle(fontSize: 13, color: ResidentColors.onPortalSecondary)),
            const SizedBox(height: 24),
            if (_pendingApproval)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ResidentColors.iconAmberBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Your account is pending approval. You\'ll get full access '
                  'once the Secretary verifies your proof of residency.',
                  style: TextStyle(fontSize: 12.5, color: ResidentColors.iconAmberText),
                ),
              ),
            // Each card shows only if the role can read its data.
            // responsiveStatCards sizes columns from the list length.
            responsiveStatCards((w) => [
                  if (_can('bills', 'read'))
                    _statCard(
                      icon: Icons.account_balance_wallet_outlined,
                      iconBg: ResidentColors.iconAmberBg,
                      label: 'My Balance',
                      value: _totalDue == null ? null : '₱${_totalDue!.toStringAsFixed(0)}',
                      badge: (_totalDue ?? 0) > 0 ? 'Due' : null,
                      width: w,
                      onTap: () => context.go('/me/billing'),
                    ),
                  // Shown if any of permits, complaints or gate passes is readable.
                  if (_can('permits', 'read') ||
                      _can('complaints', 'read') ||
                      _can('gate_passes', 'read'))
                    _statCard(
                      icon: Icons.assignment_outlined,
                      iconBg: ResidentColors.iconBlueBg,
                      label: 'Open Requests',
                      value: _openRequests?.toString(),
                      width: w,
                      onTap: () => context.go('/me/complaints'),
                    ),
                  if (!_isOutsider)
                    _statCard(
                      icon: Icons.delete_outline,
                      iconBg: ResidentColors.iconGreenBg,
                      label: 'Next Collection',
                      value: _nextCollectionLabel ?? '—',
                      width: w,
                      onTap: () => context.go('/me/waste-schedule'),
                    ),
                  if (_can('events', 'read'))
                    _statCard(
                      icon: Icons.event_outlined,
                      iconBg: ResidentColors.iconGrayBg,
                      label: 'Upcoming Event',
                      value: _nextEventLabel ?? '—',
                      width: w,
                      onTap: () => context.go('/me/events'),
                    ),
                ]),
            // The heading is gated too, so it never sits above nothing.
            if (_hasQuickActions) ...[
              const SizedBox(height: 28),
              Text(tr('Quick actions'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ResidentColors.textPrimary)),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                // One list drawn two ways, so phone and desktop match.
                final actions = <_QuickAction>[
                  if (_can('bills', 'read'))
                    const _QuickAction(Icons.receipt_long_outlined, ResidentColors.iconGreenBg,
                        'Pay My Bill', 'Pay Bill', '/me/billing'),
                  if (_can('complaints', 'create'))
                    const _QuickAction(Icons.report_problem_outlined, ResidentColors.iconBlueBg,
                        'File a Complaint', 'Complaint', '/me/complaints'),
                  if (_can('gate_passes', 'create'))
                    const _QuickAction(Icons.person_add_alt_outlined, ResidentColors.iconAmberBg,
                        'New Gate Pass', 'Visitor', '/me/visitors'),
                  // Tenants get a "Lease" card (links to My Profile) instead of Permit.
                  if (_isTenant)
                    const _QuickAction(Icons.home_work_outlined, ResidentColors.iconGrayBg,
                        'Lease', 'Lease', '/me/profile')
                  else if (_can('permits', 'create'))
                    const _QuickAction(Icons.description_outlined, ResidentColors.iconGrayBg,
                        'Apply for Permit', 'Permit', '/me/permits'),
                  if (_can('household_members', 'create'))
                    const _QuickAction(Icons.family_restroom_outlined, ResidentColors.iconBlueBg,
                        'Register Household Member', 'Household', '/me/household'),
                ];

                // Phone: one white card of icon tiles.
                if (constraints.maxWidth < 640) {
                  final cols = actions.length < 4 ? actions.length : 4;
                  final w = ((constraints.maxWidth - 16) / (cols < 1 ? 1 : cols)).floorToDouble();
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: ResidentColors.cardShadow,
                    ),
                    child: Wrap(
                      runSpacing: 14,
                      children: [
                        for (final a in actions) SizedBox(width: w, child: _quickTile(a)),
                      ],
                    ),
                  );
                }

                final cardWidth = (constraints.maxWidth - 3 * 20) / 4;
                return Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    for (final a in actions)
                      _quickAction(
                        icon: a.icon,
                        iconBg: a.tint,
                        label: a.label,
                        width: cardWidth,
                        onTap: () => context.go(a.route),
                      ),
                  ],
                );
              }),
            ],
            const SizedBox(height: 28),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 900;
              // Current announcements and upcoming events as small cards;
              // tap one for full details.
              final announcements = _panel(
                title: tr('Announcements & Events'),
                child: _announcements.isEmpty && _upcomingEvents.isEmpty
                    ? _emptyRow('No current announcements or upcoming events.')
                    : Column(children: [
                        for (final e in _upcomingEvents)
                          _feedCard(
                            imageUrl: e['image_url']?.toString(),
                            icon: Icons.event_outlined,
                            iconBg: ResidentColors.iconAmberBg,
                            tag: tr('Event'),
                            title: (e['title'] ?? '').toString(),
                            snippet: (e['description'] ?? '').toString(),
                            meta: _eventMeta(e),
                            onTap: () => showEventDetails(context, e),
                          ),
                        for (final a in _announcements)
                          _feedCard(
                            imageUrl: a['image_url']?.toString(),
                            icon: Icons.campaign_outlined,
                            iconBg: ResidentColors.iconBlueBg,
                            tag: titleCase((a['category'] ?? 'general').toString()),
                            title: (a['title'] ?? '').toString(),
                            snippet: (a['content'] ?? '').toString(),
                            meta: _postedMeta(a),
                            onTap: () => showAnnouncementDetails(context, a),
                          ),
                      ]),
              );
              // "My Requests" lists the caller's own permits; skip it without permit access.
              if (!_can('permits', 'read')) return announcements;
              final requests = _panel(
                title: 'My Requests',
                child: _myRequests.isEmpty
                    ? _emptyRow('No permit requests yet.')
                    : Column(children: [
                        for (final r in _myRequests)
                          _listRow(r['title'] ?? '', titleCase((r['status'] ?? '').toString())),
                      ]),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: announcements),
                    const SizedBox(width: 20),
                    Expanded(child: requests),
                  ],
                );
              }
              return Column(children: [announcements, const SizedBox(height: 20), requests]);
            }),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconBg,
    required String label,
    String? value,
    String? badge,
    required double width,
    VoidCallback? onTap,
  }) {
    // No fixed height, so long amounts or labels cannot overflow.
    final compact = width < 190;
    final card = _statCardBody(
        icon: icon, iconBg: iconBg, label: label, value: value, badge: badge,
        width: width, compact: compact, tappable: onTap != null);
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: card),
    );
  }

  Widget _statCardBody({
    required IconData icon,
    required Color iconBg,
    required String label,
    String? value,
    String? badge,
    required double width,
    required bool compact,
    required bool tappable,
  }) {
    return Container(
      width: width.clamp(150, 400),
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ResidentColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Icon(icon, size: compact ? 18 : 20, color: ResidentColors.textPrimary),
              ),
              const Spacer(),
              if (badge != null)
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                      color: ResidentColors.iconAmberBg, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(badge,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: ResidentColors.iconAmberText)),
                ),
            ],
          ),
          SizedBox(height: compact ? 10 : 14),
          Text(tr(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: compact ? 20 : 24, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
        ],
      ),
    );
  }

  /// One icon tile in the phone quick-actions card.
  Widget _quickTile(_QuickAction a) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.go(a.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: a.tint, borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.center,
              child: Icon(a.icon, size: 24, color: ResidentColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(tr(a.short),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: ResidentColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required Color iconBg,
    required String label,
    required double width,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: width.clamp(200, 400),
        height: 84,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: ResidentColors.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: ResidentColors.textPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(tr(label),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ResidentColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ResidentColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _listRow(String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: ResidentColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: ResidentColors.iconGrayBg,
            child: Icon(Icons.article_outlined, size: 18, color: ResidentColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: ResidentColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 11, color: ResidentColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _short(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  String _eventMeta(Map<String, dynamic> e) {
    final d = DateTime.tryParse((e['start_datetime'] ?? '').toString())?.toLocal();
    final venue = (e['venue'] ?? '').toString().trim();
    return [if (d != null) _short(d), if (venue.isNotEmpty) venue].join(' \u00b7 ');
  }

  String _postedMeta(Map<String, dynamic> a) {
    final d = DateTime.tryParse((a['publish_at'] ?? a['created_at'] ?? '').toString())?.toLocal();
    return d == null ? '' : 'Posted ${_short(d)}';
  }

  /// Small card for one announcement or event: photo or icon, tag, title,
  /// two-line preview and date. Tapping it opens the details.
  Widget _feedCard({
    required String? imageUrl,
    required IconData icon,
    required Color iconBg,
    required String tag,
    required String title,
    required String snippet,
    required String meta,
    required VoidCallback onTap,
  }) {
    final hasImage = (imageUrl ?? '').trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: ResidentColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: hasImage
                        ? Image.network(imageUrl!.trim(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                color: iconBg,
                                child: Icon(icon, color: ResidentColors.textPrimary)))
                        : Container(
                            color: iconBg,
                            child: Icon(icon, color: ResidentColors.textPrimary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tag.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w600,
                              color: ResidentColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: ResidentColors.textPrimary)),
                      if (snippet.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(snippet.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, height: 1.35, color: ResidentColors.textSecondary)),
                      ],
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(meta,
                            style: const TextStyle(fontSize: 11, color: ResidentColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: ResidentColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyRow(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: const TextStyle(fontSize: 12.5, color: ResidentColors.textSecondary)),
      );
}

/// One dashboard shortcut. [label] is the full wording used on the desktop
/// cards; [short] is the one or two words that fit under a phone tile.
class _QuickAction {
  final IconData icon;
  final Color tint;
  final String label;
  final String short;
  final String route;
  const _QuickAction(this.icon, this.tint, this.label, this.short, this.route);
}
