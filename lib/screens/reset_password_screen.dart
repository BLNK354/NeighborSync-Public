import 'dart:async';
import 'package:flutter/material.dart';
import '../core/auth_link_error.dart';
import '../core/form_helpers.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_screen_scaffold.dart';
import '../widgets/password_feedback.dart';
import '../core/safe_state.dart';

/// Page opened from the password-reset email link. It waits for the
/// recovery session to be ready, then lets the user set a new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> with SafeSetState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _done = false;
  String? _error;
  bool _sessionReady = false;
  StreamSubscription<AuthState>? _authSub;
  Timer? _waitTimer;

  String? _linkFailure;

  static const _kWaitForSession = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _sessionReady = SupabaseService.instance.client.auth.currentSession != null;
    _authSub = SupabaseService.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.passwordRecovery ||
            SupabaseService.instance.client.auth.currentSession != null) {
          _waitTimer?.cancel();
          if (mounted) setState(() => _sessionReady = true);
        }
      },
      onError: (Object e) {
        _waitTimer?.cancel();
        if (mounted) {
          setState(() => _linkFailure =
              'That reset link could not be confirmed. Links work once, and '
              'only in the browser that asked for them -- if you opened this '
              'on a different device or have already used it, request a new '
              'one below.');
        }
      },
    );

    if (!_sessionReady) {
      _waitTimer = Timer(_kWaitForSession, () {
        if (mounted && !_sessionReady) {
          setState(() => _linkFailure =
              "We didn't get a valid reset link from this page's address. "
              'Open the most recent link straight from your email on this '
              'device, or request a new one below.');
        }
      });
    }
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _authSub?.cancel();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.updatePassword(_passwordCtrl.text);
      // Sign out every device so only the new password gets back in.
      try {
        await SupabaseService.instance.signOutEverywhere();
      } catch (_) {}
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reset password. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = authLinkError?.message ?? _linkFailure;

    return AuthScreenScaffold(
      formKey: _formKey,
      children: [
      Text('Set a new password',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 6),
      const Text("Choose a strong password you'll remember.",
          style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
      const SizedBox(height: 28),
      if (_done) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.badgeGreenBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline,
                  color: AppColors.sidebarActiveText, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your password has been reset. Sign in again with your '
                  'new password \u2014 all other devices have been signed out.',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.sidebarActiveText, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            if (context.mounted) context.go('/login?pw=1');
          },
          child: const Text('Back to Log In'),
        ),
      ] else if (failure != null) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.badgeAmberBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.schedule_outlined,
                  color: AppColors.badgeAmberText, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  failure,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.badgeAmberText,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => context.go('/forgot-password'),
          child: const Text('Request a new link'),
        ),
      ] else if (!_sessionReady) ...[
        const Row(
          children: [
            SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Confirming your reset link\u2026',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          "If this doesn't finish in a few seconds, the link may have "
          'expired -- request a new one.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => context.go('/forgot-password'),
          child: Text('Request a new link',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sidebarActiveText)),
        ),
      ] else
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New Password',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF5C5C66))),
            const SizedBox(height: 6),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(hintText: '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022'),
              validator: passwordError,
            ),
            PasswordStrengthBar(controller: _passwordCtrl, topGap: 10),
            const SizedBox(height: 6),
            const Text(kPasswordHint,
                style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    height: 1.35)),
            const SizedBox(height: 16),
            const Text('Confirm New Password',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF5C5C66))),
            const SizedBox(height: 6),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(hintText: '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022'),
              onFieldSubmitted: (_) => _submit(),
              validator: (v) => v != _passwordCtrl.text
                  ? 'Passwords do not match'
                  : null,
            ),
            PasswordMatchNote(
              passwordController: _passwordCtrl,
              confirmController: _confirmCtrl,
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
              ),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Reset Password'),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => context.go('/login'),
              child: Text('Back to Log In',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.sidebarActiveText)),
            ),
          ],
        ),
      ],
    );
  }
}
