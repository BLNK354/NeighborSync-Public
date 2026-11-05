import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/session_storage.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_link_status.dart';
import '../widgets/auth_screen_scaffold.dart';
import '../core/safe_state.dart';

/// Asks the person to tap the emailed link, with a resend button.
/// Moves on to the login route (which forwards them home) once the account is verified.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> with SafeSetState<VerifyEmailScreen> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub =
        SupabaseService.instance.client.auth.onAuthStateChange.listen((_) {
      if (SupabaseService.instance.isEmailVerified && mounted) {
        clearPendingVerifyEmail();
        // The router sends a verified, signed-in person on to their own home.
        context.go('/login');
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = SupabaseService.instance.client.auth.currentUser?.email;
    return AuthScreenScaffold(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
      Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          color: AppColors.badgeGreenBg,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(Icons.mark_email_unread_outlined,
            color: AppColors.sidebarActiveText, size: 32),
      ),
      const SizedBox(height: 24),
      Text('Verify your email',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
      const SizedBox(height: 10),
      const Text(
        'Tap the link in the email to activate your account.',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 13.5,
            color: AppColors.textMuted,
            height: 1.5),
      ),
      const SizedBox(height: 28),
      // A fresh signup has no session yet, so resend uses the address saved
      // at registration. With no saved address there is nothing to send to.
      if (email == null)
        switch (readPendingVerifyEmail()) {
          null => const Text(
              'Sign in again to have the verification link resent.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.textMuted, height: 1.5),
            ),
          final pending => AuthLinkStatus(
              email: pending,
              resendLabel: 'Send verification again',
              message: (masked) => 'We sent a verification link to $masked.',
              onResend: () =>
                  SupabaseService.instance.resendVerificationEmail(pending),
            ),
        }
      else
        AuthLinkStatus(
          email: email,
          resendLabel: 'Resend verification link',
          message: (masked) => 'We sent a verification link to $masked.',
          onResend: () =>
              SupabaseService.instance.resendVerificationEmail(email),
        ),
      const SizedBox(height: 20),
      InkWell(
        onTap: () async {
          await SupabaseService.instance.signOut();
          if (context.mounted) context.go('/login');
        },
        child: Text('Back to Log In',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.sidebarActiveText)),
      ),
      ],
    );
  }
}
