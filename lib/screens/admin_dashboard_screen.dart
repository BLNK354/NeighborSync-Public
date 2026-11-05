import 'package:flutter/material.dart';
import '../core/card_filter.dart';
import 'package:go_router/go_router.dart';
import '../core/branding.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/responsive_officer_shell.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Default officer dashboard for roles without their own (HOA president,
/// super admin, audit officer). Shows four stat cards, a collections chart,
/// recent activity and recent complaints.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SafeSetState<AdminDashboardScreen> {
  Map<String, dynamic>? _profile;
  String? _role;

  int? _residents;
  int? _openComplaints;
  double? _pendingBills;
  int? _openIncidents;

  List<MonthAmount> _monthly = const [];
  double _collectionRate = 0;
  double _collectedYtd = 0;

  List<Map<String, dynamic>> _activity = const [];
  List<Map<String, dynamic>> _complaints = const [];

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads the stat cards, chart, activity and complaints.
  Future<void> _load() async {
    final profile = await SupabaseService.instance.getMyProfile();
    if (mounted) setState(() => _profile = profile);
    final role = await SupabaseService.instance.getMyRole();
    if (mounted) setState(() => _role = role);

    final c = SupabaseService.instance.client;

    // Try the SECURITY DEFINER aggregate first: read-limited roles (e.g.
    // Audit Officer) cannot query these tables directly. Falls back below.
    try {
      final rpc = await c.rpc('report_overview_data');
      if (rpc is Map) {
        final m = Map<String, dynamic>.from(rpc);
        List<Map<String, dynamic>> lst(String k) =>
            List<Map<String, dynamic>>.from((m[k] as List? ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map)));
        final users = lst('users');
        final residents = users
            .where((u) => {'member_resident', 'tenant'}
                .contains((u['roles'] as Map?)?['name']))
            .length;
        final complaintsAll = lst('complaints');
        final openComplaints = complaintsAll
            .where((v) => !{'resolved', 'dismissed'}.contains(v['status']))
            .length;
        final bills = lst('bills');
        final pendingTotal = bills
            .where((b) => {'pending', 'overdue'}.contains(b['status']))
            .fold<double>(0, (s, b) {
          final amt = num.tryParse(b['amount']?.toString() ?? '0') ?? 0;
          final pen = num.tryParse(b['penalty_amount']?.toString() ?? '0') ?? 0;
          final disc =
              num.tryParse(b['discount_amount']?.toString() ?? '0') ?? 0;
          return s + amt + pen - disc;
        });
        final incidents = lst('incidents');
        final openIncidents = incidents
            .where((i) => {'open', 'investigating'}.contains(i['status']))
            .length;
        final payments = lst('payments');
        final buckets = buildCollectionsBuckets(bills, payments);
        final rate = buckets.billedYear <= 0
            ? 0.0
            : (buckets.collectedYtd / buckets.billedYear)
                .clamp(0, 1)
                .toDouble();
        List<Map<String, dynamic>> activity = const [];
        try {
          final a = await c
              .from('audit_logs')
              .select(
                  'id, action, module, resource, old_values, new_values, severity, created_at, '
                  'actor:user_id(first_name, last_name)')
              .order('created_at', ascending: false)
              .limit(4);
          activity = List<Map<String, dynamic>>.from(a as List);
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _residents = residents;
          _openComplaints = openComplaints;
          _pendingBills = pendingTotal;
          _openIncidents = openIncidents;
          _monthly = buckets.buckets;
          _collectionRate = rate;
          _collectedYtd = buckets.collectedYtd;
          _activity = activity;
          _complaints = lst('recent_complaints').map((r) {
            final name = (r['resident_name'] ?? '').toString().trim();
            return {
              ...r,
              'resident_name': name.isEmpty ? '—' : name,
              'category_name': titleCase((r['category'] ?? '—').toString()),
            };
          }).toList();
        });
        return;
      }
    } catch (_) {
      // Fall through to the direct table reads.
    }

    try {
      final results = await Future.wait([
        c
            .from('users')
            .select('id, roles!inner(name)')
            .eq('roles.name', 'member_resident'),
        c
            .from('users')
            .select('id, roles!inner(name)')
            .eq('roles.name', 'tenant'),
        c.from('complaints').select('id, status'),
        c.from('bills').select(
            'amount, penalty_amount, discount_amount, status, due_date'),
        c.from('payments').select('amount_paid, payment_date, status'),
        c.from('security_incidents').select('id, status'),
        c
            .from('audit_logs')
            .select(
                'id, action, module, resource, old_values, new_values, severity, created_at, '
                'actor:user_id(first_name, last_name)')
            .order('created_at', ascending: false)
            .limit(4),
        c
            .from('complaints')
            .select(
                'id, complaint_number, subject, category, priority, status, complainant_id, created_at')
            .order('created_at', ascending: false)
            .limit(4),
      ]);
      if (!mounted) return;

      final residents1 = (results[0] as List? ?? const []).length;
      final residents2 = (results[1] as List? ?? const []).length;

      final complaintsAll =
          List<Map<String, dynamic>>.from(results[2] as List? ?? const []);
      final openComplaints = complaintsAll
          .where((v) => !{'resolved', 'dismissed'}.contains(v['status']))
          .length;

      final bills =
          List<Map<String, dynamic>>.from(results[3] as List? ?? const []);
      final pending =
          bills.where((b) => {'pending', 'overdue'}.contains(b['status']));
      final pendingTotal = pending.fold<double>(0, (sum, b) {
        final amt = num.tryParse(b['amount']?.toString() ?? '0') ?? 0;
        final pen = num.tryParse(b['penalty_amount']?.toString() ?? '0') ?? 0;
        final disc = num.tryParse(b['discount_amount']?.toString() ?? '0') ?? 0;
        return sum + amt + pen - disc;
      });

      final incidents =
          List<Map<String, dynamic>>.from(results[5] as List? ?? const []);
      final openIncidents = incidents
          .where((i) => {'open', 'investigating'}.contains(i['status']))
          .length;

      final payments =
          List<Map<String, dynamic>>.from(results[4] as List? ?? const []);

      // Last 6 months, billed vs collected.
      final buckets = buildCollectionsBuckets(bills, payments);
      final rate = buckets.billedYear <= 0
          ? 0.0
          : (buckets.collectedYtd / buckets.billedYear).clamp(0, 1).toDouble();

      // Resolve each complaint's resident display name.
      final activity =
          List<Map<String, dynamic>>.from(results[6] as List? ?? const []);
      final complaintRows =
          List<Map<String, dynamic>>.from(results[7] as List? ?? const []);

      final userIds = complaintRows
          .map((r) => r['complainant_id'])
          .whereType<int>()
          .toSet()
          .toList();

      Map<int, String> userNames = {};
      if (userIds.isNotEmpty) {
        final lookup = await c
            .from('users')
            .select('id, first_name, last_name')
            .inFilter('id', userIds);
        for (final u in List<Map<String, dynamic>>.from(lookup)) {
          userNames[u['id'] as int] =
              '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
        }
      }

      if (!mounted) return;
      setState(() {
        _residents = residents1 + residents2;
        _openComplaints = openComplaints;
        _pendingBills = pendingTotal;
        _openIncidents = openIncidents;
        _monthly = buckets.buckets;
        _collectionRate = rate;
        _collectedYtd = buckets.collectedYtd;
        _activity = activity;
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
              role: _role,
              communityName: AppBranding.instance.communityName),
          const SizedBox(height: 24),
          responsiveStatCards((cardWidth) => [
                DashboardStatCard(
                  icon: Icons.people_outline,
                  iconBg: AppColors.badgeGreenBg,
                  label: 'Total Residents',
                  value: _residents?.toString(),
                  width: cardWidth,
                  onTap: () => context.go('/admin/residents'),
                ),
                DashboardStatCard(
                  icon: Icons.forum_outlined,
                  iconBg: AppColors.badgeBlueBg,
                  label: 'Open Complaints',
                  value: _openComplaints?.toString(),
                  width: cardWidth,
                  onTap: () => goFiltered(context, '/admin/community-concern', 'complaints', 'open'),
                ),
                DashboardStatCard(
                  icon: Icons.receipt_long_outlined,
                  iconBg: AppColors.badgeAmberBg,
                  label: 'Pending Bills',
                  value: _pendingBills == null
                      ? null
                      : dashboardMoney(_pendingBills!),
                  width: cardWidth,
                  onTap: () => goFiltered(context, '/admin/finance', 'billing', 'outstanding'),
                ),
                DashboardStatCard(
                  icon: Icons.warning_amber_outlined,
                  iconBg: AppColors.badgeRedBg,
                  label: 'Open Incidents',
                  value: _openIncidents?.toString(),
                  width: cardWidth,
                  onTap: () => goFiltered(context, '/admin/security', 'security', 'unresolved'),
                ),
              ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth > 900;
            final collections = CollectionsChart(
              monthly: _monthly,
              collectionRate: _collectionRate,
              collectedYtd: _collectedYtd,
            );
            final activity = _activityCard();
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: collections),
                  const SizedBox(width: 20),
                  Expanded(child: activity),
                ],
              );
            }
            return Column(
                children: [collections, const SizedBox(height: 20), activity]);
          }),
          const SizedBox(height: 20),
          _complaintsTable(),
        ],
      ),
    );
  }

  // ---------- mobile body ----------

  Widget _mobileBody() {
    final firstName = _profile?['first_name'] ?? '';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardHeader(
              firstName: firstName,
              role: _role,
              communityName: AppBranding.instance.communityName,
              mobile: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: responsiveStatCards((w) => [
                  DashboardStatCard(
                      icon: Icons.people_outline,
                      iconBg: AppColors.badgeGreenBg,
                      label: 'Residents',
                      value: _residents?.toString(),
                      width: w,
                      onTap: () => context.go('/admin/residents')),
                  DashboardStatCard(
                      icon: Icons.forum_outlined,
                      iconBg: AppColors.badgeBlueBg,
                      label: 'Open Complaints',
                      value: _openComplaints?.toString(),
                      width: w,
                      onTap: () => goFiltered(context, '/admin/community-concern', 'complaints', 'open')),
                  DashboardStatCard(
                      icon: Icons.receipt_long_outlined,
                      iconBg: AppColors.badgeAmberBg,
                      label: 'Pending Bills',
                      value: _pendingBills == null
                          ? null
                          : dashboardMoney(_pendingBills!),
                      width: w,
                      onTap: () => goFiltered(context, '/admin/finance', 'billing', 'outstanding')),
                  DashboardStatCard(
                      icon: Icons.warning_amber_outlined,
                      iconBg: AppColors.badgeRedBg,
                      label: 'Incidents',
                      value: _openIncidents?.toString(),
                      width: w,
                      onTap: () => goFiltered(context, '/admin/security', 'security', 'unresolved')),
                ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _mobileCollectionsCard(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: _mobileActivityCard(),
          ),
        ],
      ),
    );
  }

  Widget _mobileCollectionsCard() {
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
          const Text('Collections',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: _monthly.isEmpty
                ? const Center(
                    child: Text('No billing activity yet.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)))
                // Only "Collected" on phones; two series would be too thin.
                : TrendLineChart(
                    labels: [
                      for (final m in _monthly)
                        dashboardMonthLabels[m.month - 1]
                    ],
                    series: [
                      ChartSeries(
                          label: 'Collected',
                          color: kSeriesColors[0],
                          values: [for (final m in _monthly) m.collected]),
                    ],
                    formatValue: (v) => '\u20B1${compactNumber(v)}',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _mobileActivityCard() {
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
          const Text('Recent Activity',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (_activity.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No recent activity yet.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            for (final log in _activity) ...[
              InkWell(
                onTap: () => _showActivity(log),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: AppColors.badgeGreenBg,
                        child: Icon(Icons.bolt_outlined,
                            size: 16, color: AppColors.sidebarActiveText),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_activityText(log),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(
                                (log['created_at'] ?? '')
                                    .toString()
                                    .split('.')
                                    .first
                                    .replaceAll('T', ' '),
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }

  // ---------- building blocks ----------

  Widget _activityCard() {
    return DashboardPanel(
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Activity',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Expanded(
            child: _activity.isEmpty
                ? const Text('No recent activity yet.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary))
                : ListView.separated(
                    itemCount: _activity.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final log = _activity[i];
                      final ts = (log['created_at'] ?? '')
                          .toString()
                          .split('.')
                          .first
                          .replaceAll('T', ' ');
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _showActivity(log),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.badgeGreenBg,
                              child: Icon(Icons.bolt_outlined,
                                  size: 16, color: AppColors.sidebarActiveText),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_activityText(log),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text(ts,
                                      style: const TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 16, color: AppColors.textMuted),
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(flex: 2, child: DashboardColHeader('ID')),
              Expanded(flex: 3, child: DashboardColHeader('RESIDENT')),
              Expanded(flex: 3, child: DashboardColHeader('CATEGORY')),
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
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
            )
          else
            for (final row in _complaints) ...[
              InkWell(
                onTap: () => _showComplaint(row),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: Text(
                              '#${row['complaint_number'] ?? row['id']}',
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.textPrimary))),
                      Expanded(
                          flex: 3,
                          child: Text(row['resident_name'] ?? '—',
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.textPrimary))),
                      Expanded(
                          flex: 3,
                          child: StatusBadge(row['category_name'] ?? '—')),
                      Expanded(
                          flex: 2,
                          child: StatusBadge((row['status'] ?? '').toString())),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
            ],
        ],
      ),
    );
  }

  // ---------- interactive rows ----------

  /// One-line summary of a log entry: who did what to which record, e.g.
  /// "Name · Updated · Bills · BILL-0001".
  String _activityText(Map<String, dynamic> log) {
    final actor = log['actor'] as Map<String, dynamic>?;
    final who = actor == null
        ? 'System'
        : '${actor['first_name'] ?? ''} ${actor['last_name'] ?? ''}'.trim();
    final res = (log['resource'] ?? '').toString().trim();
    return [
      who.isEmpty ? 'System' : who,
      titleCase((log['action'] ?? '').toString().replaceAll('_', ' ')),
      titleCase((log['module'] ?? '').toString().replaceAll('_', ' ')),
      if (res.isNotEmpty) res,
    ].join(' · ');
  }

  /// Dialog with an activity entry's details and what changed.
  void _showActivity(Map<String, dynamic> log) {
    final ts = (log['created_at'] ?? '')
        .toString()
        .split('.')
        .first
        .replaceAll('T', ' ');
    final oldV = log['old_values'], newV = log['new_values'];
    final changes = <String>[];
    if (oldV is Map && newV is Map) {
      for (final k in newV.keys) {
        if (oldV.containsKey(k)) {
          changes.add('$k: ${oldV[k] ?? '—'} → ${newV[k] ?? '—'}');
        }
      }
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Activity'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_activityText(log),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(ts,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              if ((log['severity'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                StatusBadge((log['severity']).toString()),
              ],
              if (changes.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('What changed',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                for (final c in changes.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(c,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/admin/audit_logs');
            },
            child: const Text('Open Audit Logs'),
          ),
        ],
      ),
    );
  }

  /// Dialog with a complaint's summary and a link to the complaints page.
  void _showComplaint(Map<String, dynamic> row) {
    String v(String k) => (row[k] ?? '').toString().trim();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            '#${v('complaint_number').isEmpty ? v('id') : v('complaint_number')}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (v('subject').isNotEmpty)
                Text(v('subject'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              Text(
                  'Filed by ${v('resident_name').isEmpty ? '—' : v('resident_name')}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
              if (v('created_at').isNotEmpty)
                Text('On ${v('created_at').split('T').first}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                StatusBadge(v('category_name')),
                if (v('priority').isNotEmpty) StatusBadge(v('priority')),
                StatusBadge(v('status')),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/admin/community-concern');
            },
            child: const Text('Open Complaints'),
          ),
        ],
      ),
    );
  }
}
