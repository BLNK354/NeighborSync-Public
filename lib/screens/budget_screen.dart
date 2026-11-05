import 'package:flutter/material.dart';
import '../widgets/pagination_footer.dart';
import '../core/dialog_sizing.dart';
import '../core/form_helpers.dart';
import '../core/module_registry.dart';
import '../core/permissions.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/charts.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/module_form_dialog.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Budget tab for officers, using `budget_categories` and `budget_expenses`.
/// Treasurer and super admin can edit; HOA president, secretary and audit
/// officer can only view.
///
/// "Spent" is the live sum of a category's expenses. "Variance" is total
/// spent minus total allocated. Shown as a tab inside FinanceScreen.
class AdminBudgetScreen extends StatefulWidget {
  const AdminBudgetScreen({super.key});

  @override
  State<AdminBudgetScreen> createState() => _AdminBudgetScreenState();
}

class _AdminBudgetScreenState extends State<AdminBudgetScreen>
    with SafeSetState<AdminBudgetScreen>, TableSortState {
  // 1-based page for the 10-row pager (pagination_footer.dart).
  int _page = 1;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;
  String? _error;
  int _fiscalYear = DateTime.now().year;

  /// Whether this officer may change the budget. Read-only roles see the
  /// figures without the buttons.
  bool _canEdit = false;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = SupabaseService.instance.client;
      final results = await Future.wait([
        c.from('budget_categories').select('*').eq('fiscal_year', _fiscalYear).order('name'),
        c.from('budget_expenses').select('id, category_id, description, amount, expense_date'),
      ]);
      final perms = await SupabaseService.instance.getMyPermissions();
      if (!mounted) return;
      setState(() {
        _categories = List<Map<String, dynamic>>.from(results[0] as List);
        _expenses = List<Map<String, dynamic>>.from(results[1] as List);
        _canEdit = canPerform(perms, 'budget', 'update');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  double _allocated(Map<String, dynamic> cat) =>
      (num.tryParse(cat['allocated_amount']?.toString() ?? '0') ?? 0).toDouble();

  double _spent(Map<String, dynamic> cat) => _expenses
      .where((e) => e['category_id'] == cat['id'])
      .fold<double>(0, (s, e) => s + (num.tryParse(e['amount']?.toString() ?? '0') ?? 0));

  double get _totalAllocated => _categories.fold<double>(0, (s, c) => s + _allocated(c));
  double get _totalSpent => _categories.fold<double>(0, (s, c) => s + _spent(c));
  double get _remaining => _totalAllocated - _totalSpent;
  double get _variance => _totalSpent - _totalAllocated;

  /// 'over' above 100% spent, 'near_limit' from 85%, otherwise 'on_track'.
  String _statusFor(double allocated, double spent) {
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

  /// Picks the fiscal year to show. The range (2010 to five years ahead)
  /// must match what trg_02_fiscal_year allows.
  Future<void> _pickFiscalYear() async {
    final now = DateTime.now().year;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fiscal Year'),
        content: SizedBox(
          width: dialogContentWidth(context, 300),
          height: 320,
          child: YearPicker(
            firstDate: DateTime(2010),
            lastDate: DateTime(now + 5),
            selectedDate: DateTime(_fiscalYear),
            onChanged: (d) => Navigator.pop(ctx, d.year),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (picked == null || picked == _fiscalYear) return;
    setState(() => _fiscalYear = picked);
    _load();
  }

  Future<void> _addCategory() async {
    final saved = await showModuleFormDialog(context, budgetCategories);
    if (saved == true) _load();
  }

  /// Opens the expense form, optionally with a category already chosen.
  /// Use `prefill`, not `initial`: `initial != null` turns it into an UPDATE.
  Future<void> _recordExpense([Map<String, dynamic>? forCategory]) async {
    final saved = await showModuleFormDialog(
      context,
      budgetExpenses,
      prefill: forCategory == null
          ? null
          : {'category_id': forCategory['id']},
    );
    if (saved == true) _load();
  }

  /// Short peso format, e.g. ₱1.5k or ₱2.0M.
  static String _compact(double n) {
    final sign = n < 0 ? '-' : '';
    final abs = n.abs();
    if (abs >= 1000000) return '$sign₱${(abs / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '$sign₱${(abs / 1000).toStringAsFixed(1)}k';
    return '$sign₱${abs.toStringAsFixed(0)}';
  }

  /// 0 Category · 1 Allocated · 2 Spent · 3 Remaining · 4 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> cat, int col) {
    switch (col) {
      case 0:
        return text(cat['name']);
      case 1:
        return _allocated(cat);
      case 2:
        return _spent(cat);
      case 3:
        return _allocated(cat) - _spent(cat);
      case 4:
        return text(_statusFor(_allocated(cat), _spent(cat)));
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    return LayoutBuilder(builder: (context, constraints) {
      return constraints.maxWidth < 700 ? _mobileBody() : _desktopBody();
    });
  }

  Widget _desktopBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Fiscal Year $_fiscalYear',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _pickFiscalYear,
                icon: const Icon(Icons.calendar_month_outlined, size: 16),
                label: Text('$_fiscalYear'),
              ),
              if (_canEdit) ...[
                const SizedBox(width: 10),
                OutlinedButton(onPressed: _addCategory, child: const Text('Add Category')),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _categories.isEmpty ? null : () => _recordExpense(),
                  child: const Text('Record Expense'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          responsiveStatCards((w) => [
            DashboardStatCard(icon: Icons.account_balance_wallet_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Total Budget', value: _compact(_totalAllocated), width: w),
            DashboardStatCard(icon: Icons.bar_chart, iconBg: const Color(0xFFE2F0F7), label: 'Spent', value: _compact(_totalSpent), width: w),
            DashboardStatCard(icon: Icons.savings_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Remaining', value: _compact(_remaining), width: w),
            DashboardStatCard(icon: Icons.trending_up, iconBg: const Color(0xFFFBE4E4), label: 'Variance', value: _compact(_variance), width: w),
          ]),
          const SizedBox(height: 20),
          if (_categories.isEmpty)
            _emptyState()
          else ...[
            _chartCard(),
            const SizedBox(height: 20),
            _tableCard(),
          ],
        ],
      ),
    );
  }

  // ---------- mobile body ----------
  //
  // No bar chart on narrow screens; each category card shows the numbers.
  Widget _mobileBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Text('FY $_fiscalYear',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              const Spacer(),
              IconButton(
                onPressed: _pickFiscalYear,
                tooltip: 'Choose fiscal year',
                icon: const Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.textSecondary),
              ),
              if (_canEdit) ...[
                IconButton(
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add_circle_outline, size: 20, color: AppColors.textSecondary),
                  tooltip: 'Add Category',
                ),
                FilledButton(
                  onPressed: _categories.isEmpty ? null : () => _recordExpense(),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                  child: const Text('+ Expense', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: responsiveStatCards((w) => [
            DashboardStatCard(icon: Icons.account_balance_wallet_outlined, iconBg: const Color(0xFFE3F1E9), label: 'Total Budget', value: _compact(_totalAllocated), width: w),
            DashboardStatCard(icon: Icons.bar_chart, iconBg: const Color(0xFFE2F0F7), label: 'Spent', value: _compact(_totalSpent), width: w),
            DashboardStatCard(icon: Icons.savings_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Remaining', value: _compact(_remaining), width: w),
            DashboardStatCard(icon: Icons.trending_up, iconBg: const Color(0xFFFBE4E4), label: 'Variance', value: _compact(_variance), width: w),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _categories.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: _emptyState(),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: pageSlice(_categories, _page).length + (pageCountFor(_categories.length) > 1 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= pageSlice(_categories, _page).length) {
                      return pagerFor(_categories.length, _page, (p) => setState(() => _page = p));
                    }
                    final cat = pageSlice(_categories, _page)[i];
                    final allocated = _allocated(cat);
                    final spent = _spent(cat);
                    final status = _statusFor(allocated, spent);
                    return InkWell(
                      // Null onTap keeps the card inert for read-only roles.
                      onTap: _canEdit ? () => _recordExpense(cat) : null,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((cat['name'] ?? '').toString(),
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  const SizedBox(height: 3),
                                  Text('${_compact(spent)} of ${_compact(allocated)}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            _statusChip(status),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.pie_chart_outline, size: 32, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text('No budget categories set up for $_fiscalYear yet.',
                style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('Use "Add Category" above to allocate this year\'s budget.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _chartCard() {
    // Allocated vs spent bars per category, on the shared chart painter.
    return ChartCard(
      title: 'Budget vs Actual',
      height: 240,
      isEmpty: _categories.isEmpty,
      emptyMessage: 'No budget categories for this fiscal year yet.',
      series: [
        ChartSeries(
            label: 'Allocated',
            color: kSeriesColors[0],
            values: [for (final c in _categories) _allocated(c)]),
        ChartSeries(
            label: 'Spent',
            color: kSeriesColors[1],
            values: [for (final c in _categories) _spent(c)]),
      ],
      chart: GroupedBarChart(
        labels: [for (final c in _categories) (c['name'] ?? '').toString()],
        series: [
          ChartSeries(
              label: 'Allocated',
              color: kSeriesColors[0],
              values: [for (final c in _categories) _allocated(c)]),
          ChartSeries(
              label: 'Spent',
              color: kSeriesColors[1],
              values: [for (final c in _categories) _spent(c)]),
        ],
        formatValue: (v) => '\u20B1${compactNumber(v)}',
      ),
    );
  }


  Widget _tableCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: fullWidthTable(
            footer: pagerFor(_categories.length, _page, (p) => setState(() => _page = p)),
            
        DataTable(
          showCheckboxColumn: false,
          sortColumnIndex: sortColumn,
          sortAscending: sortAsc,
          columnSpacing: 28,
          headingRowHeight: 40,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
          headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
          dataTextStyle: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
          columns: [
            DataColumn(label: const Text('CATEGORY'), onSort: onSort),
            DataColumn(label: const Text('ALLOCATED'), onSort: onSort),
            DataColumn(label: const Text('SPENT'), onSort: onSort),
            DataColumn(label: const Text('REMAINING'), onSort: onSort),
            DataColumn(label: const Text('STATUS'), onSort: onSort),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (final cat in pageSlice(sortRows(_categories), _page))
              DataRow(cells: [
                DataCell(Text((cat['name'] ?? '').toString())),
                DataCell(Text(_compact(_allocated(cat)))),
                DataCell(Text(_compact(_spent(cat)))),
                DataCell(Text(_compact(_allocated(cat) - _spent(cat)))),
                DataCell(_statusChip(_statusFor(_allocated(cat), _spent(cat)))),
                DataCell(
                  _canEdit
                      ? TextButton(
                          onPressed: () => _recordExpense(cat),
                          child: const Text('+ Expense'),
                        )
                      : const SizedBox.shrink(),
                ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _statusBg(status), borderRadius: BorderRadius.circular(12)),
      child: Text(_statusLabel(status),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _statusFg(status))),
    );
  }
}
