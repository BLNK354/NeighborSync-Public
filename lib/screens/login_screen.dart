import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import 'package:go_router/go_router.dart';
import '../core/branding.dart';
import '../core/device_label.dart';
import '../core/roles.dart';
import '../core/session_policy.dart';
import '../core/session_storage.dart' show supportsNonPersistentSession;
import '../core/user_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_screen_scaffold.dart';
import '../core/safe_state.dart';

/// Login screen: a split layout with the branded panel on the left and
/// the sign-in form on the right. The brand panel is hidden on narrow
/// windows so the form stays usable on small screens.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SafeSetState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  /// Off by default, so a shared machine signs out when the browser closes.
  bool _rememberDevice = false;

  bool _readReasonFlag = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Shows why the user was sent here. Read here, not in initState,
    // because GoRouterState.of() needs inherited widgets.
    if (_readReasonFlag) return;
    _readReasonFlag = true;
    final q = GoRouterState.of(context).uri.queryParameters;
    if (q['timeout'] == '1') {
      setState(() => _error =
          'You were signed out after a period of inactivity.');
    } else if (q['kicked'] == '1') {
      setState(() => _error =
          'You were signed out because your account was used on another device.');
    } else if (q['pw'] == '1') {
      setState(() => _error =
          'Password updated. Please sign in again with your new password.');
    }
  }

  /// Signs in, runs the maintenance and two-factor checks, then opens the
  /// right home screen for the role.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Must be set before signing in; storage reads it to place the session.
      SessionPolicy.setRememberDevice(_rememberDevice);
      await SupabaseService.instance.signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      final info = await SupabaseService.instance.getRoleAndStatus();
      if (info == null) {
        setState(() => _error = 'Could not load your account. Contact an admin.');
        return;
      }

      // Reload branding; the boot-time load ran signed out and sees fewer rows.
      await AppBranding.instance.load();

      // Maintenance Mode blocks everyone except officers.
      if (!officerRoles.contains(info.role)) {
        final maintenance = await SupabaseService.instance.client
            .from('system_settings')
            .select('value')
            .eq('setting_key', 'general.maintenance_mode')
            .maybeSingle();
        if (maintenance != null && maintenance['value'] == 'true') {
          SupabaseService.instance.clearIdentityCache();
          await SupabaseService.instance.client.auth.signOut();
          if (!mounted) return;
          setState(() => _error = 'The system is currently under maintenance. Please try again later.');
          return;
        }
      }

      // Email sign-in code. An authenticator app takes priority (handled
      // below). The password-only session is closed before the code is sent.
      if (!SupabaseService.instance.needsMfaStepUp()) {
        final prefs = await readMyPreferences();
        if (prefs['email_2fa'] == true) {
          final email = _emailCtrl.text.trim();
          SupabaseService.instance.clearIdentityCache();
          await SupabaseService.instance.client.auth.signOut(scope: SignOutScope.local);
          await SupabaseService.instance.sendEmailLoginCode(email);
          SupabaseService.pendingEmailCodeAddress = email;
          if (!mounted) return;
          context.go('/mfa-email');
          return;
        }
      }

      // Record this device in Recent Sign-ins, only after sign-in is allowed.
      await SupabaseService.instance.recordLoginSession(currentDeviceLabel());

      // One session only: sign out every other device.
      await SupabaseService.instance.signOutOtherDevices();

      // Where to land first; the router redirect in main.dart enforces access.
      if (!mounted) return;

      // Authenticator users must pass the MFA challenge first.
      if (SupabaseService.instance.needsMfaStepUp()) {
        context.go('/mfa-challenge');
        return;
      }

      if (officerRoles.contains(info.role)) {
        context.go('/admin');
      } else if (info.status == 'pending_verification') {
        // Pending: Profile first, where the address and proof are filled in.
        context.go('/me/profile');
      } else {
        context.go('/dashboard');
      }
    } catch (e) {
      // Same message for wrong email or password, so it cannot reveal
      // which addresses have accounts.
      var message = friendlyError(e);
      if (e.toString().toLowerCase().contains('invalid login credentials')) {
        message = 'Incorrect email or password. Please try again.';
      }
      if (!mounted) return;
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScreenScaffold(
      brandDescription:
          'Manage billing, complaints, visitors and security requests '
          '— all in one place, built for your community.',
      showBackToHome: true,
      formKey: _formKey,
      children: [
      Text('Welcome back',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 6),
      const Text('Log in to your NeighborSync account',
          style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
      // Maintenance notice, shown before sign-in.
      if (AppBranding.instance.maintenanceMode) ...[
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.badgeAmberBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.construction_outlined, size: 18, color: AppColors.badgeAmberText),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The system is under maintenance. Residents and tenants '
                  'cannot log in until it is finished. HOA officers can '
                  'still log in.',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.badgeAmberText),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 32),
      const Text('Email Address',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF5C5C66))),
      const SizedBox(height: 6),
      TextFormField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(hintText: 'you@gmail.com'),
        validator: emailError,
      ),
      const SizedBox(height: 18),
      const Text('Password',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF5C5C66))),
      const SizedBox(height: 6),
      TextFormField(
        controller: _passwordCtrl,
        obscureText: _obscure,
        onFieldSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Enter your password',
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 20, color: AppColors.textMuted),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
      ),
      const SizedBox(height: 10),
      if (supportsNonPersistentSession)
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _rememberDevice,
                visualDensity: VisualDensity.compact,
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _rememberDevice = v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: _loading
                    ? null
                    : () => setState(() => _rememberDevice = !_rememberDevice),
                child: const Text(
                  'Remember this device',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      if (supportsNonPersistentSession)
        const Padding(
          padding: EdgeInsets.only(left: 32, bottom: 4),
          child: Text(
            'Leave this off on a shared or borrowed device — '
            'you will be signed out when the browser closes.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.4),
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          onTap: () => context.push('/forgot-password'),
          child: Text('Forgot password?',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sidebarActiveText)),
        ),
      ),
      const SizedBox(height: 22),
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
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Log In'),
      ),
      const SizedBox(height: 24),
      const Divider(color: Color(0xFFD9D9DB), height: 1),
      const SizedBox(height: 20),
      InkWell(
        onTap: () => context.go('/register'),
        child: Text.rich(
          TextSpan(
            text: "Don't have an account? ",
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF5C5C66)),
            children: [
              TextSpan(
                text: 'Register',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.sidebarActiveText),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
      ],
    );
  }
}
