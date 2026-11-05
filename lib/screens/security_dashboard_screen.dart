import 'package:flutter/material.dart';
import '../core/branding.dart';
import '../core/card_filter.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/responsive_officer_shell.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Dashboard for security guards: stat cards (open incidents, visitors today,
/// vehicles, pending gate passes), today's visitor log, recent incidents, and
/// gate passes waiting for the guardhouse.
///
/// "Vehicles On-Site" is the count of active registered vehicles, not a live count.
class SecurityDashboardScreen extends StatefulWidget {
  const SecurityDashboardScreen({super.key});

  @override
  State<SecurityDashboardScreen> createState() => _SecurityDashboardScreenState();
}

class _SecurityDashboardScreenState extends State<SecurityDashboardScreen> with SafeSetState<SecurityDashboardScreen> {
  Map<String, dynamic>? _profile;

  int? _openIncidents;
  int? _visitorsToday;
  int? _vehiclesRegistered;
  int? _pendingMoveRequests;

  List<Map<String, dynamic>> _visitorLog = const [];
  List<Map<String, dynamic>> _incidents = const [];
  List<Map<String, dynamic>> _moveRequests = const [];

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads the profile, counts, today's visitor log, incidents and pending passes.
  Future<void> _load() async {
    final profile = await SupabaseService.instance.getMyProfile();
    if (mounted) setState(() => _profile = profile);

    final c = SupabaseService.instance.client;
    try {
      // "Today" is the guard's local day; the column is timestamptz, so send
      // local midnight converted to UTC.
      final now = DateTime.now();
      final startOfDay =
          DateTime(now.year, now.month, now.day).toUtc().toIso8601String();

      final results = await Future.wait([
        c.from('security_incidents').select('id, status'),
        c
            .from('visitor_logs')
            .select('id, visitor_name, host_user_id, visiting_lot_id, time_in, time_out')
            .gte('time_in', startOfDay)
            .order('time_in', ascending: false),
        c.from('vehicles').select('id').eq('status', 'active'),
        c
            .from('security_incidents')
            .select('id, incident_number, title, type, severity, status, location, incident_date')
            .order('incident_date', ascending: false)
            .limit(4),
        // Gate passes, not move requests: guards have no move_requests permission.
        c
            .from('gate_passes')
            .select('id')
            .eq('status', 'pending')
            .gte('valid_until', DateTime.now().toUtc().toIso8601String()),
        c
            .from('gate_passes')
            .select('id, pass_number, visitor_name, requested_by, valid_from, valid_until, status')
            .eq('status', 'pending')
            .gte('valid_until', DateTime.now().toUtc().toIso8601String())
            .order('valid_from', ascending: true)
            .limit(5),
      ]);
      if (!mounted) return;

      final incidentsAll = List<Map<String, dynamic>>.from(results[0]);
      final openIncidents =
          incidentsAll.where((i) => {'open', 'investigating'}.contains(i['status'])).length;

      final visitorLog = List<Map<String, dynamic>>.from(results[1]);
      final hostIds = visitorLog.map((v) => v['host_user_id']).whereType<int>().toSet().toList();
      Map<int, String> hostNames = {};
      if (hostIds.isNotEmpty) {
        final lookup = await c
            .from('users')
            .select('id, first_name, last_name')
            .inFilter('id', hostIds);
        for (final u in List<Map<String, dynamic>>.from(lookup)) {
          hostNames[u['id'] as int] = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
        }
      }

      final vehicleCount = (results[2] as List).length;
      final recentIncidents = List<Map<String, dynamic>>.from(results[3]);

      final pendingMoveRequests = (results[4] as List).length;

      final upcomingMoveRequests = List<Map<String, dynamic>>.from(results[5]);
      final residentIds =
          upcomingMoveRequests.map((r) => r['requested_by']).whereType<int>().toSet().toList();
      Map<int, String> residentNames = {};
      if (residentIds.isNotEmpty) {
        final lookup = await c
            .from('users')
            .select('id, first_name, last_name')
            .inFilter('id', residentIds);
        for (final u in List<Map<String, dynamic>>.from(lookup)) {
          residentNames[u['id'] as int] = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
        }
      }

      if (!mounted) return;
      setState(() {
        _openIncidents = openIncidents;
        _visitorsToday = visitorLog.length;
        _vehiclesRegistered = vehicleCount;
        _pendingMoveRequests = pendingMoveRequests;
        _visitorLog = visitorLog
            .take(5)
            .map((v) => {...v, 'host_name': hostNames[v['host_user_id']] ?? '—'})
            .toList();
        _incidents = recentIncidents;
        _moveRequests = upcomingMoveRequests
            .map((r) => {...r, 'resident_name': residentNames[r['requested_by']] ?? '—'})
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  String _time(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
                role: 'security',
                communityName: AppBranding.instance.communityName),
            const SizedBox(height: 24),
            responsiveStatCards((cardWidth) => [
                  DashboardStatCard(
                    icon: Icons.shield_outlined,
                    iconBg: AppColors.badgeRedBg,
                    label: 'Open Incidents',
                    value: _openIncidents?.toString(),
                    width: cardWidth,
                    onTap: () => goFiltered(context, '/admin/security', 'security', 'unresolved'),
                  ),
                  DashboardStatCard(
                    icon: Icons.badge_outlined,
                    iconBg: AppColors.badgeBlueBg,
                    label: 'Visitors Today',
                    value: _visitorsToday?.toString(),
                    width: cardWidth,
                    onTap: () => goFiltered(context, '/admin/visitors', 'visitors', 'today'),
                  ),
                  DashboardStatCard(
                    icon: Icons.directions_car_outlined,
                    iconBg: AppColors.badgeGreenBg,
                    label: 'Vehicles On-Site',
                    value: _vehiclesRegistered?.toString(),
                    width: cardWidth,
                    onTap: () => goFiltered(context, '/admin/vehicles', 'vehicles', 'active'),
                  ),
                  DashboardStatCard(
                    icon: Icons.qr_code_outlined,
                    iconBg: AppColors.badgeGrayBg,
                    label: 'Pending Gate Passes',
                    // Counts only passes not yet expired; the Gate Passes list counts all pending.
                    caption: 'Still valid',
                    value: _pendingMoveRequests?.toString(),
                    width: cardWidth,
                    onTap: () => goFiltered(context, '/admin/gate_passes', 'gate_passes', 'pending'),
                  ),
                ]),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 900;
              final visitorLog = _visitorLogPanel();
              final incidents = _incidentsPanel();
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: visitorLog),
                    const SizedBox(width: 20),
                    Expanded(child: incidents),
                  ],
                );
              }
              return Column(children: [visitorLog, const SizedBox(height: 20), incidents]);
            }),
            const SizedBox(height: 20),
            _moveRequestsTable(),
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
              role: 'security',
              communityName: AppBranding.instance.communityName,
              mobile: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: responsiveStatCards((w) => [
              DashboardStatCard(icon: Icons.shield_outlined, iconBg: AppColors.badgeRedBg, label: 'Open Incidents', value: _openIncidents?.toString(), width: w, onTap: () => goFiltered(context, '/admin/security', 'security', 'unresolved')),
              DashboardStatCard(icon: Icons.badge_outlined, iconBg: AppColors.badgeBlueBg, label: 'Visitors Today', value: _visitorsToday?.toString(), width: w, onTap: () => goFiltered(context, '/admin/visitors', 'visitors', 'today')),
              DashboardStatCard(icon: Icons.directions_car_outlined, iconBg: AppColors.badgeGreenBg, label: 'Vehicles On-Site', value: _vehiclesRegistered?.toString(), width: w, onTap: () => goFiltered(context, '/admin/vehicles', 'vehicles', 'active')),
              DashboardStatCard(icon: Icons.qr_code_outlined, iconBg: AppColors.badgeGrayBg, label: 'Pending Passes', caption: 'Still valid', value: _pendingMoveRequests?.toString(), width: w, onTap: () => goFiltered(context, '/admin/gate_passes', 'gate_passes', 'pending')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _mobileVisitorLogCard(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: _mobileIncidentsCard(),
          ),
        ],
      ),
    );
  }

  Widget _mobileVisitorLogCard() {
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
          const Row(
            children: [
              Expanded(
                child: Text('Visitor Log · Today',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              StatusBadge('active'),
            ],
          ),
          const SizedBox(height: 12),
          if (_visitorLog.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No visitors logged today.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            for (final v in _visitorLog) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((v['visitor_name'] ?? '—').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text('Host: ${v['host_name'] ?? '—'} · ${_time(v['time_in']?.toString())}',
                              style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    StatusBadge(v['time_out'] == null ? 'on-site' : 'departed'),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _mobileIncidentsCard() {
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
          const Text('Recent Incidents',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (_incidents.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No incidents reported yet.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            for (final inc in _incidents) ...[
              InkWell(
                onTap: () => context.go('/admin/security'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((inc['title'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text((inc['location'] ?? '—').toString(),
                                style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      StatusBadge((inc['severity'] ?? '—').toString()),
                      const SizedBox(width: 6),
                      StatusBadge((inc['status'] ?? '—').toString()),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _visitorLogPanel() {
    return DashboardPanel(
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('Visitor Log - Today',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Spacer(),
              StatusBadge('active'),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(flex: 3, child: DashboardColHeader('VISITOR')),
              Expanded(flex: 2, child: DashboardColHeader('HOST')),
              Expanded(flex: 2, child: DashboardColHeader('TIME IN')),
              Expanded(flex: 2, child: DashboardColHeader('STATUS')),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Expanded(
            child: _visitorLog.isEmpty
                ? const Text('No visitors logged today.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
                : ListView.separated(
                    itemCount: _visitorLog.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, i) {
                      final v = _visitorLog[i];
                      final status = v['time_out'] == null ? 'on-site' : 'departed';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                                flex: 3,
                                child: Text((v['visitor_name'] ?? '—').toString(),
                                    style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary))),
                            Expanded(
                                flex: 2,
                                child: Text(v['host_name'] ?? '—',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                            Expanded(
                                flex: 2,
                                child: Text(_time(v['time_in']?.toString()),
                                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
                            Expanded(flex: 2, child: StatusBadge(status)),
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

  Widget _incidentsPanel() {
    return DashboardPanel(
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Incidents',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Expanded(
            child: _incidents.isEmpty
                ? const Text('No incidents reported yet.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
                : ListView.separated(
                    itemCount: _incidents.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final inc = _incidents[i];
                      return InkWell(
                        onTap: () => context.go('/admin/security'),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.contentBg, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((inc['title'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text((inc['location'] ?? '—').toString(),
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                StatusBadge((inc['severity'] ?? '—').toString()),
                                const SizedBox(height: 4),
                                StatusBadge((inc['status'] ?? '—').toString()),
                              ],
                            ),
                          ],
                        ),
                      ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Table of pending gate passes (the names say "move requests" from earlier code).
  Widget _moveRequestsTable() {
    return DashboardPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gate Passes · Awaiting the Guardhouse',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (_moveRequests.isEmpty)
            const DashboardEmptyNote('No passes waiting for the guardhouse.')
          else ...[
            const Row(
              children: [
                Expanded(flex: 3, child: DashboardColHeader('VISITOR')),
                Expanded(flex: 2, child: DashboardColHeader('HOST')),
                Expanded(flex: 2, child: DashboardColHeader('VALID FROM')),
                Expanded(flex: 2, child: DashboardColHeader('STATUS')),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: AppColors.border),
            ),
            for (final r in _moveRequests) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child: Text((r['visitor_name'] ?? '—').toString(),
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary))),
                    Expanded(
                        flex: 2,
                        child: Text((r['resident_name'] ?? '—').toString(),
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                    Expanded(
                        flex: 2,
                        child: Text((r['valid_from']?.toString() ?? '—').split('T').first,
                            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
                    Expanded(flex: 2, child: StatusBadge((r['status'] ?? '—').toString())),
                  ],
                ),
              ),
              if (r != _moveRequests.last) const Divider(height: 1, color: AppColors.border),
            ],
          ],
        ],
      ),
    );
  }
}
