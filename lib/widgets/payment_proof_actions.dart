import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../core/dialog_sizing.dart';
import '../core/dialog_controllers.dart';
import '../core/stored_file.dart';

/// View / verify / reject a resident's uploaded proof of payment.
///
/// Shared by the Payments review queue and the bill detail page. The
/// verify and reject functions return true when the database changed, so the
/// caller knows to reload.

/// Opens the uploaded receipt from the private bucket.
///
/// Only someone with `payments:read` can open it (Storage policy
/// `receipts_select_own_or_treasurer`).
Future<void> viewPaymentReceipt(BuildContext context, String? receiptPath) async {
  if (receiptPath == null || receiptPath.isEmpty) return;
  try {
    // Every private file open is logged here. The module comes from the
    // path's first folder, so callers need not pass a label.
    final folder = receiptPath.split('/').first;
    await SupabaseService.instance.logAuditAction(
      'view',
      switch (folder) {
        'receipts' => 'payments',
        'complaints' => 'complaints',
        'ownership' => 'users',
        'payment-qr' => 'payment_channels',
        _ => 'documents',
      },
      resource: receiptPath.split('/').last,
    );

    if (!context.mounted) return;
    await openStoredFile(context, path: receiptPath);
  } catch (e) {
    if (context.mounted) {
      _snack(context, 'Could not open the receipt. ${friendlyError(e)}', error: true);
    }
  }
}

/// Verifies a submission, creating the authoritative `payments` row.
///
/// All the work is in `approve_payment_submission()`, so it fully succeeds or
/// fails, and two treasurers clicking at once cannot create two payments.
Future<bool> approvePaymentSubmission(
  BuildContext context,
  Map<String, dynamic> sub, {
  String? residentName,
  String? billNumber,
}) async {
  final amount = (num.tryParse(sub['amount'].toString()) ?? 0).toStringAsFixed(2);
  final who = (residentName ?? '').trim();
  final bill = billNumber ?? sub['bill_id']?.toString() ?? '—';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Verify this payment?'),
      content: SizedBox(
        width: dialogContentWidth(context, 380),
        child: Text(
          'This records a verified payment of ₱$amount'
          '${who.isEmpty ? '' : ' from $who'} against bill #$bill.\n\n'
          'Check the receipt against the association records first — this '
          'updates the ledger.',
          style: const TextStyle(
              fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Verify')),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    await SupabaseService.instance.client.rpc('approve_payment_submission', params: {
      'p_submission_id': sub['id'],
      'p_review_note': null,
    });
    if (context.mounted) _snack(context, 'Payment verified and recorded.');
    return true;
  } catch (e) {
    if (context.mounted) {
      _snack(context, 'Could not verify. ${friendlyError(e)}', error: true);
    }
    return false;
  }
}

/// Rejects a submission. A reason is required so the resident knows what to fix.
Future<bool> rejectPaymentSubmission(
    BuildContext context, Map<String, dynamic> sub) async {
  final noteCtrl = TextEditingController();
  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject this proof?'),
        content: SizedBox(
          width: dialogContentWidth(context, 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The resident sees this reason, so say what was wrong '
                '(wrong amount, unreadable photo, no matching deposit).',
                style: TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
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
              onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA82F2F)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    if (noteCtrl.text.trim().isEmpty) {
      if (context.mounted) {
        _snack(context, 'Please give a reason so the resident knows what to fix.',
            error: true);
      }
      return false;
    }

    try {
      await SupabaseService.instance.client.rpc('reject_payment_submission', params: {
        'p_submission_id': sub['id'],
        'p_review_note': noteCtrl.text.trim(),
      });
      if (context.mounted) _snack(context, 'Rejected. The resident has been notified.');
      return true;
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Could not reject. ${friendlyError(e)}', error: true);
      }
      return false;
    }
  } finally {
    disposeAfterDialogCloses([noteCtrl]);
  }
}

/// Shows a short message at the bottom; red when [error] is true.
void _snack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? const Color(0xFFA82F2F) : null,
  ));
}
