import 'dart:async';

import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Factor, FactorStatus, AuthMFAEnrollResponse, AuthException;
import '../core/auth_link_timing.dart';
import '../core/roles.dart';
import '../core/text_utils.dart';
import '../core/user_preferences.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../core/refresh_bus.dart';
import '../widgets/auth_screen_scaffold.dart';
import '../core/dialog_controllers.dart';
import '../core/safe_state.dart';

/// Two-factor settings, reached from the Profile screen's Security card.
///
/// Two methods, picked with a switch at the top:
///  - **Authenticator app** -- Supabase's built-in TOTP MFA. Once verified,
///    future logins go through the MFA challenge screen.
///  - **Email code** -- a 6-digit code mailed at each sign-in. Stored as
///    `users.preferences.email_2fa`. Turning it on needs a test code;
///    turning it off needs the current password.
/// When both are on, the authenticator app is used at sign-in.
class MfaSetupScreen extends StatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  State<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends State<MfaSetupScreen> with SafeSetState<MfaSetupScreen> {
  bool _loading = true;
  Factor? _verifiedFactor;
  AuthMFAEnrollResponse? _enrollment;
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _success;

  // ---- email code ----
  /// 'app' or 'email' -- which method's panel is showing.
  String _method = 'app';
  bool _emailOn = false;
  bool _emailCodeSent = false;
  bool _emailBusy = false;
  String? _myEmail;
  int? _myUserId;
  final _emailCodeCtrl = TextEditingController();
  /// When the last test code was sent; resend is locked for kEmailCodeResendCooldown.
  DateTime? _emailSentAt;
  Timer? _ticker;

