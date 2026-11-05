import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';

/// "Reset password" for the account screens: an officer sends a reset email
/// to the resident's own inbox. The officer never sees a password or link.
/// The `admin-reset-password` Edge Function re-checks permission on the server;
/// the check here only decides whether to show the button.

/// Whether to show the button: true when the user holds `users:update`.
bool canResetPassword(Map<String, Set<String>> perms) =>
    perms['users']?.contains('update') ?? false;

/// Confirms, then sends. Returns true when the email went out.
///
/// [account] is a `users` row; it needs `id`, `email`, and ideally the name
/// fields for the dialog copy.
Future<bool> sendPasswordResetFor(
  BuildContext context,
  Map<String, dynamic> account,
) async {
  final email = (account['email'] ?? '').toString();
  final name = [account['first_name'], account['last_name']]
      .where((s) => s != null && s.toString().trim().isNotEmpty)
      .join(' ')
      .trim();
  final who = name.isEmpty ? 'this account' : name;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Send a password reset?'),
      content: ConstrainedBox(
        // Dialog padding takes 128px; a fixed width would overflow on a phone.
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 128 < 360
              ? MediaQuery.of(context).size.width - 128
              : 360,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$who will get an email with a link to choose a new password.',
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 12),
            // Show the exact address so the officer sees where the mail goes.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.pageBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                email.isEmpty ? 'No email on record' : email,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "You won't see the link or the new password — it goes straight "
              'to them, and the link expires in an hour.',
              style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: email.isEmpty ? null : () => Navigator.pop(context, true),
          child: const Text('Send reset email'),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;

  try {
    final sentTo = await SupabaseService.instance.adminSendPasswordReset(account['id']);
    if (context.mounted) {
      AppToast.success(
        context,
        message: 'Reset link sent to ${sentTo.isEmpty ? email : sentTo}.',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      // Not friendlyError: it would hide the function's specific reasons.
      AppToast.error(
        context,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
    return false;
  }
}

/// The "Reset password" button; tapping it confirms, then sends the email.
class ResetPasswordButton extends StatelessWidget {
  const ResetPasswordButton({
    super.key,
    required this.account,
    this.dense = false,
    this.onSent,
  });

  final Map<String, dynamic> account;

  /// Text button (inside a dialog's action row) rather than an outlined
  /// button (a row action beside Edit / Files).
  final bool dense;

  final VoidCallback? onSent;

  @override
  Widget build(BuildContext context) {
    Future<void> go() async {
      final ok = await sendPasswordResetFor(context, account);
      if (ok) onSent?.call();
    }

    if (dense) {
      return TextButton.icon(
        onPressed: go,
        icon: const Icon(Icons.lock_reset, size: 16),
        label: const Text('Reset password'),
      );
    }
    return OutlinedButton.icon(
      onPressed: go,
      icon: const Icon(Icons.lock_reset, size: 15),
      label: const Text('Reset password'),
    );
  }
}
