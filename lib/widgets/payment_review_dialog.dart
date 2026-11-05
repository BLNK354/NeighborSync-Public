import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../core/form_helpers.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'payment_proof_actions.dart';
import '../core/dialog_sizing.dart';
import '../core/dialog_controllers.dart';
import '../core/safe_state.dart';
import '../core/stored_file.dart';

/// Lets an officer verify or reject one pending payment.
///
/// Shows the bill and what is still owed, the resident's uploaded receipts,
/// and the payment's own receipt. Only verified payments count toward a bill.
///
/// Returns true when the database changed, so the caller reloads.
Future<bool> reviewPayment(
  BuildContext context,
  Map<String, dynamic> payment, {
  String? residentName,
  bool readOnly = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _PaymentReviewDialog(
        payment: payment, residentName: residentName, readOnly: readOnly),
  );
  return result == true;
}

/// " · BPI" when the resident named the account they paid into, else empty.
/// Older submissions have no channel, so no dangling separator is shown.
String _channelSuffix(Map<String, dynamic> s) {
  final ch = s['channel'] as Map<String, dynamic>?;
  if (ch == null) return '';
  final label = (ch['label'] ?? '').toString().trim();
  return label.isEmpty ? '' : ' · $label';
}

class _PaymentReviewDialog extends StatefulWidget {
  final Map<String, dynamic> payment;
  final String? residentName;
  final bool readOnly;
  const _PaymentReviewDialog(
      {required this.payment, this.residentName, this.readOnly = false});

  @override
  State<_PaymentReviewDialog> createState() => _PaymentReviewDialogState();
}

class _PaymentReviewDialogState extends State<_PaymentReviewDialog> with SafeSetState<_PaymentReviewDialog> {
  bool _loading = true;
  bool _busy = false;
  String? _error;

  Map<String, dynamic>? _bill;
  double _alreadyVerified = 0;
  List<Map<String, dynamic>> _proof = [];

  double get _amount =>
      num.tryParse('${widget.payment['amount_paid']}')?.toDouble() ?? 0;

  double get _due {
    final b = _bill;
    if (b == null) return 0;
    double n(Object? v) => num.tryParse('${v ?? 0}')?.toDouble() ?? 0;
    return n(b['amount']) + n(b['penalty_amount']) - n(b['discount_amount']);
  }

  double get _balance => _due - _alreadyVerified;

  /// True when nothing is left to pay. The database refuses a verified
  /// payment then (trg_block_payment_on_settled_bill), so warn up front.
  bool get _billSettled => _bill != null && _balance <= 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = SupabaseService.instance.client;
      final billId = widget.payment['bill_id'];

      final bill = await c
          .from('bills')
          .select('bill_number, status, due_date, amount, penalty_amount, '
              'discount_amount')
          .eq('id', billId)
          .maybeSingle();

      // Verified payments on this bill, skipping the one under review.
      final verified = await c
          .from('payments')
          .select('id, amount_paid')
          .eq('bill_id', billId)
          .eq('status', 'verified');
      var total = 0.0;
      for (final p in verified as List) {
        if (p['id'] == widget.payment['id']) continue;
        total += num.tryParse('${p['amount_paid']}')?.toDouble() ?? 0;
      }