  Duration get _emailCooldownLeft {
    final at = _emailSentAt;
    if (at == null) return Duration.zero;
    final left = kEmailCodeResendCooldown - DateTime.now().difference(at);
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _emailCodeCtrl.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  /// Loads current two-factor status, or starts app enrollment if none.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await readMyPreferences();
      _emailOn = prefs['email_2fa'] == true;
      _myEmail = SupabaseService.instance.client.auth.currentUser?.email;
      _myUserId = await SupabaseService.instance.getMyUserId();
      final factors = await SupabaseService.instance.listMfaFactors();
      final verified = factors.where((f) => f.status == FactorStatus.verified).toList();
      // Open on the email panel only if it is the only method on.
      if (verified.isEmpty && _emailOn) _method = 'email';
      if (verified.isNotEmpty) {
        setState(() {
          _verifiedFactor = verified.first;
          _enrollment = null;
          _loading = false;
        });
      } else {
        await _startEnrollment();
      }
    } catch (e) {
      setState(() {
        _error = 'Could not load two-factor status. ${friendlyError(e)}';
        _loading = false;
      });
    }
  }

  /// Requests a new authenticator QR code and secret.
  Future<void> _startEnrollment() async {
    try {
      final resp = await SupabaseService.instance.enrollTotp();
      if (!mounted) return;
      setState(() {
        _enrollment = resp;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not start enrollment. ${friendlyError(e)}';
        _loading = false;
      });
    }
  }

  /// Confirms the app code and turns the authenticator on.
  Future<void> _verify(String code) async {
    // Unfocus first or a focused code box trips "_dependents.isEmpty".
    FocusManager.instance.primaryFocus?.unfocus();
    if (_enrollment == null || code.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.instance
          .verifyMfaCodeForFactor(factorId: _enrollment!.id, code: code);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _success = 'Two-factor authentication is now enabled.';
      });
      await _load();
    } catch (e) {
      _codeCtrl.clear();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "That code didn't match -- try again.";
      });
    }
  }

  /// Asks for a current authenticator code. Supabase only removes the app
  /// from a sign-in that passed it (AAL2). False if cancelled or wrong.
  Future<bool> _stepUpWithAuthenticator(Factor factor) async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm with your authenticator app'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To remove the authenticator app, enter the 6-digit code it '
              'shows right now.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            Pinput(
              length: 6,
              controller: ctrl,
              autofocus: true,
              // Unfocus, then close next frame; closing inside the callback
              // trips "_dependents.isEmpty".
              onCompleted: (v) {
                FocusManager.instance.primaryFocus?.unfocus();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (Navigator.of(ctx).canPop()) Navigator.pop(ctx, v);
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Confirm')),
        ],
      ),
    );
    disposeAfterDialogCloses([ctrl]);
    if (code == null || code.length != 6) return false;
    try {
      await SupabaseService.instance
          .verifyMfaCodeForFactor(factorId: factor.id, code: code);
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = "That code didn't match -- try again.");
      return false;
    }
  }

  /// Removes the authenticator app, asking for a code first if needed.
  Future<void> _remove() async {
    final factor = _verifiedFactor;
    if (factor == null) return;
    if (!SupabaseService.instance.passedAuthenticator) {
      final ok = await _stepUpWithAuthenticator(factor);
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.unenrollMfa(factor.id);
      if (!mounted) return;
      setState(() {
        _verifiedFactor = null;
        _busy = false;
        // Say what is still on, so it is clear only one method was removed.
        _success = _emailOn
            ? 'Authenticator app removed. Email codes are still on and will be used at sign-in.'
            : 'Authenticator app removed. Sign-in now needs only your password.';
      });
      await _startEnrollment();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not remove. ${friendlyError(e)}';
      });
    }
  }

  /// Goes back, or to the user's own home when there is nothing to pop.
  Future<void> _leave() async {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Officers must go to /admin, not the resident dashboard.
    final info = await SupabaseService.instance.getRoleAndStatus();
    if (!mounted) return;
    if (info != null && officerRoles.contains(info.role)) {
      context.go('/admin');
    } else if (info?.status == 'pending_verification') {
      context.go('/me/profile');
    } else {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScreenScaffold(
      maxContentWidth: 420,
      children: [
        _loading
            ? const Center(child: CircularProgressIndicator())
            : _body(context),
      ],
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Two-factor authentication',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'app',
                icon: Icon(Icons.phonelink_lock_outlined, size: 16),
                label: Text('Authenticator app')),
            ButtonSegment(
                value: 'email',
                icon: Icon(Icons.mark_email_read_outlined, size: 16),
                label: Text('Email code')),
          ],
          selected: {_method},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() {
            _method = v.first;
            _error = null;
            _success = null;
          }),
        ),
        const SizedBox(height: 16),
        Text(
          _method == 'email'
              ? 'Get a 6-digit code by email every time you sign in.'
              : _verifiedFactor != null
                  ? 'Your account is protected with an authenticator app.'
                  : 'Scan this QR code with your authenticator app.',
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
        if (_success != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.badgeGreenBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: AppColors.sidebarActiveText, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_success!,
                        style: TextStyle(fontSize: 12.5, color: AppColors.sidebarActiveText)),
                  ),
                ],
              ),
            ),
          ),
        if (_method == 'email')
          ..._emailState()
        else if (_verifiedFactor != null)
          ..._enabledState()
        else
          ..._enrollState(),
      ],
    );
  }

  // ---------------------------------------------------------------- email

  /// Emails a test code to the user's own address.
  Future<void> _sendEmailTestCode() async {
    final email = _myEmail;
    if (email == null || _emailCooldownLeft > Duration.zero) return;
    setState(() {
      _emailBusy = true;
      _error = null;
      _success = null;
    });
    try {
      await SupabaseService.instance.sendEmailLoginCode(email);
      if (!mounted) return;
      setState(() {
        _emailBusy = false;
        _emailCodeSent = true;
        _emailSentAt = DateTime.now();
      });
      // Repaint the countdown each second until resend unlocks.
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() {});
        if (_emailCooldownLeft == Duration.zero) t.cancel();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _emailBusy = false;
        // Show the server's message; it explains the rate limit.
        _error = e is AuthException ? e.message : 'Could not send the code. ${friendlyError(e)}';
      });
    }
  }

  /// Checks the emailed code and turns email codes on.
  Future<void> _confirmEmailCode(String code) async {
    // Unfocus first or a focused code box trips "_dependents.isEmpty".
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _myEmail;
    final uid = _myUserId;
    if (email == null || uid == null || code.trim().length != 6 || _emailBusy) return;
    setState(() {
      _emailBusy = true;
      _error = null;
    });
    try {
      // Same check as sign-in, so only a working email can turn this on
      // (otherwise the user could be locked out). Keeps the current session.
      await SupabaseService.instance
          .verifyEmailCodeKeepingSession(email: email, code: code.trim());
      await patchMyPreferences(uid, {'email_2fa': true});
      if (!mounted) return;
      setState(() {
        _emailBusy = false;
        _emailOn = true;
        _emailCodeSent = false;
        _success = 'Email sign-in codes are now on.';
      });
    } catch (e) {
      _emailCodeCtrl.clear();
      if (!mounted) return;
      setState(() {
        _emailBusy = false;
        _error = "That code didn't match or has expired. Try again or send a new one.";
      });
    }
  }

  /// Turns email codes off after the user confirms their password.
  Future<void> _turnEmailOff() async {
    final uid = _myUserId;
    if (uid == null) return;
    final pwCtrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off email codes?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter your password to confirm.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: pwCtrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Current password'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, pwCtrl.text),
              child: const Text('Turn Off')),
        ],
      ),
    );
    disposeAfterDialogCloses([pwCtrl]);
    if (password == null || password.isEmpty) return;
    setState(() {
      _emailBusy = true;
      _error = null;
      _success = null;
    });
    try {
      await SupabaseService.instance.verifyCurrentPassword(password);
      await patchMyPreferences(uid, {'email_2fa': null});
      if (!mounted) return;
      setState(() {
        _emailBusy = false;
        _emailOn = false;
        _success = _verifiedFactor != null
            ? 'Email codes turned off. Your authenticator app is still on.'
            : 'Email codes turned off. Sign-in now needs only your password.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _emailBusy = false;
        _error = e is String ? e : 'Could not turn it off. ${friendlyError(e)}';
      });
    }
  }

  /// Email-code panel.
  List<Widget> _emailState() {
    final masked = _myEmail == null ? 'your email' : maskEmail(_myEmail!);
    return [
      Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
            color: _emailOn ? AppColors.badgeGreenBg : const Color(0xFFF3F6F4),
            shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(Icons.mark_email_read_outlined,
            color: _emailOn ? AppColors.sidebarActiveText : AppColors.textMuted, size: 40),
      ),
      const SizedBox(height: 16),
      Text(
        _emailOn
            ? 'On. Each sign-in sends a code to $masked.'
            : 'Off. Turn it on and each sign-in will send a code to $masked.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      ),
      if (_verifiedFactor != null) ...[
        const SizedBox(height: 8),
        const Text(
          'You also have an authenticator app set up. While it is, sign-in asks '
          'for the app code instead of an email code.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
      const SizedBox(height: 22),
      if (_emailOn)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _emailBusy ? null : _turnEmailOff,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFA82F2F),
              side: const BorderSide(color: Color(0xFFF3C6C6)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_emailBusy ? 'Turning off...' : 'Turn Off Email Codes'),
          ),
        )
      else if (!_emailCodeSent)
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _emailBusy ? null : _sendEmailTestCode,
            child: Text(_emailBusy ? 'Sending...' : 'Send a Test Code'),
          ),
        )
      else ...[
        Text('Enter the code we just sent to $masked',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        Pinput(
          length: 6,
          controller: _emailCodeCtrl,
          enabled: !_emailBusy,
          onCompleted: _confirmEmailCode,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _emailBusy ? null : () => _confirmEmailCode(_emailCodeCtrl.text.trim()),
            child: _emailBusy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Verify & Turn On'),
          ),
        ),
        TextButton(
          onPressed: (_emailBusy || _emailCooldownLeft > Duration.zero) ? null : _sendEmailTestCode,
          child: Text(_emailCooldownLeft > Duration.zero
              ? 'Send another code in ${formatCountdown(_emailCooldownLeft)}'
              : 'Send another code'),
        ),
        const Text(
          "Didn't get it? Check spam. A new code can be sent every 3 minutes.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
      const SizedBox(height: 16),
      InkWell(
        onTap: _leave,
        child: Text('Done',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.sidebarActiveText)),
      ),
    ];
  }

  /// Authenticator panel when the app is already on.
  List<Widget> _enabledState() {
    return [
      Container(
        width: 96,
        height: 96,
        decoration: const BoxDecoration(color: AppColors.badgeGreenBg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(Icons.verified_user_outlined, color: AppColors.sidebarActiveText, size: 40),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _busy ? null : _remove,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFA82F2F),
            side: const BorderSide(color: Color(0xFFF3C6C6)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(_busy ? 'Removing...' : 'Remove Two-Factor Auth'),
        ),
      ),
      const SizedBox(height: 16),
      InkWell(
        onTap: _leave,
        child: Text('Done',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.sidebarActiveText)),
      ),
    ];
  }

  /// Authenticator panel with the QR code and 6-digit entry.
  List<Widget> _enrollState() {
    final totp = _enrollment?.totp;
    return [
      Container(
        width: 168,
        height: 168,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD3DCD6), width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: totp == null
            ? const Center(child: Text('QR unavailable', style: TextStyle(fontSize: 11)))
            : SvgPicture.string(totp.qrCode),
      ),
      const SizedBox(height: 16),
      if (totp != null)
        SelectableText(totp.secret,
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textMuted, letterSpacing: 0.5)),
      const SizedBox(height: 24),
      const Text('Enter the 6-digit code',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
      const SizedBox(height: 12),
      Pinput(
        length: 6,
        controller: _codeCtrl,
        enabled: !_busy,
        onCompleted: _verify,
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _busy ? null : () => _verify(_codeCtrl.text.trim()),
          child: _busy
              ? const SizedBox(
                  height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Verify & Enable'),
        ),
      ),
      const SizedBox(height: 16),
      InkWell(
        onTap: _leave,
        child: const Text('Skip for now',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      ),
    ];
  }
}
