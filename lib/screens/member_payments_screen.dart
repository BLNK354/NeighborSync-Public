import '../core/app_locale.dart' show tr;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/pagination_footer.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../core/form_helpers.dart';
import '../core/image_compress.dart';
import 'package:go_router/go_router.dart';
import '../core/receipt_pdf.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../widgets/payment_channels_view.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/tour_anchors.dart';
import '../core/safe_state.dart';
import '../core/local_time.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "My Payments" page: My Bills and Payment History tabs, showing only the
/// current resident's own rows.
/// Residents cannot record payments. They see where to send the money, pay
/// outside the app, then upload a receipt with Send Proof for the treasurer.
class MemberPaymentsScreen extends StatefulWidget {
  const MemberPaymentsScreen({super.key});

  @override
  State<MemberPaymentsScreen> createState() => _MemberPaymentsScreenState();
}

class _MemberPaymentsScreenState extends State<MemberPaymentsScreen> with SafeSetState<MemberPaymentsScreen>, SingleTickerProviderStateMixin {
  // Current page of each tab, starting at 1. Keep one per tab: a shared
  // counter can leave the shorter tab showing an empty page.
  int _billsPage = 1;
  int _historyPage = 1;

  /// Set by tapping a stat card: 'outstanding' / 'next' narrow My Bills,
  /// 'year' narrows Payment History. Tap the same card again to clear.
  String _cardFilter = 'all';

  late final TabController _tab = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _bills = [];
  List<Map<String, dynamic>> _payments = [];

