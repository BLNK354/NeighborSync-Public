import 'package:flutter/material.dart';
import '../core/auth_link_error.dart';
import '../core/form_helpers.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_link_status.dart';
import '../widgets/auth_screen_scaffold.dart';
import '../core/safe_state.dart';

/// Forgot Password page: sends a reset link to the email entered.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> with SafeSetState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.sendPasswordResetEmail(_emailCtrl.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not send reset link. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScreenScaffold(
      formKey: _formKey,
      children: [
      Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: AppColors.badgeGreenBg,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(Icons.lock_reset_outlined,
            color: AppColors.sidebarActiveText, size: 26),
      ),
      const SizedBox(height: 20),
      Text('Forgot your password?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      const Text(
        "Enter the email address linked to your account and we'll "
        'send you a link to reset your password.',
        style: TextStyle(fontSize: 13.5, color: AppColors.textMuted, height: 1.5),
      ),
      const SizedBox(height: 28),
      // Tells people who came from a dead link why. Hidden once a new link is sent.
      if (authLinkError != null && !_sent) ...[
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
                  authLinkError!.message,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.badgeAmberText,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
      if (_sent) ...[
        // Keep "If an account exists" wording: it must never reveal whether
        // an email is registered, and resend must behave the same either way.
        AuthLinkStatus(
          email: _emailCtrl.text.trim(),
          resendLabel: 'Resend reset link',
          message: (masked) =>
              'If an account exists for $masked, a reset link is on its way.',
          onResend: () => SupabaseService.instance
              .sendPasswordResetEmail(_emailCtrl.text.trim()),
        ),
        const SizedBox(height: 24),
      ]
      // No Form here: AuthScreenScaffold already wraps these in one with
      // _formKey, and a second Form with the same key breaks the page.
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Email Address',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF5C5C66))),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'you@gmail.com'),
              onFieldSubmitted: (_) => _submit(),
              validator: emailError,
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
                  : const Text('Send Reset Link'),
            ),
          ],
        ),
      const SizedBox(height: 8),
      InkWell(
        onTap: () => context.go('/login'),
        child: Text('← Back to Log In',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.sidebarActiveText)),
      ),
      ],
    );
  }
}
