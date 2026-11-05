import 'package:flutter/material.dart';
import '../core/branding.dart';
import '../core/card_filter.dart';
import 'package:go_router/go_router.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/responsive_officer_shell.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';
import '../core/local_time.dart';

/// Treasurer dashboard: stat cards, collections chart, recent payments and
/// a budget-vs-actual table.
///
/// Budget figures come from `budget_categories` and `budget_expenses` for the
/// current year (spent = sum of a category's expenses), like the Budget tab.
class TreasurerDashboardScreen extends StatefulWidget {
  const TreasurerDashboardScreen({super.key});

  @override
  State<TreasurerDashboardScreen> createState() => _TreasurerDashboardScreenState();
}

class _TreasurerDashboardScreenState extends State<TreasurerDashboardScreen> with SafeSetState<TreasurerDashboardScreen> {
  Map<String, dynamic>? _profile;

  double? _collectionsMtd;
  double? _pendingBills;
  int? _overdueAccounts;

  List<MonthAmount> _monthly = const [];
  double _collectionRate = 0;
  double _collectedYtd = 0;

  List<Map<String, dynamic>> _recentPayments = const [];

  List<Map<String, dynamic>> _budgetCategories = const [];
  List<Map<String, dynamic>> _budgetExpenses = const [];
  final int _fiscalYear = DateTime.now().year;

  /// Amount allocated to a budget category.
  double _allocated(Map<String, dynamic> cat) =>
      (num.tryParse(cat['allocated_amount']?.toString() ?? '0') ?? 0).toDouble();

  /// Total expenses recorded against a budget category.
  double _spent(Map<String, dynamic> cat) => _budgetExpenses
      .where((e) => e['category_id'] == cat['id'])
      .fold<double>(0, (s, e) => s + (num.tryParse(e['amount']?.toString() ?? '0') ?? 0));

  double get _totalAllocated => _budgetCategories.fold<double>(0, (s, c) => s + _allocated(c));
  double get _totalSpent => _budgetCategories.fold<double>(0, (s, c) => s + _spent(c));

  /// Spent / allocated. Null (not 0) when nothing is allocated, so the card
  /// shows empty instead of "0%".
  double? get _utilization =>
      _totalAllocated <= 0 ? null : (_totalSpent / _totalAllocated).clamp(0, 999).toDouble();

  /// 'over', 'near_limit' (85% or more spent) or 'on_track'.
  String _budgetStatus(double allocated, double spent) {
    if (allocated <= 0) return spent > 0 ? 'over' : 'on_track';
    final ratio = spent / allocated;
    if (ratio > 1) return 'over';
    if (ratio >= 0.85) return 'near_limit';
    return 'on_track';
  }