  /// Proof-of-payment uploads awaiting (or finished) treasurer review.
  /// Residents cannot write to `payments` -- they submit here and the
  /// treasurer's approval is what creates the real payment.
  List<Map<String, dynamic>> _submissions = [];
  bool _uploading = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// Loads this resident's bills, payments and proof submissions.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final myId = await SupabaseService.instance.getMyUserId();
      final c = SupabaseService.instance.client;
      final results = await Future.wait<dynamic>([
        // Resident and lot are for the downloadable statement. Keep the named
        // FK columns: the embed is ambiguous without them and the query fails.
        c
            .from('bills')
            .select('*, resident:user_id(first_name, last_name), lot:lot_id(lot_number)')
            .eq('user_id', myId as Object)
            .order('due_date', ascending: false)
            .limit(100),
        c.from('payments').select('*').eq('user_id', myId as Object).order('payment_date', ascending: false).limit(100),
        c.from('payment_submissions').select('*').eq('user_id', myId as Object).order('created_at', ascending: false).limit(100),
      ]);
      if (!mounted) return;
      setState(() {
        _bills = List<Map<String, dynamic>>.from(results[0] as List);
        _payments = List<Map<String, dynamic>>.from(results[1] as List);
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

  /// What a bill comes to: amount plus penalty minus discount.
  num _net(Map<String, dynamic> b) {
    final amt = num.tryParse(b['amount']?.toString() ?? '0') ?? 0;
    final pen = num.tryParse(b['penalty_amount']?.toString() ?? '0') ?? 0;
    final disc = num.tryParse(b['discount_amount']?.toString() ?? '0') ?? 0;
    return amt + pen - disc;
  }

  /// Total of all bills not yet paid, cancelled or waived.
  num get _totalOutstanding =>
      _bills.where((b) => b['status'] != 'paid' && b['status'] != 'cancelled' && b['status'] != 'waived').fold<num>(0, (s, b) => s + _net(b));

  /// Total paid this calendar year, leaving out rejected and refunded payments.
  num get _paidThisYear {
    final year = DateTime.now().year;
    return _payments.where((p) {
      // Use local time: in UTC, a payment early on 1 January counts as last year.
      final dt = localTime(p['payment_date']);
      return dt != null && dt.year == year && p['status'] != 'rejected' && p['status'] != 'refunded';
    }).fold<num>(0, (s, p) => s + (num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0));
  }

  /// The unpaid bill with the earliest due date, or null if there is none.
  Map<String, dynamic>? get _nextDue {
    final unpaid = _bills.where((b) => b['status'] == 'pending' || b['status'] == 'partial' || b['status'] == 'overdue').toList()
      ..sort((a, b) => (a['due_date'] ?? '').toString().compareTo((b['due_date'] ?? '').toString()));
    return unpaid.isEmpty ? null : unpaid.first;
  }

  bool _isUnpaid(Map<String, dynamic> b) =>
      const {'pending', 'partial', 'overdue'}.contains(b['status']);

  /// Bills to list, after any stat-card filter.
  List<Map<String, dynamic>> get _shownBills {
    switch (_cardFilter) {
      case 'outstanding':
        return _bills.where(_isUnpaid).toList();
      case 'next':
        final n = _nextDue;
        return n == null ? const [] : [n];
      default:
        return _bills;
    }
  }

  /// Payments to list, after any stat-card filter.
  List<Map<String, dynamic>> get _shownPayments {
    if (_cardFilter != 'year') return _payments;
    final year = DateTime.now().year;
    return _payments.where((p) {
      final dt = localTime(p['payment_date']);
      return dt != null && dt.year == year;
    }).toList();
  }

  /// A card narrows the list below it and switches to the tab it is about.
  void _tapCard(String v) {
    final on = _cardFilter != v;
    setState(() {
      _cardFilter = on ? v : 'all';
      _billsPage = 1;
      _historyPage = 1;
    });
    if (on) _tab.animateTo(v == 'year' ? 1 : 0);
  }

  String _dateLabel(String? iso) {
    // Use the local day, or an early-morning payment shows the day before.
    final t = localTime(iso);
    if (t == null) return '—';
    return '${_months[t.month - 1]} ${t.day.toString().padLeft(2, '0')}';
  }

  /// Opens the screen showing the association's GCash, Maya and bank accounts
  /// and their QR codes. The resident pays, then comes back to send the receipt.
  void _payNow([Map<String, dynamic>? bill]) {
    context.push('/me/billing/pay', extra: bill);
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'My Payments',
      activeItem: 'My Payments',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(_gutter(context), _narrow(context) ? 16 : 30, _gutter(context), 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(builder: (context, constraints) {
                            final gap = _narrow(context) ? 8.0 : 16.0;
                            final cardWidth = ((constraints.maxWidth - 2 * gap) / 3).floorToDouble();
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                _statCard('Outstanding', '₱${_totalOutstanding.toStringAsFixed(0)}', cardWidth, 'outstanding', Icons.receipt_long_outlined, ResidentColors.iconAmberBg),
                                _statCard('Paid this year', '₱${_paidThisYear.toStringAsFixed(0)}', cardWidth, 'year', Icons.check_circle_outline, ResidentColors.iconGreenBg),
                                _statCard('Next due', _nextDue == null ? '—' : _dateLabel(_nextDue!['due_date']?.toString()), cardWidth, 'next', Icons.event_outlined, ResidentColors.iconBlueBg),
                              ],
                            );
                          }),
                          const SizedBox(height: 20),
                          TabBar(
                            controller: _tab,
                            isScrollable: true,
                            labelColor: ResidentColors.sidebarActiveText,
                            unselectedLabelColor: ResidentColors.textSecondary,
                            indicatorColor: ResidentColors.sidebarActiveText,
                            tabs: [Tab(text: tr('My Bills')), Tab(text: tr('Payment History'))],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        children: [
                          _billsList(),
                          _paymentHistoryList(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  /// True below 600px, where the page uses narrower gutters and smaller card
  /// text so three cards fit across a phone without wrapping.
  bool _narrow(BuildContext context) => MediaQuery.sizeOf(context).width < 600;
  double _gutter(BuildContext context) => _narrow(context) ? 16 : 32;

  /// Summary card in the resident dashboard's style; tapping it filters the
  /// list below. Keep the shadow on the outer box: inside a white Material it
  /// paints a grey haze over the card.
  Widget _statCard(String label, String value, double width, String filter,
      IconData icon, Color iconBg) {
    final narrow = _narrow(context);
    final selected = _cardFilter == filter;
    final accent = ResidentColors.sidebarActiveText;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ResidentColors.cardShadow,
        border: Border.all(
            color: selected ? accent : Colors.transparent, width: 1.5),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _tapCard(filter),
          child: Padding(
            padding: EdgeInsets.all(narrow ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: narrow ? 32 : 44,
                  height: narrow ? 32 : 44,
                  decoration: BoxDecoration(
                      color: iconBg, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Icon(icon,
                      size: narrow ? 16 : 20, color: ResidentColors.textPrimary),
                ),
                SizedBox(height: narrow ? 8 : 14),
                Text(tr(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: narrow ? 11 : 12,
                        color: ResidentColors.textSecondary)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(
                          fontSize: narrow ? 17 : 24,
                          fontWeight: FontWeight.w600,
                          color: ResidentColors.textPrimary)),
                ),
                const SizedBox(height: 4),
                Text(tr(selected ? (narrow ? 'Tap to clear' : 'Showing · tap to clear') : 'View →'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: accent)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Latest submission for a bill, if any. Drives whether the row offers
  /// "Send Proof", shows "Awaiting review", or reports a rejection.
  Map<String, dynamic>? _submissionFor(Object? billId) {
    final matches = _submissions.where((s) => s['bill_id'] == billId);
    return matches.isEmpty ? null : matches.first;
  }

  /// Uploads a receipt for a bill and records it in `payment_submissions` for
  /// the treasurer to review. The file goes to `receipts/<user_id>/…` in the
  /// documents bucket. Never writes to `payments`; residents have no permission.
  Future<void> _sendProof(Map<String, dynamic> bill) async {
    final existing = _submissionFor(bill['id']);
    if (existing != null && existing['status'] == 'pending') {
      _snack('You already sent proof for this bill. The treasurer is reviewing it.');
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) _snack('Could not read that file — try again.', error: true);
      return;
    }
    // Refuse files over 8 MB.
    if (bytes.length > 8 * 1024 * 1024) {
      if (mounted) _snack('That file is over 8 MB. Please upload a smaller photo.', error: true);
      return;
    }
    if (!mounted) return;

    final amountCtrl = TextEditingController(text: _net(bill).toStringAsFixed(2));
    final refCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var method = 'gcash';

    // The account the money went to, so the treasurer knows where to check it.
    // If this load fails the picker is hidden and the proof can still be sent.
    int? channelId;
    var channels = <Map<String, dynamic>>[];
    try {
      final rows = await SupabaseService.instance.client
          .from('payment_channels')
          .select('id, channel_type, label, account_name')
          .eq('is_active', true)
          .order('label');
      channels = List<Map<String, dynamic>>.from(rows);
    } catch (_) {}
    if (!mounted) return;

    List<Map<String, dynamic>> forMethod(String m) {
      final t = m == 'bank_transfer' ? 'bank' : m;
      return channels.where((c) => c['channel_type'] == t).toList();
    }

    String? amountError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Send proof of payment'),
          content: SizedBox(
            width: dialogContentWidth(context, 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${bill['description'] ?? 'Bill'} · #${bill['bill_number'] ?? bill['id']}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Amount paid', prefixText: '₱ ', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(
                        labelText: 'Paid via', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                      DropdownMenuItem(value: 'maya', child: Text('Maya')),
                      DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'check', child: Text('Check')),
                    ],
                    onChanged: (v) => setLocal(() {
                      method = v ?? method;
                      // Clear the account: it belongs to the previous method.
                      channelId = null;
                    }),
                  ),
                  if (forMethod(method).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: channelId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Which account you sent it to',
                          border: OutlineInputBorder()),
                      items: [
                        for (final c in forMethod(method))
                          DropdownMenuItem(
                            value: c['id'] as int,
                            child: Text(
                              [c['label'], c['account_name']]
                                  .where((s) => (s ?? '').toString().isNotEmpty)
                                  .join(' · '),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => channelId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    maxLength: kReferenceMaxLength,
                    decoration: const InputDecoration(
                        labelText: 'Reference number (optional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    maxLength: kMaxTextLength,
                    decoration: const InputDecoration(
                        labelText: 'Note for the treasurer (optional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The treasurer will check this against the association records. '
                    'Your bill stays unpaid until they confirm it.',
                    style: TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary, height: 1.35),
                  ),
                  if (amountError != null) ...[
                    const SizedBox(height: 10),
                    Text(amountError!,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFA82F2F))),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            // Check the amount before closing, or an error loses the picked receipt.
            FilledButton(
                onPressed: () {
                  final a = num.tryParse(amountCtrl.text.trim());
                  if (a == null || a <= 0) {
                    setLocal(() => amountError = 'Enter a valid amount.');
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Send')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final amount = num.tryParse(amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      if (mounted) _snack('Enter a valid amount.', error: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      final myId = await SupabaseService.instance.getMyUserId();
      if (myId == null) throw Exception('Could not resolve your account.');
      final client = SupabaseService.instance.client;
      // Shrink the upload, but keep a large size and high quality: the
      // treasurer has to read figures off the receipt.
      final shrunk = compressImageBytes(bytes, file.name,
          maxEdge: kMaxSurveyPlanEdge, quality: 88);
      final dot = shrunk.filename.lastIndexOf('.');
      final ext = dot < 0
          ? (file.extension ?? 'jpg').toLowerCase()
          : shrunk.filename.substring(dot + 1).toLowerCase();
      final path =
          'receipts/$myId/bill${bill['id']}-${DateTime.now().millisecondsSinceEpoch}.$ext';

      await client.storage.from('documents').uploadBinary(
            path,
            shrunk.bytes,
            fileOptions: FileOptions(
                upsert: true,
                contentType: ext == 'pdf' ? 'application/pdf' : 'image/$ext'),
          );

      await client.from('payment_submissions').insert({
        'bill_id': bill['id'],
        'user_id': myId,
        'amount': amount,
        'payment_method': method,
        'channel_id': channelId,
        'reference_number': refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
        'paid_on': DateTime.now().toIso8601String().split('T').first,
        'receipt_path': path,
        'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      });

      // Also file a copy in the resident's My Files, under "Payment Proof".
      // Keep is_personal true: without it other residents can read the row.
      // If this insert fails the proof is already sent, so show no error.
      try {
        await client.from('documents').insert({
          'name': 'Payment proof — ${bill['bill_number'] ?? 'bill ${bill['id']}'}',
          'original_name': file.name,
          'mime_type': ext == 'pdf' ? 'application/pdf' : 'image/$ext',
          'size_bytes': bytes.length,
          'storage_path': path,
          'category': 'Payment Proof',
          'module': 'payments',
          'related_id': bill['id'],
          'uploaded_by': myId,
          'is_personal': true,
        });
      } catch (_) {
        // The treasurer already has the proof; this copy is only a convenience.
      }

      if (!mounted) return;
      setState(() => _uploading = false);
      _snack('Proof sent. The treasurer will review it shortly.');
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _snack('Could not send proof. ${friendlyError(e)}', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFA82F2F) : null,
    ));
  }

  /// What the resident can do with an unpaid bill, given any proof already sent.
  /// A pending submission replaces the upload button: the database allows only
  /// one pending submission per bill, so a second would fail with an error.
  Widget _billAction(Map<String, dynamic> bill) {
    final sub = _submissionFor(bill['id']);
    final status = (sub?['status'] ?? '').toString();

    if (status == 'pending') {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_outlined, size: 14, color: Color(0xFF8A6300)),
            SizedBox(width: 5),
            Text('Awaiting review',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF8A6300))),
          ],
        ),
      );
    }

    if (status == 'rejected') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: (sub?['review_note'] ?? 'The treasurer could not verify this receipt.')
                .toString(),
            child: const Icon(Icons.error_outline, size: 16, color: Color(0xFFA82F2F)),
          ),
          _howToPayButton(bill),
          TextButton(
            onPressed: _uploading ? null : () => _sendProof(bill),
            child: const Text('Send again'),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // How to pay comes first: a resident needs the QR before sending a receipt.
        _howToPayButton(bill),
        TourAnchor(
          id: TourAnchorId.sendProof,
          child: TextButton(
            onPressed: _uploading ? null : () => _sendProof(bill),
            child: const Text('Send Proof'),
          ),
        ),
      ],
    );
  }

  /// QR icon that opens the how-to-pay screen, with a tooltip for the words.
  /// An icon because a second text label beside "Send Proof" overflows on a phone.
  Widget _howToPayButton(Map<String, dynamic> bill) {
    return TourAnchor(
      id: TourAnchorId.payQr,
      child: _howToPayIcon(bill),
    );
  }

  Widget _howToPayIcon(Map<String, dynamic> bill) {
    return IconButton(
      onPressed: () => _payNow(bill),
      icon: const Icon(Icons.qr_code_2_outlined, size: 18),
      tooltip: 'How to pay — GCash, Maya or bank',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      color: AppColors.sidebarActiveText,
    );
  }

  /// This bill's own payment rows, newest first, for ReceiptPdf.
  List<Map<String, dynamic>> _paymentsFor(Object? billId) =>
      _payments.where((p) => p['bill_id'] == billId).toList();

  /// True once a payment is verified, which turns the slip into a receipt.
  /// A resident's proof still under review must not count.
  bool _hasVerifiedPayment(Object? billId) =>
      _paymentsFor(billId).any((p) => (p['status'] ?? '') == 'verified');

  /// Builds and opens the bill's statement or receipt PDF.
  Future<void> _downloadSlip(Map<String, dynamic> bill) async {
    try {
      await ReceiptPdf.open(bill: bill, payments: _paymentsFor(bill['id']));
    } catch (e) {
      if (mounted) _snack('Could not build the document. ${friendlyError(e)}', error: true);
    }
  }

  /// The My Bills tab: a paged list of bill cards.
  Widget _billsList() {
    final all = _shownBills;
    if (all.isEmpty) {
      return Center(
          child: Text(_bills.isEmpty ? 'No bills yet.' : 'No bills match this card. Tap it again to show all.',
              style: const TextStyle(fontSize: 13, color: ResidentColors.textSecondary)));
    }
    final rows = pageSlice(all, _billsPage);
    final narrow = _narrow(context);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(_gutter(context), 16, _gutter(context), 32),
      itemCount: rows.length + (pageCountFor(all.length) > 1 ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= rows.length) {
          return pagerFor(all.length, _billsPage, (p) => setState(() => _billsPage = p));
        }
        final b = rows[i];
        final unpaid = b['status'] != 'paid' && b['status'] != 'cancelled' && b['status'] != 'waived';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: ResidentColors.cardShadow),
          // On a phone the badge, download and pay actions cannot share a
          // line with the bill text, so they drop onto their own row.
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _billText(b),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: _billControls(b, unpaid),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: _billText(b)),
                    ..._billControls(b, unpaid),
                  ],
                ),
        );
      },
    );
  }

  Widget _billText(Map<String, dynamic> b) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${b['description'] ?? 'Bill'} · #${b['bill_number'] ?? b['id']}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
          const SizedBox(height: 3),
          Text('₱${_net(b).toStringAsFixed(2)} · Due ${_dateLabel(b['due_date']?.toString())}',
              style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
        ],
      );

  /// A bill's status badge, download button and, if unpaid, its pay actions.
  List<Widget> _billControls(Map<String, dynamic> b, bool unpaid) => [
        StatusBadge((b['status'] ?? '').toString()),
        const SizedBox(width: 4),
        // Always offered: a statement while the bill is unpaid, and the
        // official receipt once the treasurer has verified a payment.
        IconButton(
          tooltip: _hasVerifiedPayment(b['id']) ? 'Download receipt' : 'Download statement',
          visualDensity: VisualDensity.compact,
          icon: Icon(
              _hasVerifiedPayment(b['id']) ? Icons.receipt_long_outlined : Icons.download_outlined,
              size: 18,
              color: ResidentColors.textSecondary),
          onPressed: () => _downloadSlip(b),
        ),
        if (unpaid) _billAction(b),
      ];

  /// The Payment History tab: a paged list of payment cards.
  Widget _paymentHistoryList() {
    final all = _shownPayments;
    if (all.isEmpty) {
      return Center(
          child: Text(_payments.isEmpty ? 'No payments recorded yet.' : 'No payments this year yet.',
              style: const TextStyle(fontSize: 13, color: ResidentColors.textSecondary)));
    }
    final rows = pageSlice(all, _historyPage);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(_gutter(context), 16, _gutter(context), 32),
      itemCount: rows.length + (pageCountFor(all.length) > 1 ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= rows.length) {
          return pagerFor(all.length, _historyPage, (p) => setState(() => _historyPage = p));
        }
        final p = rows[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: ResidentColors.cardShadow),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('#${p['or_number'] ?? p['id']}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text('${titleCase((p['payment_method'] ?? '').toString())} · ${_dateLabel(p['payment_date']?.toString())}',
                        style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
                  ],
                ),
              ),
              Text('₱${(num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
              const SizedBox(width: 10),
              StatusBadge((p['status'] ?? '').toString()),
              // Receipt from the bill this payment settled; verified payments only.
              if ((p['status'] ?? '') == 'verified' && _billFor(p) != null)
                IconButton(
                  tooltip: 'Download receipt',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.receipt_long_outlined,
                      size: 18, color: ResidentColors.textSecondary),
                  onPressed: () => _downloadSlip(_billFor(p)!),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The bill a payment settled, or null if it is not in the loaded list.
  /// A null only hides the receipt button.
  Map<String, dynamic>? _billFor(Map<String, dynamic> payment) {
    for (final b in _bills) {
      if (b['id'] == payment['bill_id']) return b;
    }
    return null;
  }
}

