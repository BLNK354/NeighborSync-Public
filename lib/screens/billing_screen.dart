import 'package:flutter/material.dart';
import '../core/card_filter.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/module_registry.dart';
import '../core/permissions.dart';
import '../core/receipt_pdf.dart';
import '../core/text_utils.dart';
import '../services/crud_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/payment_proof_actions.dart';
import '../widgets/payment_review_dialog.dart';
import '../widgets/responsive_officer_shell.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/dialog_controllers.dart';
import '../core/safe_state.dart';

/// Most bills loaded at once. Keeps the download small; the stat card totals
/// come from the database, so this cap does not affect them.
const int _kBillPageSize = 300;

/// Officer Billing tab: stat cards that also filter the list, plus a capped
/// table with a "View" link to each bill.
///
/// Shown as a tab inside FinanceScreen, so it has no shell of its own.
/// [BillDetailScreen] below is a separate page and does have one.
class AdminBillingScreen extends StatefulWidget {
  const AdminBillingScreen({super.key});

  @override
  State<AdminBillingScreen> createState() => _AdminBillingScreenState();
}

class _AdminBillingScreenState extends State<AdminBillingScreen>
    with SafeSetState<AdminBillingScreen>, TableSortState {
  // 1-based page for the 10-row pager (pagination_footer.dart).
  int _page = 1;

  List<Map<String, dynamic>> _bills = [];

  /// The four stat cards, from `billing_overview()`. They cover every bill the
  /// caller may see, not just the loaded page, so never sum them from `_bills`.
  double _collected = 0;
  double _totalBilled = 0;
  double _outstanding = 0;
  double _overdue = 0;

  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';

  /// Whether this officer may generate bills (bills:create). Read-only roles
  /// such as audit_officer do not get the button.
  bool _canCreate = false;

  @override
  void initState() {
    super.initState();
    // A dashboard card may have sent us here already narrowed (card_filter.dart).
    _statusFilter = CardFilter.take('billing') ?? _statusFilter;
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads one capped page of bills, the permissions, and the card totals.
  ///
  /// `billing_overview()` adds up the totals in the database. It must stay
  /// SECURITY INVOKER: as definer it would skip RLS and show other phases' money.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = SupabaseService.instance.client;

      // Filter on the server: the list is capped, so filtering only the loaded
      // page would hide older matching bills.
      var q = c.from('bills').select(
          '*, resident:user_id(first_name, last_name), lot:lot_id(lot_number)');
      final statuses = _statusesFor(_statusFilter);
      if (statuses != null) q = q.inFilter('status', statuses);

      final results = await Future.wait<dynamic>([
        // Order on the server, or the limit would keep an arbitrary page
        // instead of the newest bills.
        q.order('created_at', ascending: false).limit(_kBillPageSize),
        c.rpc('billing_overview'),
        SupabaseService.instance.getMyPermissions(),
      ]);

      final bills = List<Map<String, dynamic>>.from(results[0] as List);

      final totalRows = results[1] as List;
      final t = totalRows.isEmpty
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(totalRows.first as Map);
      double amount(String key) =>
          num.tryParse(t[key]?.toString() ?? '0')?.toDouble() ?? 0;

      if (!mounted) return;
      setState(() {
        _bills = bills;
        _totalBilled = amount('total_billed');
        _outstanding = amount('outstanding');
        _overdue = amount('overdue');
        _collected = amount('collected');
        _canCreate = canPerform(
            results[2] as Map<String, Set<String>>, 'bills', 'create');
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

  /// What the bill charges: amount + penalty - discount.
  double _net(Map<String, dynamic> b) {
    final amt = num.tryParse(b['amount']?.toString() ?? '0') ?? 0;
    final pen = num.tryParse(b['penalty_amount']?.toString() ?? '0') ?? 0;
    final disc = num.tryParse(b['discount_amount']?.toString() ?? '0') ?? 0;
    return (amt + pen - disc).toDouble();
  }

  /// True when the page is full, so there are probably more bills than shown.
  bool get _truncated => _bills.length >= _kBillPageSize;

  /// Tells the officer the list is capped but the card totals are not.
  /// Shows nothing until the page is full.
  Widget _truncationNote() {
    if (!_truncated) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        'Showing the newest $_kBillPageSize bills. The totals above cover '
        'every bill, not just these — filter by status to narrow the list.',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    );
  }

  /// The bills to draw, narrowed by the status filter. `_load()` already
  /// filters on the server; this covers the moment before a reload arrives.
  List<Map<String, dynamic>> get _visible {
    Iterable<Map<String, dynamic>> rows = _bills;
    final statuses = _statusesFor(_statusFilter);
    if (statuses != null) rows = rows.where((b) => statuses.contains(b['status']));
    return rows.toList();
  }

  /// The bill statuses a filter value stands for. The two card-only values
  /// group several: "outstanding" is every unsettled bill (what the
  /// Outstanding card sums) and "collected" the bills money came in on.
  /// Null = no filter.
  static List<String>? _statusesFor(String f) => switch (f) {
        'all' => null,
        'outstanding' => const ['pending', 'partial', 'overdue'],
        'collected' => const ['paid', 'partial'],
        _ => [f],
      };

  /// Tapping a stat card applies its filter; tapping it again clears it.
  void _tapCard(String v) => _setStatusFilter(_statusFilter == v ? 'all' : v);

  /// Changes the filter and reloads, because the filter is part of the query.
  void _setStatusFilter(String v) {
    if (v == _statusFilter) return;
    setState(() {
      _statusFilter = v;
      _page = 1;
    });
    _load();
  }

  /// Opens the Generate Bill form, then names the new bill in a message.
  /// Clears the filter first, or a new pending bill could fall out of view.
  Future<void> _openForm() async {
    final saved = await showModuleFormDialog(context, billing);
    if (saved != true) return;
    if (_statusesFor(_statusFilter) != null) {
      setState(() {
        _statusFilter = 'all';
        _page = 1;
      });
    }
    await _load();
    if (!mounted) return;
    // _bills is ordered created_at desc, so the bill just written is first.
    final created = _bills.isEmpty ? null : _bills.first;
    final number = (created?['bill_number'] ?? '').toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(number.isEmpty ? 'Bill generated.' : 'Bill $number generated.'),
    ));
  }

  /// Copies the bills currently loaded and filtered to the clipboard as CSV.
  void _exportCsv() {
    final rows = _visible;
    final buffer = StringBuffer('Bill Number,Resident,Description,Amount,Due Date,Status\n');
    for (final b in rows) {
      final resident = b['resident'] as Map<String, dynamic>?;
      final name = resident == null
          ? ''
          : [resident['first_name'], resident['last_name']].where((s) => s != null).join(' ');
      buffer.writeln(
          '${b['bill_number']},$name,"${b['description']}",${_net(b)},${b['due_date']},${b['status']}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    // Says "the newest N" when the page is full, so nobody takes a partial
    // export for the whole ledger.
    final what = _truncated
        ? 'the newest ${rows.length} bills'
        : '${rows.length} bills';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $what as CSV to clipboard.')),
    );
  }

  /// 0 Bill# · 1 Resident · 2 Type · 3 Amount · 4 Due · 5 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> b, int col) {
    switch (col) {
      case 0:
        return text(b['bill_number']);
      case 1:
        return text(_residentName(b));
      case 2:
        return text(b['description']);
      case 3:
        // Sort on the net, which is what the AMOUNT column shows.
        return _net(b);
      case 4:
        return date(b['due_date']);
      case 5:
        return rankedKey(b['status'], kStatusRank);
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
              Text('${_bills.length} bills',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: _setStatusFilter,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'all', child: Text('All statuses')),
                  PopupMenuItem(value: 'pending', child: Text('Pending')),
                  PopupMenuItem(value: 'partial', child: Text('Partial')),
                  PopupMenuItem(value: 'paid', child: Text('Paid')),
                  PopupMenuItem(value: 'overdue', child: Text('Overdue')),
                  PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
                  PopupMenuItem(value: 'waived', child: Text('Waived')),
                ],
                child: OutlinedButton(
                  onPressed: null,
                  child: Text(_statusFilter == 'all' ? 'Filter' : titleCase(_statusFilter)),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: _exportCsv, child: const Text('Export')),
              const SizedBox(width: 10),
              if (_canCreate) FilledButton(onPressed: _openForm, child: const Text('Generate Bill')),
            ],
          ),
          const SizedBox(height: 18),
          responsiveStatCards((w) => [
            DashboardStatCard(icon: Icons.bar_chart, iconBg: const Color(0xFFE3F1E9), label: 'Total Billed', value: _compact(_totalBilled), width: w, hint: 'Show all', onTap: () => _setStatusFilter('all')),
            DashboardStatCard(icon: Icons.account_balance_wallet_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Collected', value: _compact(_collected), width: w, selected: _statusFilter == 'collected', onTap: () => _tapCard('collected')),
            DashboardStatCard(icon: Icons.pending_actions_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Outstanding', value: _compact(_outstanding), width: w, selected: _statusFilter == 'outstanding', onTap: () => _tapCard('outstanding')),
            DashboardStatCard(icon: Icons.warning_amber_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Overdue', value: _compact(_overdue), width: w, selected: _statusFilter == 'overdue', onTap: () => _tapCard('overdue')),
          ]),
          _truncationNote(),
          const SizedBox(height: 20),
          Expanded(child: _buildTable()),
        ],
      ),
    );
  }

  /// Phone layout: bill cards instead of a table. No Export button, and the
  /// filter is an icon so the header row fits.
  Widget _mobileBody() {
    final rows = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: responsiveStatCards((w) => [
            DashboardStatCard(icon: Icons.bar_chart, iconBg: const Color(0xFFE3F1E9), label: 'Total Billed', value: _compact(_totalBilled), width: w, hint: 'Show all', onTap: () => _setStatusFilter('all')),
            DashboardStatCard(icon: Icons.account_balance_wallet_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Collected', value: _compact(_collected), width: w, selected: _statusFilter == 'collected', onTap: () => _tapCard('collected')),
            DashboardStatCard(icon: Icons.pending_actions_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Outstanding', value: _compact(_outstanding), width: w, selected: _statusFilter == 'outstanding', onTap: () => _tapCard('outstanding')),
            DashboardStatCard(icon: Icons.warning_amber_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Overdue', value: _compact(_overdue), width: w, selected: _statusFilter == 'overdue', onTap: () => _tapCard('overdue')),
          ]),
        ),
        _truncationNote(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('${_bills.length} bills',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: _setStatusFilter,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'all', child: Text('All statuses')),
                  PopupMenuItem(value: 'pending', child: Text('Pending')),
                  PopupMenuItem(value: 'partial', child: Text('Partial')),
                  PopupMenuItem(value: 'paid', child: Text('Paid')),
                  PopupMenuItem(value: 'overdue', child: Text('Overdue')),
                  PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
                  PopupMenuItem(value: 'waived', child: Text('Waived')),
                ],
                icon: const Icon(Icons.filter_list, size: 20, color: AppColors.textSecondary),
              ),
              if (_canCreate)
                FilledButton(
                  onPressed: _openForm,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                  child: const Text('+ Bill', style: TextStyle(fontSize: 12.5)),
                ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(_statusFilter == 'all' ? 'No bills yet.' : 'No bills match this filter.',
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: pageSlice(rows, _page).length + (pageCountFor(rows.length) > 1 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= pageSlice(rows, _page).length) {
                      return pagerFor(rows.length, _page, (p) => setState(() => _page = p));
                    }
                    final b = pageSlice(rows, _page)[i];
                    return InkWell(
                      onTap: () => context.push('/admin/billing/${b['id']}'),
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
                                  Text('${b['bill_number'] ?? ''} · ${_residentName(b)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  const SizedBox(height: 3),
                                  Text('${(b['description'] ?? '').toString()} · due ${(b['due_date'] ?? '').toString()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_compact(_net(b)), style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                                const SizedBox(height: 4),
                                StatusBadge((b['status'] ?? '').toString()),
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
    );
  }

  /// Short peso amount: ₱950, ₱1.5k, ₱2.1M.
  static String _compact(double n) {
    final abs = n.abs();
    if (abs >= 1000000) return '₱${(n / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '₱${(n / 1000).toStringAsFixed(1)}k';
    return '₱${n.toStringAsFixed(0)}';
  }

  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return Center(
          child: Text(_statusFilter == 'all' ? 'No bills yet.' : 'No bills match this filter.',
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
              DataColumn(label: const Text('BILL #'), onSort: onSort),
              DataColumn(label: const Text('RESIDENT'), onSort: onSort),
              DataColumn(label: const Text('TYPE'), onSort: onSort),
              DataColumn(label: const Text('AMOUNT'), onSort: onSort),
              DataColumn(label: const Text('DUE'), onSort: onSort),
              DataColumn(label: const Text('STATUS'), onSort: onSort),
              const DataColumn(label: Text('ACTIONS')),
            ],
            rows: [
              for (final b in pageSlice(sortRows(rows), _page))
                DataRow(cells: [
                  DataCell(Text((b['bill_number'] ?? '').toString())),
                  DataCell(Text(_residentName(b))),
                  DataCell(Text((b['description'] ?? '').toString())),
                  DataCell(Text(_compact(_net(b)))),
                  DataCell(Text((b['due_date'] ?? '').toString())),
                  DataCell(StatusBadge((b['status'] ?? '').toString())),
                  DataCell(
                    TextButton(
                      onPressed: () => context.push('/admin/billing/${b['id']}'),
                      child: const Text('View'),
                    ),
                  ),
                ]),
            ],
          ),
      ),
    );
  }

  String _residentName(Map<String, dynamic> b) {
    final r = b['resident'] as Map<String, dynamic>?;
    if (r == null) return '—';
    return [r['first_name'], r['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
  }
}

/// One bill's page: summary (amount, penalty, discount), amount due, proofs
/// of payment and payment history, with the actions the officer may take.
class BillDetailScreen extends StatefulWidget {
  final int billId;
  const BillDetailScreen({super.key, required this.billId});

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> with SafeSetState<BillDetailScreen> {
  Map<String, dynamic>? _bill;
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  String? _error;
  // May review pending payments (payments:approve). A payment recorded here
  // starts 'pending' and only counts toward the bill once verified.
  bool _canVerify = false;

  /// Recording a payment against this bill needs payments:create.
  bool _canRecordPayment = false;
  bool _canReviewProof = false;

  /// Cancelling, waiving and reopening write `bills.status`, which needs
  /// bills:update.
  bool _canManageBill = false;
  List<Map<String, dynamic>> _submissions = [];

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
      final results = await Future.wait<dynamic>([
        c
            .from('bills')
            .select('*, resident:user_id(first_name, last_name), lot:lot_id(lot_number)')
            .eq('id', widget.billId)
            .single(),
        c.from('payments').select('*').eq('bill_id', widget.billId).order('payment_date', ascending: false),
        SupabaseService.instance.getMyPermissions(),
        // Proof of payment the resident uploaded for this bill.
        c
            .from('payment_submissions')
            .select('*')
            .eq('bill_id', widget.billId)
            .order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _bill = results[0] as Map<String, dynamic>;
        _payments = List<Map<String, dynamic>>.from(results[1] as List);
        _canVerify = canPerform(results[2] as Map<String, Set<String>>, 'payments', 'approve');
        _canRecordPayment =
            canPerform(results[2] as Map<String, Set<String>>, 'payments', 'create');
        // Must match what approve_payment_submission() checks on the server
        // (payments:update), or the buttons would show and then be refused.
        _canReviewProof =
            canPerform(results[2] as Map<String, Set<String>>, 'payments', 'update');
        _canManageBill =
            canPerform(results[2] as Map<String, Set<String>>, 'bills', 'update');
        _submissions = List<Map<String, dynamic>>.from(results[3] as List);
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

  /// The resident's uploaded proofs for this bill, shown so the officer reviews
  /// them instead of recording the same payment by hand. Empty if there are none.
  Widget _proofSection(Map<String, dynamic> b) {
    if (_submissions.isEmpty) return const SizedBox.shrink();
    final residentName = _residentName(b);
    final billNumber = (b['bill_number'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text('Proof of Payment',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        for (final s in _submissions) _proofCard(s, residentName, billNumber),
      ],
    );
  }

  /// One uploaded proof: amount, method, reference, View receipt, and
  /// Verify / Reject while it is pending.
  Widget _proofCard(Map<String, dynamic> s, String residentName, String billNumber) {
    final status = (s['status'] ?? 'pending').toString();
    final pending = status == 'pending';
    final amount = (num.tryParse(s['amount']?.toString() ?? '0') ?? 0).toDouble();
    final method = (s['payment_method'] ?? '').toString();
    final ref = (s['reference_number'] ?? '').toString();
    final note = (s['review_note'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Tinted while pending, because it is waiting on the officer.
        color: pending ? AppColors.badgeAmberBg.withValues(alpha: 0.35) : null,
        border: Border.all(color: pending ? AppColors.badgeAmberText : AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.image_outlined, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '₱${amount.toStringAsFixed(2)}'
                '${method.isEmpty ? '' : ' · ${method.toUpperCase()}'}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            StatusBadge(status),
          ]),
          if (ref.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Ref $ref',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ],
          if (!pending && note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(note, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(
              onPressed: () =>
                  viewPaymentReceipt(context, s['receipt_path'] as String?),
              icon: const Icon(Icons.visibility_outlined, size: 15),
              label: const Text('View receipt'),
            ),
            if (pending && _canReviewProof) ...[
              FilledButton(
                onPressed: () async {
                  final done = await approvePaymentSubmission(
                    context, s,
                    residentName: residentName,
                    billNumber: billNumber,
                  );
                  if (done) _load();
                },
                child: const Text('Verify'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFA82F2F)),
                onPressed: () async {
                  final done = await rejectPaymentSubmission(context, s);
                  if (done) _load();
                },
                child: const Text('Reject'),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  String _residentName(Map<String, dynamic> b) {
    final r = b['resident'] as Map<String, dynamic>?;
    if (r == null) return '';
    return [r['first_name'], r['last_name']].where((s) => s != null).join(' ').trim();
  }

  /// Opens the shared review dialog (widgets/payment_review_dialog.dart) and
  /// reloads if the payment changed.
  Future<void> _reviewPayment(Map<String, dynamic> p) async {
    final changed = await reviewPayment(context, p,
        residentName: _bill == null ? null : _residentName(_bill!));
    if (changed) _load();
  }

  /// The bill's amount + penalty - discount.
  double get _totalDue {
    final b = _bill;
    if (b == null) return 0;
    final amt = num.tryParse(b['amount']?.toString() ?? '0') ?? 0;
    final pen = num.tryParse(b['penalty_amount']?.toString() ?? '0') ?? 0;
    final disc = num.tryParse(b['discount_amount']?.toString() ?? '0') ?? 0;
    return (amt + pen - disc).toDouble();
  }

  /// Only verified payments count toward the bill.
  double get _paidSoFar => _payments.where((p) => p['status'] == 'verified').fold<double>(
      0, (s, p) => s + (num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0));

  double get _amountDue => (_totalDue - _paidSoFar).clamp(0, double.infinity);

  /// Opens the Record Payment dialog, pre-filled with the amount still due.
  /// The payment is saved as 'pending' until someone verifies it.
  Future<void> _recordPayment() async {
    final b = _bill;
    if (b == null) return;
    final orCtrl = TextEditingController();
    final amountCtrl = TextEditingController(text: _amountDue.toStringAsFixed(2));
    final refCtrl = TextEditingController();
    String method = 'cash';
    bool saving = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            final amount = num.tryParse(amountCtrl.text);
            if (!RegExp(r'^\d{1,6}$').hasMatch(orCtrl.text.trim()) ||
                amount == null ||
                amount <= 0) {
              setDialogState(() => error =
                  'Enter the OR number (up to 6 digits) and a valid amount.');
              return;
            }
            setDialogState(() {
              saving = true;
              error = null;
            });
            try {
              await CrudService.instance.create(payments, {
                'or_number': orCtrl.text.trim(),
                'bill_id': b['id'],
                'user_id': b['user_id'],
                'amount_paid': amount,
                'payment_method': method,
                'payment_date': DateTime.now().toUtc().toIso8601String(),
                'reference_number': refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
                'status': 'pending',
              });
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (mounted) _load();
            } catch (e) {
              setDialogState(() {
                saving = false;
                error = 'Could not record payment. ${friendlyError(e)}';
              });
            }
          }

          return AlertDialog(
            title: const Text('Record Payment'),
            content: SizedBox(
              width: dialogContentWidth(context, 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: orCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: orNumberInputFormatters,
                    decoration: const InputDecoration(
                        labelText: 'OR Number', hintText: 'e.g. 004512'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: moneyInputFormatters,
                    decoration: const InputDecoration(labelText: 'Amount Paid'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(labelText: 'Payment Method'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                      DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                      DropdownMenuItem(value: 'maya', child: Text('Maya')),
                      DropdownMenuItem(value: 'check', child: Text('Check')),
                      DropdownMenuItem(value: 'online', child: Text('Online')),
                    ],
                    onChanged: (v) => setDialogState(() => method = v ?? 'cash'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                      controller: refCtrl,
                      maxLength: kReferenceMaxLength,
                      decoration: const InputDecoration(labelText: 'Reference # (optional)')),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: saving ? null : submit,
                  child: Text(saving ? 'Saving...' : 'Record Payment')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _bill;
    // One layout for all widths: the cards stack below 900px.
    return ResponsiveOfficerShell(
      title: b == null ? 'Bill Detail' : 'Bill #${b['bill_number']}',
      // Billing/Payments/Budget share one "Finance" nav item.
      activeItem: 'Finance',
      activeTab: 'Finance',
      desktopChild: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back link; goes to Finance if there is no page to return to.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextButton.icon(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/admin/finance');
                }
              },
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to Billing'),
            ),
          ),
          Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || b == null
              ? Center(child: Text(_error ?? 'Bill not found.', style: const TextStyle(color: Colors.redAccent)))
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 900;
                      final summary = _summaryCard(b);
                      final status = _statusCard(b);
                      if (stacked) {
                        return SingleChildScrollView(
                          child: Column(children: [summary, const SizedBox(height: 20), status]),
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: summary),
                          const SizedBox(width: 20),
                          Expanded(child: status),
                        ],
                      );
                    },
                  ),
                )),
        ],
      ),
    );
  }

  Widget _summaryCard(Map<String, dynamic> b) {
    final resident = b['resident'] as Map<String, dynamic>?;
    final lot = b['lot'] as Map<String, dynamic>?;
    final name = resident == null
        ? 'Unknown'
        : [resident['first_name'], resident['last_name']].where((s) => s != null).join(' ');
    final lotLabel = lot == null ? '' : ' - Lot #${lot['lot_number']}';
    final amt = num.tryParse(b['amount']?.toString() ?? '0') ?? 0;
    final pen = num.tryParse(b['penalty_amount']?.toString() ?? '0') ?? 0;
    final disc = num.tryParse(b['discount_amount']?.toString() ?? '0') ?? 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bill Summary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Billed To: $name$lotLabel',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          const SizedBox(height: 20),
          _lineRow('DESCRIPTION', 'DUE DATE', 'AMOUNT', header: true),
          const Divider(height: 20),
          _lineRow((b['description'] ?? '').toString(), (b['due_date'] ?? '').toString(),
              _AdminBillingScreenStateCompactAccess.compact(amt.toDouble())),
          if (pen > 0) ...[
            const Divider(height: 20),
            _lineRow('Penalty', '', _AdminBillingScreenStateCompactAccess.compact(pen.toDouble())),
          ],
          if (disc > 0) ...[
            const Divider(height: 20),
            _lineRow('Discount', '', '-${_AdminBillingScreenStateCompactAccess.compact(disc.toDouble())}'),
          ],
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Due',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text(_AdminBillingScreenStateCompactAccess.compact(_totalDue),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.sidebarActiveText)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lineRow(String a, String b, String c, {bool header = false}) {
    final style = header
        ? const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)
        : const TextStyle(fontSize: 13, color: AppColors.textPrimary);
    return Row(
      children: [
        Expanded(flex: 2, child: Text(a, style: style)),
        Expanded(child: Text(b, style: style)),
        SizedBox(width: 100, child: Text(c, textAlign: TextAlign.right, style: style)),
      ],
    );
  }

  /// Only a verified payment makes this a receipt; unchecked proof must not.
  bool get _hasVerifiedPayment =>
      _payments.any((p) => (p['status'] ?? '') == 'verified');

  /// Opens this bill's PDF slip, or shows a message if it cannot be built.
  Future<void> _downloadSlip(Map<String, dynamic> b) async {
    try {
      await ReceiptPdf.open(bill: b, payments: _payments);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not build the document. ${friendlyError(e)}')),
        );
      }
    }
  }

  /// Sets a bill by hand to cancelled (should never have been issued), waived
  /// (real charge, forgiven) or back to pending (reopen). Asks for a reason
  /// and adds it to `bills.notes`.
  ///
  /// Only cancelled and waived stay put: the database works out every other
  /// status itself. A reopened bill goes back to that automatic handling.
  Future<void> _setBillStatus(
    Map<String, dynamic> b, {
    required String status,
    required String verb,
    required String blurb,
  }) async {
    final noteCtrl = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$verb ${b['bill_number'] ?? 'this bill'}?'),
          content: SizedBox(
            width: dialogContentWidth(context, 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(blurb,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.4)),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  maxLength: kMaxTextLength,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Reason', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(verb),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final reason = noteCtrl.text.trim();
      if (reason.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Please give a reason — this is a financial record.')));
        }
        return;
      }

      try {
        final stamp = DateTime.now().toIso8601String().split('T').first;
        final existing = (b['notes'] ?? '').toString();
        await SupabaseService.instance.client.from('bills').update({
          'status': status,
          'notes':
              '${existing.isEmpty ? '' : '$existing\n'}$verb $stamp: $reason',
        }).eq('id', b['id']);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Bill ${status.toLowerCase()}.')));
        }
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Could not update the bill. ${friendlyError(e)}')));
        }
      }
    } finally {
      disposeAfterDialogCloses([noteCtrl]);
    }
  }

  /// Waive and Cancel buttons, or Reopen once the bill is cancelled or waived.
  Widget _billActions(Map<String, dynamic> b) {
    final status = (b['status'] ?? '').toString();
    final settled = status == 'cancelled' || status == 'waived';

    // Never offered on a paid bill: it could remove a real payment from the
    // collected total.
    if (!_canManageBill || status == 'paid') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: settled
          ? OutlinedButton.icon(
              onPressed: () => _setBillStatus(b,
                  status: 'pending',
                  verb: 'Reopen',
                  blurb:
                      'This puts the bill back into the ledger as money owed. '
                      'If its due date has already passed, tonight\'s sweep '
                      'will mark it overdue.'),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Reopen bill'),
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _setBillStatus(b,
                        status: 'waived',
                        verb: 'Waive',
                        blurb:
                            'The charge was real and the association is '
                            'forgiving it. The bill stops counting as money '
                            'owed and no longer appears in the arrears.'),
                    child: const Text('Waive'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFA82F2F)),
                    onPressed: () => _setBillStatus(b,
                        status: 'cancelled',
                        verb: 'Cancel',
                        blurb:
                            'The bill should never have been issued — billed '
                            'in error, or a duplicate. Use Waive instead if '
                            'the charge was correct and is being forgiven.'),
                    child: const Text('Cancel bill'),
                  ),
                ),
              ],
            ),
    );
  }

  /// Payment Status card: amount due, record and download buttons, bill actions,
  /// uploaded proofs and payment history.
  Widget _statusCard(Map<String, dynamic> b) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payment Status',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(color: AppColors.badgeGreenBg, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                const Text('Amount Due', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 4),
                Text(_AdminBillingScreenStateCompactAccess.compact(_amountDue),
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.sidebarActiveText)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_canRecordPayment)
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _recordPayment, child: const Text('Record Payment')),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _downloadSlip(b),
              icon: Icon(_hasVerifiedPayment ? Icons.receipt_long : Icons.description_outlined,
                  size: 16),
              // A receipt acknowledges money received; with no verified payment
              // this is a statement.
              label: Text(_hasVerifiedPayment ? 'Download Receipt' : 'Download Statement'),
            ),
          ),
          const SizedBox(height: 16),
          StatusBadge((b['status'] ?? '').toString()),
          _billActions(b),
          _proofSection(b),
          const SizedBox(height: 20),
          const Text('Payment History',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          const SizedBox(height: 10),
          if (_payments.isEmpty)
            const Text('No payments recorded yet.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))
          else
            for (final p in _payments)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${p['or_number'] ?? ''} - ${_AdminBillingScreenStateCompactAccess.compact(num.tryParse(p['amount_paid']?.toString() ?? '0')?.toDouble() ?? 0)}',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          Text('${p['payment_method'] ?? ''} - ${(p['payment_date'] ?? '').toString().split('T').first}',
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        StatusBadge((p['status'] ?? '').toString()),
                        if (_canVerify && p['status'] == 'pending')
                          TextButton(
                            onPressed: () => _reviewPayment(p),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 28),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: const Text('Review', style: TextStyle(fontSize: 11.5)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Short peso formatter for the Bill Detail page.
class _AdminBillingScreenStateCompactAccess {
  static String compact(double n) {
    final abs = n.abs();
    if (abs >= 1000000) return '₱${(n / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '₱${(n / 1000).toStringAsFixed(1)}k';
    return '₱${n.toStringAsFixed(0)}';
  }
}
