import 'package:flutter/material.dart';
import '../core/fetch_all.dart';
import '../core/card_filter.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import 'package:flutter/services.dart';
import '../core/module_registry.dart';
import '../core/permissions.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/payment_proof_actions.dart';
import '../widgets/payment_review_dialog.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';
import '../core/local_time.dart';

/// Officer-facing Payments screen: stat cards from the `payments` data, a
/// queue of resident receipts to review, and a table of recent payments.
/// "Record Payment" reuses the shared payments form.
///
/// Embedded as a tab inside FinanceScreen rather than its own shell page.
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen>
    with SafeSetState<AdminPaymentsScreen>, TableSortState {
  // 1-based page for the 10-row pager (pagination_footer.dart).
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';
  // Whether this officer may verify payments (payments:approve). New
  // payments start 'pending'; a database trigger updates the bill on verify.
  bool _canVerify = false;

  /// Resident-uploaded proof of payment awaiting review. Needs payments:update,
  /// the same permission the database re-checks on approval.
  List<Map<String, dynamic>> _submissions = [];
  bool _canReview = false;

  /// Whether the officer may record a payment by hand (payments:create).
  bool _canCreate = false;
  bool _reviewing = false;

  @override
  void initState() {
    super.initState();
    // A dashboard card may have sent us here already narrowed (card_filter.dart).
    _statusFilter = CardFilter.take('payments') ?? _statusFilter;
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads payments, the caller's permissions and pending receipt submissions.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        fetchAllRows((from, to) => SupabaseService.instance.client
            .from('payments')
            .select('*, resident:user_id(first_name, last_name)')
            .order('payment_date', ascending: false)
            .order('id', ascending: false)
            .range(from, to)),
        SupabaseService.instance.getMyPermissions(),
        SupabaseService.instance.client
            .from('payment_submissions')
            .select('*, resident:user_id(first_name, last_name), bill:bill_id(bill_number, description)')
            .eq('status', 'pending')
            .order('created_at', ascending: false)
            .limit(100),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(results[0] as List);
        final perms = results[1] as Map<String, Set<String>>;
        _canVerify = canPerform(perms, 'payments', 'approve');
        _canReview = canPerform(perms, 'payments', 'update');
        _canCreate = canPerform(perms, 'payments', 'create');
        _submissions = List<Map<String, dynamic>>.from(results[2] as List);
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

  /// Opens the review dialog (read-only without verify permission) and
  /// reloads if anything changed.
  Future<void> _reviewPayment(Map<String, dynamic> p) async {
    final changed = await reviewPayment(context, p,
        residentName: _residentName(p), readOnly: !_canVerify);
    if (changed) _load();
  }

  /// Resident's full name, or a dash if unknown.
  String _residentName(Map<String, dynamic> row) {
    final r = row['resident'] as Map<String, dynamic>?;
    if (r == null) return '—';
    final n = [r['first_name'], r['last_name']]
        .where((s) => s != null && s.toString().isNotEmpty)
        .join(' ');
    return n.isEmpty ? '—' : n;
  }

  /// Shows the uploaded receipt (shared with the bill detail page).
  Future<void> _viewReceipt(Map<String, dynamic> sub) =>
      viewPaymentReceipt(context, sub['receipt_path'] as String?);

  /// Approves a submitted receipt. The dialogs and rules are shared with the
  /// bill detail page in widgets/payment_proof_actions.dart.
  Future<void> _approveSubmission(Map<String, dynamic> sub) async {
    setState(() => _reviewing = true);
    final done = await approvePaymentSubmission(
      context,
      sub,
      residentName: _residentName(sub),
      billNumber:
          ((sub['bill'] as Map<String, dynamic>?)?['bill_number'] ?? sub['bill_id'])?.toString(),
    );
    if (!mounted) return;
    setState(() => _reviewing = false);
    if (done) _load();
  }

  /// Rejects a submitted receipt (a reason is asked for in the shared dialog).
  Future<void> _rejectSubmission(Map<String, dynamic> sub) async {
    setState(() => _reviewing = true);
    final done = await rejectPaymentSubmission(context, sub);
    if (!mounted) return;
    setState(() => _reviewing = false);
    if (done) _load();
  }

  double _amt(Map<String, dynamic> p) => (num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0).toDouble();

  /// `payment_date` arrives as UTC; it must be converted to local time to
  /// compare with `DateTime.now()` (core/local_time.dart).
  DateTime? _date(Map<String, dynamic> p) => localTime(p['payment_date']);

  double get _collectedThisMonth {
    final now = DateTime.now();
    return _rows
        .where((p) => p['status'] == 'verified')
        .where((p) {
          final d = _date(p);
          return d != null && d.year == now.year && d.month == now.month;
        })
        .fold<double>(0, (s, p) => s + _amt(p));
  }

  double get _pendingTotal =>
      _rows.where((p) => p['status'] == 'pending').fold<double>(0, (s, p) => s + _amt(p));

  double get _refundedTotal =>
      _rows.where((p) => p['status'] == 'refunded').fold<double>(0, (s, p) => s + _amt(p));

  bool _inThisMonth(Map<String, dynamic> p) {
    final d = _date(p), now = DateTime.now();
    return d != null && d.year == now.year && d.month == now.month;
  }

  /// 'month' is the Collected card's filter: verified payments this month.
  List<Map<String, dynamic>> get _visible => switch (_statusFilter) {
        'all' => _rows,
        'month' => _rows.where((p) => p['status'] == 'verified' && _inThisMonth(p)).toList(),
        _ => _rows.where((p) => p['status'] == _statusFilter).toList(),
      };

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String get _collectedLabel => 'Collected · ${_months[DateTime.now().month - 1]}';

  /// Caption under the month total: the payment count, or when the last
  /// verified payment was if there are none this month.
  String get _collectedCaption {
    final mine = _rows.where((p) => p['status'] == 'verified' && _inThisMonth(p)).length;
    if (mine > 0) return '$mine payment${mine == 1 ? '' : 's'} this month';
    final last = _rows
        .where((p) => p['status'] == 'verified')
        .map(_date)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, d) => a == null || d.isAfter(a) ? d : a);
    return last == null
        ? 'No verified payments yet'
        : 'None yet this month · last ${_months[last.month - 1]} ${last.day}';
  }

  void _tapCard(String v) => setState(() {
        _statusFilter = _statusFilter == v ? 'all' : v;
        _page = 1;
      });

  /// Opens the record-payment form and reloads on save.
  Future<void> _openForm() async {
    final saved = await showModuleFormDialog(context, payments);
    if (saved == true) _load();
  }

  /// Copies the shown payments to the clipboard as CSV.
  void _exportCsv() {
    final rows = _visible;
    final buffer = StringBuffer('OR Number,Resident,Amount,Method,Date,Status\n');
    for (final p in rows) {
      final r = p['resident'] as Map<String, dynamic>?;
      final name = r == null ? '' : [r['first_name'], r['last_name']].where((s) => s != null).join(' ');
      buffer.writeln(
          '${p['or_number']},$name,${_amt(p)},${p['payment_method']},${p['payment_date']},${p['status']}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Copied ${rows.length} payments as CSV to clipboard.')));
  }

  /// Short peso amount, e.g. ₱1.5k or ₱2.0M.
  static String _compact(double n) {
    final abs = n.abs();
    if (abs >= 1000000) return '₱${(n / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '₱${(n / 1000).toStringAsFixed(1)}k';
    return '₱${n.toStringAsFixed(0)}';
  }

  /// 0 OR# · 1 Resident · 2 Amount · 3 Method · 4 Date · 5 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> p, int col) {
    switch (col) {
      case 0:
        return text(p['or_number']);
      case 1:
        return text(_residentName(p));
      case 2:
        return _amt(p);
      case 3:
        return text(p['payment_method']);
      case 4:
        return date(p['payment_date']);
      case 5:
        return rankedKey(p['status'], kStatusRank);
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Recent payments',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'all', child: Text('All statuses')),
                  PopupMenuItem(value: 'pending', child: Text('Pending')),
                  PopupMenuItem(value: 'verified', child: Text('Verified')),
                  PopupMenuItem(value: 'rejected', child: Text('Rejected')),
                  PopupMenuItem(value: 'refunded', child: Text('Refunded')),
                ],
                child: OutlinedButton(
                  onPressed: null,
                  child: Text(_statusFilter == 'all' ? 'Filter' : _statusFilter == 'month' ? 'This month' : titleCase(_statusFilter)),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: _exportCsv, child: const Text('Export')),
              const SizedBox(width: 10),
              if (_canCreate) FilledButton(onPressed: _openForm, child: const Text('Record Payment')),
            ],
          ),
          const SizedBox(height: 18),
          responsiveStatCards((w) => [
            DashboardStatCard(icon: Icons.credit_card, iconBg: const Color(0xFFE3F1E9), label: _collectedLabel, value: _compact(_collectedThisMonth), width: w, caption: _collectedCaption, selected: _statusFilter == 'month', onTap: () => _tapCard('month')),
            DashboardStatCard(icon: Icons.receipt_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Pending', value: _compact(_pendingTotal), width: w, selected: _statusFilter == 'pending', onTap: () => setState(() { _statusFilter = _statusFilter == 'pending' ? 'all' : 'pending'; _page = 1; })),
            DashboardStatCard(icon: Icons.credit_card_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Refunded', value: _compact(_refundedTotal), width: w, selected: _statusFilter == 'refunded', onTap: () => setState(() { _statusFilter = _statusFilter == 'refunded' ? 'all' : 'refunded'; _page = 1; })),
          ]),
          _submissionsQueue(),
          const SizedBox(height: 20),
          Expanded(child: _buildTable()),
        ],
      ),
    );
  }

  /// Resident-submitted receipts waiting for review. Hidden when the queue
  /// is empty or the caller cannot review.
  Widget _submissionsQueue() {
    if (!_canReview || _submissions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8D8AE)),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 18, color: Color(0xFF8A6300)),
                const SizedBox(width: 8),
                Text('Proof of payment awaiting review (${_submissions.length})',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Residents uploaded these receipts. Verifying one records the '
              'payment against their bill.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            for (final s in _submissions) _submissionRow(s),
          ],
        ),
      ),
    );
  }

  /// One submitted receipt with Receipt, Reject and Verify buttons.
  Widget _submissionRow(Map<String, dynamic> sub) {
    final bill = sub['bill'] as Map<String, dynamic>?;
    final amount = num.tryParse(sub['amount'].toString()) ?? 0;
    final note = (sub['note'] ?? '').toString().trim();
    final ref = (sub['reference_number'] ?? '').toString().trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.contentBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_residentName(sub)} · ₱${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '#${bill?['bill_number'] ?? sub['bill_id']} '
                  '${bill?['description'] ?? ''} · '
                  '${titleCase((sub['payment_method'] ?? '').toString())}'
                  '${ref.isEmpty ? '' : ' · Ref $ref'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('"$note"',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () => _viewReceipt(sub),
                icon: const Icon(Icons.image_outlined, size: 15),
                label: const Text('Receipt'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _reviewing ? null : () => _rejectSubmission(sub),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFA82F2F)),
                child: const Text('Reject'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _reviewing ? null : () => _approveSubmission(sub),
                child: const Text('Verify'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Phone layout for the Payments tab.
  Widget _mobileBody() {
    final rows = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: responsiveStatCards((w) => [
            DashboardStatCard(icon: Icons.credit_card, iconBg: const Color(0xFFE3F1E9), label: _collectedLabel, value: _compact(_collectedThisMonth), width: w, caption: _collectedCaption, selected: _statusFilter == 'month', onTap: () => _tapCard('month')),
            DashboardStatCard(icon: Icons.receipt_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Pending', value: _compact(_pendingTotal), width: w, selected: _statusFilter == 'pending', onTap: () => setState(() { _statusFilter = _statusFilter == 'pending' ? 'all' : 'pending'; _page = 1; })),
            DashboardStatCard(icon: Icons.credit_card_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Refunded', value: _compact(_refundedTotal), width: w, selected: _statusFilter == 'refunded', onTap: () => setState(() { _statusFilter = _statusFilter == 'refunded' ? 'all' : 'refunded'; _page = 1; })),
          ]),
        ),
        // Same receipt queue as desktop.
        if (_canReview && _submissions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _submissionsQueue(),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('Recent payments',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'all', child: Text('All statuses')),
                  PopupMenuItem(value: 'pending', child: Text('Pending')),
                  PopupMenuItem(value: 'verified', child: Text('Verified')),
                  PopupMenuItem(value: 'rejected', child: Text('Rejected')),
                  PopupMenuItem(value: 'refunded', child: Text('Refunded')),
                ],
                icon: const Icon(Icons.filter_list, size: 20, color: AppColors.textSecondary),
              ),
              if (_canCreate)
                FilledButton(
                  onPressed: _openForm,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                  child: const Text('+ Payment', style: TextStyle(fontSize: 12.5)),
                ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(_statusFilter == 'all' ? 'No payments yet.' : 'No payments match this filter.',
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: pageSlice(rows, _page).length + (pageCountFor(rows.length) > 1 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= pageSlice(rows, _page).length) {
                      return pagerFor(rows.length, _page, (p) => setState(() => _page = p));
                    }
                    final p = pageSlice(rows, _page)[i];
                    return Container(
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
                                Text('${p['or_number'] ?? ''} · ${_residentName(p)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                const SizedBox(height: 3),
                                Text(
                                    '${titleCase((p['payment_method'] ?? '').toString())} · ${(p['payment_date'] ?? '').toString().split('T').first}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_compact(_amt(p)), style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                              const SizedBox(height: 4),
                              StatusBadge((p['status'] ?? '').toString()),
                              TextButton(
                                onPressed: () => _reviewPayment(p),
                                style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 28),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                child: Text(
                                    _canVerify && p['status'] == 'pending' ? 'Review' : 'View',
                                    style: const TextStyle(fontSize: 11.5)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Desktop payments table for the filtered, sorted, paged rows.
  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return Center(
          child: Text(_statusFilter == 'all' ? 'No payments yet.' : 'No payments match this filter.',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted)));
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: fullWidthTable(
            footer: pagerFor(rows.length, _page, (p) => setState(() => _page = p)),
            
        DataTable(
            showCheckboxColumn: false,
            sortColumnIndex: sortColumn,
            sortAscending: sortAsc,
            columnSpacing: 28,
            headingRowHeight: 40,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 56,
            headingTextStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
            dataTextStyle: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            columns: [
              DataColumn(label: const Text('PAYMENT #'), onSort: onSort),
              DataColumn(label: const Text('RESIDENT'), onSort: onSort),
              DataColumn(label: const Text('AMOUNT'), onSort: onSort),
              DataColumn(label: const Text('METHOD'), onSort: onSort),
              DataColumn(label: const Text('DATE'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
              const DataColumn(label: Text('ACTIONS')),
            ],
            rows: [
              for (final p in pageSlice(sortRows(rows), _page))
                DataRow(cells: [
                  DataCell(Text((p['or_number'] ?? '').toString())),
                  DataCell(Text(_residentName(p))),
                  DataCell(Text(_compact(_amt(p)))),
                  DataCell(Text(titleCase((p['payment_method'] ?? '').toString()))),
                  DataCell(Text((p['payment_date'] ?? '').toString().split('T').first)),
                  DataCell(StatusBadge((p['status'] ?? '').toString())),
                  // Review for pending payments (if allowed to verify), else read-only View.
                  DataCell(TextButton(
                    onPressed: () => _reviewPayment(p),
                    child: Text(_canVerify && p['status'] == 'pending' ? 'Review' : 'View'),
                  )),
                ]),
            ],
          ),
      ),
    );
  }

}
