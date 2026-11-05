import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../core/auth_link_timing.dart';
import '../core/branding.dart';
import '../core/device_label.dart';
import '../core/roles.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_screen_scaffold.dart';
import '../core/safe_state.dart';

/// Second sign-in step for accounts using an emailed 6-digit code.
/// Verifies the code, then finishes sign-in (device record, routing).
///
/// Reached while signed out, so it must stay in main.dart's public paths.
/// The address lives in memory ([SupabaseService.pendingEmailCodeAddress]);
/// after a reload it is gone and the person is sent back to log in.
class MfaEmailScreen extends StatefulWidget {
  const MfaEmailScreen({super.key});

  @override
  State<MfaEmailScreen> createState() => _MfaEmailScreenState();
}

class _MfaEmailScreenState extends State<MfaEmailScreen> with SafeSetState<MfaEmailScreen> {
  final _codeCtrl = TextEditingController();
  final String? _email = SupabaseService.pendingEmailCodeAddress;
  bool _verifying = false;
  bool _resending = false;
  String? _error;
  String? _info;
  DateTime _sentAt = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _cooldownLeft > Duration.zero) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Locked for 3 minutes after each code (kEmailCodeResendCooldown).
  Duration get _cooldownLeft {
    final left = kEmailCodeResendCooldown - DateTime.now().difference(_sentAt);
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _verify(String code) async {
    // Drop focus first; navigating away with a focused code box throws.
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _email;
    if (email == null || code.trim().length != 6 || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
      _info = null;
    });
    try {
      final svc = SupabaseService.instance;
      await svc.verifyEmailLoginCode(email: email, code: code.trim());
      SupabaseService.pendingEmailCodeAddress = null;
      await AppBranding.instance.load();
      await svc.recordLoginSession(currentDeviceLabel());
      await svc.signOutOtherDevices();
      final info = await svc.getRoleAndStatus();
      if (!mounted) return;
      if (info != null && officerRoles.contains(info.role)) {
        context.go('/admin');
      } else if (info?.status == 'pending_verification') {
        context.go('/me/profile');
      } else {
        context.go('/dashboard');
      }
    } catch (_) {
      _codeCtrl.clear();
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = "That code didn't match or has expired. Try again, or send a new code.";
      });
    }
  }

  Future<void> _resend() async {
    final email = _email;
    if (email == null || _resending || _cooldownLeft > Duration.zero) return;
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });
    try {
      await SupabaseService.instance.sendEmailLoginCode(email);
      if (!mounted) return;
      setState(() {
        _sentAt = DateTime.now();
        _info = 'A new code is on its way. Only the newest code works. You can ask for another in 3 minutes.';
      });
    } on AuthException catch (e) {
      // Show the server's own wording; it explains the rate limit.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send a new code. Check your connection.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _backToLogin() {
    SupabaseService.pendingEmailCodeAddress = null;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final email = _email;
    if (email == null) {
      return AuthScreenScaffold(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Sign in again',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
            'This sign-in step is no longer open (the page was reloaded or '
            'left). Enter your email and password again to get a new code.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _backToLogin, child: const Text('Back to sign in')),
          ),
        ],
      );
    }

    final left = _cooldownLeft;
    return AuthScreenScaffold(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Check your email',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(
          'We sent a 6-digit sign-in code to ${maskEmail(email)}. '
          'Enter it below to finish signing in.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 28),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
          ),
        if (_info != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(_info!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.sidebarActiveText, fontSize: 12.5)),
          ),
        Pinput(
          length: 6,
          controller: _codeCtrl,
          enabled: !_verifying,
          autofocus: true,
          onCompleted: _verify,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _verifying ? null : () => _verify(_codeCtrl.text.trim()),
            child: _verifying
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Verify'),
          ),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: (_resending || left > Duration.zero) ? null : _resend,
          child: Text(_resending
              ? 'Sending...'
              : left > Duration.zero
                  ? 'Send a new code in ${formatCountdown(left)}'
                  : 'Send a new code'),
        ),
        const SizedBox(height: 4),
        const Text(
          "Can't find it? Check your spam folder.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _backToLogin,
          child: Text('Back to sign in',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sidebarActiveText)),
        ),
      ],
    );
  }
}
