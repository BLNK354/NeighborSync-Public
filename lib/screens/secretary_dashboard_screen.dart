import 'package:flutter/material.dart';
import '../core/branding.dart';
import '../core/card_filter.dart';
import '../widgets/event_details_dialog.dart';
import 'package:go_router/go_router.dart';
import '../core/form_helpers.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/responsive_officer_shell.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Secretary home page: four stat cards, pending account approvals with
/// Approve/Reject buttons, upcoming events, and recent complaints.
class SecretaryDashboardScreen extends StatefulWidget {
  const SecretaryDashboardScreen({super.key});

  @override
  State<SecretaryDashboardScreen> createState() => _SecretaryDashboardScreenState();
}

class _SecretaryDashboardScreenState extends State<SecretaryDashboardScreen> with SafeSetState<SecretaryDashboardScreen> {
  Map<String, dynamic>? _profile;

  int? _openComplaints;
  int? _pendingApprovals;
  int? _upcomingEventsCount;
  int? _activeAnnouncements;

  List<Map<String, dynamic>> _pendingUsers = const [];
  List<Map<String, dynamic>> _events = const [];
  List<Map<String, dynamic>> _complaints = const [];
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  Future<void> _load() async {
    final profile = await SupabaseService.instance.getMyProfile();
    if (mounted) setState(() => _profile = profile);

    final c = SupabaseService.instance.client;
    try {
      final results = await Future.wait([
        c.from('complaints').select('id, status'),
        c
            .from('users')
            .select('id, first_name, last_name, roles(name, display_name), created_at')
            .eq('status', 'pending_verification')
            .order('created_at', ascending: true)
            .limit(5),
        c
            .from('events')
            .select('id, title, description, category, venue, start_datetime, end_datetime, max_attendees, status')
            // Filter by date too, so a past event still marked upcoming is hidden.
            .inFilter('status', ['upcoming', 'scheduled'])
            .gte('start_datetime', DateTime.now().toUtc().toIso8601String())
            .order('start_datetime', ascending: true),
        c.from('announcements').select('id, status').eq('status', 'published'),
        c
            .from('complaints')
            .select('id, complaint_number, subject, category, priority, status, complainant_id, created_at, '
                'suggested_category, suggested_priority')
            .order('created_at', ascending: false)
            .limit(4),
      ]);
      if (!mounted) return;

      final complaintsAll = List<Map<String, dynamic>>.from(results[0]);
      final openComplaints =
          complaintsAll.where((v) => !{'resolved', 'dismissed'}.contains(v['status'])).length;

      final pendingUsers = List<Map<String, dynamic>>.from(results[1]);
      final events = List<Map<String, dynamic>>.from(results[2]);
      final activeAnnouncements = (results[3] as List).length;

      final complaintRows = List<Map<String, dynamic>>.from(results[4]);
      final userIds = complaintRows.map((r) => r['complainant_id']).whereType<int>().toSet().toList();
      Map<int, String> userNames = {};
      if (userIds.isNotEmpty) {
        final lookup = await c
            .from('users')
            .select('id, first_name, last_name')
            .inFilter('id', userIds);
        for (final u in List<Map<String, dynamic>>.from(lookup)) {
          userNames[u['id'] as int] = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
        }
      }

      if (!mounted) return;
      setState(() {
        _openComplaints = openComplaints;
        _pendingApprovals = pendingUsers.length;
        _upcomingEventsCount = events.length;
        _activeAnnouncements = activeAnnouncements;
        _pendingUsers = pendingUsers;
        _events = events.take(4).toList();
        _complaints = complaintRows.map((r) {
          return {
            ...r,
            'resident_name': userNames[r['complainant_id']] ?? '—',
            'category_name': titleCase((r['category'] ?? '—').toString()),
          };
        }).toList();
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _decide(Map<String, dynamic> user, String newStatus) async {
    final id = user['id'] as int;
    setState(() => _busy.add(id));
    try {
      await SupabaseService.instance.client
          .from('users')
          .update({'status': newStatus}).eq('id', id);
      if (!mounted) return;
      setState(() {
        _pendingUsers = _pendingUsers.where((u) => u['id'] != id).toList();
        _pendingApprovals = _pendingUsers.length;
        _busy.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Action failed. ${friendlyError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: 'Dashboard',
      activeItem: 'Dashboard',
      activeTab: 'Home',
      desktopChild: _desktopBody(),
      mobileChild: _mobileBody(),
    );
  }

  Widget _desktopBody() {
    final firstName = _profile?['first_name'] ?? '';
    return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardHeader(
                firstName: firstName,
                role: 'secretary',
                communityName: AppBranding.instance.communityName),
            const SizedBox(height: 24),
            responsiveStatCards((cardWidth) => [
                  DashboardStatCard(
                    icon: Icons.forum_outlined,
                    iconBg: AppColors.badgeBlueBg,
                    label: 'Open Complaints',
                    value: _openComplaints?.toString(),
                    width: cardWidth,
                    onTap: () => goFiltered(context, '/admin/community-concern', 'complaints', 'open'),
                  ),
                  DashboardStatCard(
                    icon: Icons.how_to_reg_outlined,
                    iconBg: AppColors.badgeAmberBg,
                    label: 'Pending Approvals',
                    value: _pendingApprovals?.toString(),
                    width: cardWidth,
                    onTap: () => context.go('/admin/approvals'),
                  ),
                  DashboardStatCard(
                    icon: Icons.event_outlined,
                    iconBg: AppColors.badgeGreenBg,
                    label: 'Upcoming Events',
                    value: _upcomingEventsCount?.toString(),
                    width: cardWidth,
                    onTap: () => context.go('/admin/events'),
                  ),
                  DashboardStatCard(
                    icon: Icons.campaign_outlined,
                    iconBg: AppColors.badgeGrayBg,
                    label: 'Active Announcements',
                    value: _activeAnnouncements?.toString(),
                    width: cardWidth,
                    onTap: () => context.go('/admin/announcements'),
                  ),
                ]),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 900;
              final approvals = _approvalsPanel();
              final events = _eventsPanel();
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: approvals),
                    const SizedBox(width: 20),
                    Expanded(child: events),
                  ],
                );
              }
              return Column(children: [approvals, const SizedBox(height: 20), events]);
            }),
            const SizedBox(height: 20),
            _complaintsTable(),
          ],
        ),
      );
  }

  // ---------- mobile body ----------

  Widget _mobileBody() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardHeader(
              firstName: _profile?['first_name'],
              role: 'secretary',
              communityName: AppBranding.instance.communityName,
              mobile: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: responsiveStatCards((w) => [
              DashboardStatCard(icon: Icons.forum_outlined, iconBg: AppColors.badgeBlueBg, label: 'Open Complaints', value: _openComplaints?.toString(), width: w, onTap: () => goFiltered(context, '/admin/community-concern', 'complaints', 'open')),
              DashboardStatCard(icon: Icons.how_to_reg_outlined, iconBg: AppColors.badgeAmberBg, label: 'Pending Approvals', value: _pendingApprovals?.toString(), width: w, onTap: () => context.go('/admin/approvals')),
              DashboardStatCard(icon: Icons.event_outlined, iconBg: AppColors.badgeGreenBg, label: 'Upcoming Events', value: _upcomingEventsCount?.toString(), width: w, onTap: () => context.go('/admin/events')),
              DashboardStatCard(icon: Icons.campaign_outlined, iconBg: AppColors.badgeGrayBg, label: 'Announcements', value: _activeAnnouncements?.toString(), width: w, onTap: () => context.go('/admin/announcements')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _mobileApprovalsCard(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _mobileEventsCard(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: _mobileComplaintsCard(),
          ),
        ],
      ),
    );
  }

  Widget _mobileApprovalsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
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
              const Expanded(
                child: Text('Pending Account Approvals',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              Text('${_pendingUsers.length} pending',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          if (_pendingUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No pending applications right now.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            for (final u in _pendingUsers) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${u['first_name'] ?? ''} ${u['last_name'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(((u['roles'] as Map<String, dynamic>?)?['display_name'] ??
                                  (u['roles'] as Map<String, dynamic>?)?['name'] ?? '—')
                              .toString(),
                              style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    if (_busy.contains(u['id']))
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    else ...[
                      OutlinedButton(
                        onPressed: () => _decide(u, 'suspended'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.badgeRedText,
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: const Text('Reject', style: TextStyle(fontSize: 10.5)),
                      ),
                      const SizedBox(width: 6),
                      FilledButton(
                        onPressed: () => _decide(u, 'active'),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.sidebarActiveText,
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: const Text('Approve', style: TextStyle(fontSize: 10.5)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _mobileEventsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Upcoming Events',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (_events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No upcoming events.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            for (final e in _events) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Builder(builder: (context) {
                      final dt = DateTime.tryParse(e['start_datetime']?.toString() ?? '');
                      return Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                            color: AppColors.contentBg, borderRadius: BorderRadius.circular(10)),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(dt == null ? '—' : '${dt.day}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                            Text(dt == null ? '' : _months[dt.month - 1],
                                style: const TextStyle(fontSize: 8, color: AppColors.textSecondary)),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((e['title'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text((e['venue'] ?? '—').toString(),
                              style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _mobileComplaintsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Complaints',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (_complaints.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No complaints reported yet.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            for (final row in _complaints) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('#${row['complaint_number'] ?? row['id']} · ${row['resident_name'] ?? '—'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text((row['category_name'] ?? '—').toString(),
                              style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                          if (row['suggested_category'] != null)
                            Text(
                              'Suggested: ${row['suggested_category']} · ${row['suggested_priority'] ?? '—'}',
                              style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: AppColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                    StatusBadge((row['priority'] ?? '—').toString()),
                    const SizedBox(width: 6),
                    StatusBadge((row['status'] ?? '').toString()),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _approvalsPanel() {
    return DashboardPanel(
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Pending Account Approvals',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const Spacer(),
              Text('${_pendingUsers.length} pending',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _pendingUsers.isEmpty
                ? const Text('No pending applications right now.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
                : ListView.separated(
                    itemCount: _pendingUsers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final u = _pendingUsers[i];
                      final roles = u['roles'] as Map<String, dynamic>?;
                      final roleLabel =
                          (roles?['display_name'] ?? roles?['name'] ?? '—').toString();
                      final busy = _busy.contains(u['id']);
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${u['first_name'] ?? ''} ${u['last_name'] ?? ''}',
                                    style: const TextStyle(
                                        fontSize: 13, color: AppColors.textPrimary)),
                                const SizedBox(height: 2),
                                Text(roleLabel,
                                    style: const TextStyle(
                                        fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          if (busy)
                            const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          else ...[
                            OutlinedButton(
                              onPressed: () => _decide(u, 'suspended'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.badgeRedText,
                                  minimumSize: const Size(0, 32),
                                  padding: const EdgeInsets.symmetric(horizontal: 10)),
                              child: const Text('Reject', style: TextStyle(fontSize: 11.5)),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => _decide(u, 'active'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.sidebarActiveText,
                                  minimumSize: const Size(0, 32),
                                  padding: const EdgeInsets.symmetric(horizontal: 10)),
                              child: const Text('Approve', style: TextStyle(fontSize: 11.5)),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _eventsPanel() {
    return DashboardPanel(
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Upcoming Events',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Expanded(
            child: _events.isEmpty
                ? const Text('No upcoming events.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
                : ListView.separated(
                    itemCount: _events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final e = _events[i];
                      final dt = DateTime.tryParse(e['start_datetime']?.toString() ?? '');
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => showEventDetails(context, e),
                        child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                                color: AppColors.contentBg, borderRadius: BorderRadius.circular(10)),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(dt == null ? '—' : '${dt.day}',
                                    style: const TextStyle(
                                        fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                Text(dt == null ? '' : _months[dt.month - 1],
                                    style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((e['title'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                                const SizedBox(height: 2),
                                Text((e['venue'] ?? '—').toString(),
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                        ],
                      ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _complaintsTable() {
    return DashboardPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Complaints',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(flex: 2, child: DashboardColHeader('ID')),
              Expanded(flex: 3, child: DashboardColHeader('RESIDENT')),
              Expanded(flex: 3, child: DashboardColHeader('CATEGORY')),
              Expanded(flex: 2, child: DashboardColHeader('PRIORITY')),
              Expanded(flex: 3, child: DashboardColHeader('SUGGESTED')),
              Expanded(flex: 2, child: DashboardColHeader('STATUS')),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: AppColors.border),
          ),
          if (_complaints.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No complaints reported yet.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            )
          else
            for (final row in _complaints) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                        flex: 2,
                        child: Text('#${row['complaint_number'] ?? row['id']}',
                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
                    Expanded(
                        flex: 3,
                        child: Text(row['resident_name'] ?? '—',
                            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
                    Expanded(flex: 3, child: StatusBadge(row['category_name'] ?? '—')),
                    Expanded(
                        flex: 2, child: StatusBadge((row['priority'] ?? '—').toString())),
                    Expanded(
                      flex: 3,
                      child: Text(
                        row['suggested_category'] == null
                            ? '—'
                            : '${row['suggested_category']} · ${row['suggested_priority'] ?? '—'}',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textMuted),
                      ),
                    ),
                    Expanded(flex: 2, child: StatusBadge((row['status'] ?? '').toString())),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
            ],
        ],
      ),
    );
  }
}