  Color _statusBg(String s) => switch (s) {
        'over' => const Color(0xFFFBE4E4),
        'near_limit' => const Color(0xFFFBEFD6),
        _ => const Color(0xFFE3F1E9),
      };
  Color _statusFg(String s) => switch (s) {
        'over' => const Color(0xFFA82F2F),
        'near_limit' => const Color(0xFF8A6300),
        _ => const Color(0xFF1A6B43),
      };
  String _statusLabel(String s) => switch (s) {
        'over' => 'Over',
        'near_limit' => 'Near Limit',
        _ => 'On Track',
      };

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads the stat cards, chart, recent payments and budget data.
  Future<void> _load() async {
    final profile = await SupabaseService.instance.getMyProfile();
    if (mounted) setState(() => _profile = profile);

    final c = SupabaseService.instance.client;
    try {
      final results = await Future.wait([
        c.from('bills').select('amount, penalty_amount, discount_amount, status, due_date'),
        c.from('payments').select('amount_paid, payment_date, status'),
        c
            .from('payments')
            .select('id, or_number, amount_paid, payment_method, payment_date, status, user_id')
            .order('payment_date', ascending: false)
            .limit(5),
        c.from('budget_categories').select('*').eq('fiscal_year', _fiscalYear).order('name'),
        c.from('budget_expenses').select('id, category_id, amount'),
      ]);
      if (!mounted) return;

      final bills = List<Map<String, dynamic>>.from(results[0]);
      final payments = List<Map<String, dynamic>>.from(results[1]);

      // Local month, not UTC (see core/local_time.dart); the Payments
      // screen's Collected card uses the same rule.
      final mtd = payments
          .where((p) => p['status'] == 'verified' && isThisMonth(p['payment_date']))
          .fold<double>(0, (s, p) => s + (num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0));

      final pending = bills.where((b) => {'pending', 'overdue', 'partial'}.contains(b['status']));
      final pendingTotal = pending.fold<double>(0, (sum, b) {
        final amt = num.tryParse(b['amount']?.toString() ?? '0') ?? 0;
        final pen = num.tryParse(b['penalty_amount']?.toString() ?? '0') ?? 0;
        final disc = num.tryParse(b['discount_amount']?.toString() ?? '0') ?? 0;
        return sum + amt + pen - disc;
      });

      final overdueCount = bills.where((b) => b['status'] == 'overdue').length;

      final buckets = buildCollectionsBuckets(bills, payments);
      final rate = buckets.billedYear <= 0
          ? 0.0
          : (buckets.collectedYtd / buckets.billedYear).clamp(0, 1).toDouble();

      final recent = List<Map<String, dynamic>>.from(results[2]);
      final userIds = recent.map((r) => r['user_id']).whereType<int>().toSet().toList();
      Map<int, String> userNames = {};
      // Own try/catch: without `users` access only this lookup fails, not
      // the whole load.
      if (userIds.isNotEmpty) {
        try {
          final lookup = await c
              .from('users')
              .select('id, first_name, last_name')
              .inFilter('id', userIds);
          for (final u in List<Map<String, dynamic>>.from(lookup)) {
            userNames[u['id'] as int] = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
          }
        } catch (_) {
          // No `users` read access: names stay blank.
        }
      }

      if (!mounted) return;
      setState(() {
        _collectionsMtd = mtd;
        _pendingBills = pendingTotal;
        _overdueAccounts = overdueCount;
        _monthly = buckets.buckets;
        _collectionRate = rate;
        _collectedYtd = buckets.collectedYtd;
        _recentPayments = recent
            .map((r) => {...r, 'resident_name': userNames[r['user_id']] ?? '—'})
            .toList();
        _budgetCategories = List<Map<String, dynamic>>.from(results[3]);
        _budgetExpenses = List<Map<String, dynamic>>.from(results[4]);
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
                role: 'treasurer',
                communityName: AppBranding.instance.communityName),
            const SizedBox(height: 24),
            responsiveStatCards((cardWidth) => [
                  DashboardStatCard(
                    icon: Icons.account_balance_wallet_outlined,
                    iconBg: AppColors.badgeGreenBg,
                    label: 'Collections MTD',
                    value: _collectionsMtd == null ? null : dashboardMoney(_collectionsMtd!),
                    width: cardWidth,
                    onTap: () => goFiltered(context, '/admin/finance?tab=payments', 'payments', 'month'),
                  ),
                  DashboardStatCard(
                    icon: Icons.receipt_long_outlined,
                    iconBg: AppColors.badgeAmberBg,
                    label: 'Pending Bills',
                    value: _pendingBills == null ? null : dashboardMoney(_pendingBills!),
                    width: cardWidth,
                    onTap: () => goFiltered(context, '/admin/finance', 'billing', 'outstanding'),
                  ),
                  DashboardStatCard(
                    icon: Icons.warning_amber_outlined,
                    iconBg: AppColors.badgeRedBg,
                    label: 'Overdue Accounts',
                    value: _overdueAccounts?.toString(),
                    width: cardWidth,
                    onTap: () => goFiltered(context, '/admin/finance', 'billing', 'overdue'),
                  ),
                  DashboardStatCard(
                    icon: Icons.pie_chart_outline,
                    iconBg: AppColors.badgeGrayBg,
                    label: 'Budget Utilization',
                    value: _utilization == null
                        ? null
                        : '${(_utilization! * 100).toStringAsFixed(0)}%',
                    width: cardWidth,
                    onTap: () => context.go('/admin/finance?tab=budget'),
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
              final recent = _recentPaymentsPanel();
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: collections),
                    const SizedBox(width: 20),
                    Expanded(child: recent),
                  ],
                );
              }
              return Column(children: [collections, const SizedBox(height: 20), recent]);
            }),
            const SizedBox(height: 20),
            _budgetTable(),
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
              role: 'treasurer',
              communityName: AppBranding.instance.communityName,
              mobile: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: responsiveStatCards((w) => [
              DashboardStatCard(icon: Icons.account_balance_wallet_outlined, iconBg: AppColors.badgeGreenBg, label: 'Collections MTD', value: _collectionsMtd == null ? null : dashboardMoney(_collectionsMtd!), width: w, onTap: () => goFiltered(context, '/admin/finance?tab=payments', 'payments', 'month')),
              DashboardStatCard(icon: Icons.receipt_long_outlined, iconBg: AppColors.badgeAmberBg, label: 'Pending Bills', value: _pendingBills == null ? null : dashboardMoney(_pendingBills!), width: w, onTap: () => goFiltered(context, '/admin/finance', 'billing', 'outstanding')),
              DashboardStatCard(icon: Icons.warning_amber_outlined, iconBg: AppColors.badgeRedBg, label: 'Overdue Accts', value: _overdueAccounts?.toString(), width: w, onTap: () => goFiltered(context, '/admin/finance', 'billing', 'overdue')),
              DashboardStatCard(icon: Icons.pie_chart_outline, iconBg: AppColors.badgeGrayBg, label: 'Budget Used', value: _utilization == null ? null : '${(_utilization! * 100).toStringAsFixed(0)}%', width: w, onTap: () => context.go('/admin/finance?tab=budget')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _mobileCollectionsCard(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: _mobileRecentPaymentsCard(),
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
          const Text('Collections Overview',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: _monthly.isEmpty
                ? const Center(
                    child: Text('No billing activity yet.',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted)))
                // Only "Collected" on phones; two series would be too thin.
                : TrendLineChart(
                    labels: [for (final m in _monthly) dashboardMonthLabels[m.month - 1]],
                    series: [
                      ChartSeries(
                          label: 'Collected',
                          color: kSeriesColors[0],
                          values: [for (final m in _monthly) m.collected]),
                    ],
                    formatValue: (v) => '\u20B1${compactNumber(v)}',
                  ),
          ),
          const SizedBox(height: 10),
          Text('${dashboardMoney(_collectedYtd)} collected YTD · ${(_collectionRate * 100).toStringAsFixed(0)}% rate',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _mobileRecentPaymentsCard() {
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
          const Text('Recent Payments',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (_recentPayments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No payments recorded yet.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            )
          else
            for (final p in _recentPayments) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['resident_name'] ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(titleCase((p['payment_method'] ?? '').toString()),
                              style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Text('₱${(num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                    const SizedBox(width: 10),
                    StatusBadge((p['status'] ?? '').toString()),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _recentPaymentsPanel() {
    return DashboardPanel(
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Payments',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Expanded(
            child: _recentPayments.isEmpty
                ? const Text('No payments recorded yet.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
                : ListView.separated(
                    itemCount: _recentPayments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final p = _recentPayments[i];
                      final amt = num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0;
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p['resident_name'] ?? '—',
                                    style: const TextStyle(
                                        fontSize: 13, color: AppColors.textPrimary)),
                                const SizedBox(height: 2),
                                Text(
                                    titleCase((p['payment_method'] ?? '').toString()),
                                    style: const TextStyle(
                                        fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Text('₱${amt.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                          const SizedBox(width: 12),
                          StatusBadge((p['status'] ?? '').toString()),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _budgetTable() {
    return DashboardPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Budget vs Actual by Category ($_fiscalYear)',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          if (_budgetCategories.isEmpty)
            DashboardEmptyNote(
              'No budget categories set up yet for $_fiscalYear. '
              'Add categories under Finance > Budget to see them here.',
            )
          else
            for (final cat in _budgetCategories) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text((cat['name'] ?? '—').toString(),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ),
                    Text('₱${_spent(cat).toStringAsFixed(0)} / ₱${_allocated(cat).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    const SizedBox(width: 12),
                    Builder(builder: (_) {
                      final status = _budgetStatus(_allocated(cat), _spent(cat));
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusBg(status),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_statusLabel(status),
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: _statusFg(status))),
                      );
                    }),
                  ],
                ),
              ),
              if (cat != _budgetCategories.last) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}