      // Receipts the resident uploaded for this bill, matched by bill id.
      final proof = await c
          .from('payment_submissions')
          // channel = the account paid into. Named FK column: the embed is
          // ambiguous without it if a second FK is ever added.
          .select('id, amount, payment_method, reference_number, paid_on, '
              'receipt_path, note, status, review_note, created_at, '
              'channel:channel_id(label, account_name, account_number)')
          .eq('bill_id', billId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _bill = bill;
        _alreadyVerified = total;
        _proof = List<Map<String, dynamic>>.from(proof as List);
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

  /// Shows the database's own message; `friendlyError` would make it generic.
  String _reviewError(Object e) =>
      e is PostgrestException && e.message.isNotEmpty
          ? e.message
          : friendlyError(e);

  Future<void> _apply(String status, {String? reason}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final patch = <String, dynamic>{
        'status': status,
        // Also records who rejected it: these are the only reviewer columns.
        'verified_by': SupabaseService.cachedUserRowId,
        'verified_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (reason != null) {
        final existing = (widget.payment['notes'] ?? '').toString().trim();
        final stamp = DateTime.now().toIso8601String().split('T').first;
        patch['notes'] =
            '${existing.isEmpty ? '' : '$existing | '}Rejected $stamp: $reason';
      }
      await SupabaseService.instance.client
          .from('payments')
          .update(patch)
          .eq('id', widget.payment['id']);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _reviewError(e);
        });
      }
    }
  }

  Future<void> _reject() async {
    final noteCtrl = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject this payment?'),
          content: SizedBox(
            width: dialogContentWidth(context, 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Say what was wrong — the reason is kept on the payment '
                  'record (wrong amount, no matching deposit, receipt does '
                  'not match).',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.4),
                ),
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
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFA82F2F)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final reason = noteCtrl.text.trim();
      if (reason.isEmpty) {
        if (mounted) {
          setState(() => _error =
              'Give a reason — a bare rejection leaves no record of why.');
        }
        return;
      }
      await _apply('rejected', reason: reason);
    } finally {
      disposeAfterDialogCloses([noteCtrl]);
    }
  }

  bool get _isPending =>
      !widget.readOnly &&
      (widget.payment['status'] ?? 'pending').toString() == 'pending';

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final inset = width < 500 ? 16.0 : 40.0;
    final contentWidth = (width - inset * 2 - 48).clamp(260.0, 440.0);

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: inset, vertical: 24),
      // Only pending payments can be reviewed; decided ones open read-only.
      title: Text(_isPending ? 'Review payment' : 'Payment details'),
      content: SizedBox(
        width: contentWidth.toDouble(),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _paymentBlock(),
                    const SizedBox(height: 14),
                    _billBlock(),
                    const SizedBox(height: 14),
                    _proofBlock(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFA82F2F))),
                    ],
                  ],
                ),
              ),
      ),
      actions: _loading
          ? null
          : !_isPending
          ? [
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Close')),
            ]
          : [
              TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              TextButton(
                onPressed: _busy ? null : _reject,
                style:
                    TextButton.styleFrom(foregroundColor: const Color(0xFFA82F2F)),
                child: const Text('Reject'),
              ),
              FilledButton(
                onPressed: _busy || _billSettled || _amount > _balance ? null : () => _apply('verified'),
                child: Text(_busy ? 'Saving…' : 'Verify'),
              ),
            ],
    );
  }

  Widget _panel({required Widget child, bool warn = false}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warn ? AppColors.badgeAmberBg : AppColors.highlight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textPrimary)),
            ),
          ],
        ),
      );

  Widget _paymentBlock() {
    final p = widget.payment;
    final method = (p['payment_method'] ?? '').toString();
    final ref = (p['reference_number'] ?? '').toString();
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text((p['or_number'] ?? '—').toString(),
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
              Text(formatPeso(_amount),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          _line('Paid by', widget.residentName ?? '—'),
          _line('Method', method.isEmpty ? '—' : titleCase(method)),
          _line('Date', _date(p['payment_date'])),
          if (ref.isNotEmpty) _line('Reference', ref),
        ],
      ),
    );
  }

  Widget _billBlock() {
    final b = _bill;
    if (b == null) {
      return _panel(child: _line('Bill', 'Could not load the bill.'));
    }
    return _panel(
      warn: _billSettled || _amount > _balance,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line('Bill', (b['bill_number'] ?? '—').toString()),
          _line('Bill total', formatPeso(_due)),
          _line('Already paid', formatPeso(_alreadyVerified)),
          _line(
              _balance < 0 ? 'Overpaid by' : 'Still owed',
              formatPeso(_balance.abs())),
          const SizedBox(height: 4),
          Text(
            _billSettled
                ? 'Nothing left to pay — verifying will be refused. Void the '
                    'earlier payment first if this one is a correction.'
                : _amount > _balance
                    ? 'This is more than the ${formatPeso(_balance)} still '
                        'owed, so it will be refused. Reject it and record '
                        'the correct amount.'
                    : 'Verifying moves the bill to '
                        '${_amount >= _balance ? 'Paid' : 'Partial'}.',
            style: TextStyle(
                fontSize: 11,
                color: _billSettled
                    ? AppColors.textPrimary
                    : AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _proofBlock() {
    final ownReceipt = (widget.payment['receipt_url'] ?? '').toString();

    if (_proof.isEmpty && ownReceipt.isEmpty) {
      // Say so plainly: verifying with no receipt is the officer's call.
      return _panel(
        child: const Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No receipt was uploaded for this bill. Verify only if you '
                'took this payment yourself or can match it to a deposit.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Proof on file',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        if (ownReceipt.isNotEmpty)
          _panel(
            child: Row(
              children: [
                const Expanded(
                  child: Text('Receipt attached to this payment',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textPrimary)),
                ),
                TextButton(
                  onPressed: () => openStoredFile(context, publicUrl: ownReceipt)
                      .catchError((_) {}),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        for (final s in _proof) ...[
          if (ownReceipt.isNotEmpty || s != _proof.first)
            const SizedBox(height: 8),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                          'Resident sent ${formatPeso(s['amount'])} · '
                          '${titleCase((s['payment_method'] ?? '').toString())}'
                          '${_channelSuffix(s)}',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ),
                    Text(titleCase((s['status'] ?? '').toString()),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Paid on ${_date(s['paid_on'])}'
                  '${(s['reference_number'] ?? '').toString().isEmpty ? '' : ' · ref ${s['reference_number']}'}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted),
                ),
                if ((s['note'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('"${s['note']}"',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondary)),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        viewPaymentReceipt(context, s['receipt_path'] as String?),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Open receipt'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _date(Object? v) {
    final dt = DateTime.tryParse((v ?? '').toString());
    if (dt == null) return '—';
    const m = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${m[dt.month]} ${dt.year}';
  }
}