/// "Pay a Bill" page, opened from the QR icon on a bill row. [bill] is that
/// row's data, or null if opened with nothing selected.
/// It records nothing: it shows the accounts to pay and tells the resident to
/// send proof afterwards.
class MemberPayBillScreen extends StatefulWidget {
  final Map<String, dynamic>? bill;
  const MemberPayBillScreen({super.key, this.bill});

  @override
  State<MemberPayBillScreen> createState() => _MemberPayBillScreenState();
}

class _MemberPayBillScreenState extends State<MemberPayBillScreen> with SafeSetState<MemberPayBillScreen> {
  /// What a bill comes to: amount plus penalty minus discount.
  num _net(Map<String, dynamic> b) {
    final amt = num.tryParse(b['amount']?.toString() ?? '0') ?? 0;
    final pen = num.tryParse(b['penalty_amount']?.toString() ?? '0') ?? 0;
    final disc = num.tryParse(b['discount_amount']?.toString() ?? '0') ?? 0;
    return amt + pen - disc;
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    return MemberShell(
      title: 'Pay a Bill',
      activeItem: 'My Payments',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Bill'),
                child: Text(b == null ? 'Select from My Bills' : '#${b['bill_number'] ?? b['id']} ${b['description'] ?? ''}'),
              ),
              const SizedBox(height: 14),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Amount'),
                child: Text(b == null ? '—' : '₱${_net(b).toStringAsFixed(2)}'),
              ),
              const SizedBox(height: 22),
              // Accounts come from Finance -> Channels; RLS limits them to this
              // resident's own association plus any shared ones.
              const Text('Where to send it',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              const Text(
                'Scan the QR in your wallet app, or copy the account number. '
                'Put your lot number in the message so the treasurer can match it.',
                style: TextStyle(
                    fontSize: 12.5, color: ResidentColors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 14),
              const PaymentChannelsView(),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: ResidentColors.iconAmberBg,
                    borderRadius: BorderRadius.circular(10)),
                child: const Text(
                  'Paying does not clear the bill on its own. Once you have sent '
                  'it, go back to My Bills and tap "Send Proof" to upload the '
                  'receipt — the treasurer verifies it and the bill is marked paid.',
                  style: TextStyle(fontSize: 12, color: ResidentColors.iconAmberText, height: 1.4),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
