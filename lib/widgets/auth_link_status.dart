import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth_link_timing.dart';
import '../core/form_helpers.dart';
import '../core/text_utils.dart';
import '../theme/app_theme.dart';
import '../core/safe_state.dart';

/// Shows "We sent a link to na****@example.com", an expiry countdown and a
/// Resend button that stays disabled until the server would accept a resend.
///
/// Used by Forgot Password and Verify Email; each passes its own message
/// and resend call.
///
/// Limit: the countdown starts when this widget is created (or [sentAt]),
/// so a page reload restarts it while the real link keeps ageing.
class AuthLinkStatus extends StatefulWidget {
  const AuthLinkStatus({
    super.key,
    required this.email,
    required this.message,
    required this.onResend,
    required this.resendLabel,
    this.sentAt,
  });

  /// The raw address. Masked here, so callers must not mask it first.
  final String email;

  /// Builds the message from the masked address, never the real one.
  final String Function(String maskedEmail) message;

  /// Sends another link. Throw to report failure; the message shows under the button.
  final Future<void> Function() onResend;

  /// Button text, e.g. 'Resend reset link'.
  final String resendLabel;

  /// When the link went out, if known. Null means now.
  final DateTime? sentAt;

  @override
  State<AuthLinkStatus> createState() => _AuthLinkStatusState();
}

class _AuthLinkStatusState extends State<AuthLinkStatus> with SafeSetState<AuthLinkStatus> {
  late DateTime _sentAt;
  Timer? _tick;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sentAt = widget.sentAt ?? DateTime.now();
    _startTicking();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _startTicking() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Stop ticking once the link is expired and the cooldown is over.
      if (_expired && _cooldownLeft <= Duration.zero) {
        _tick?.cancel();
        _tick = null;
      }
      setState(() {});
    });
  }

  /// Time left, computed from the clock each tick (a counter would drift
  /// or freeze while the tab is in the background).
  Duration get _validFor => kAuthLinkValidity - DateTime.now().difference(_sentAt);
  Duration get _cooldownLeft =>
      kAuthResendCooldown - DateTime.now().difference(_sentAt);

  bool get _expired => _validFor <= Duration.zero;
  bool get _coolingDown => _cooldownLeft > Duration.zero;

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await widget.onResend();
      if (!mounted) return;
      setState(() => _sentAt = DateTime.now());
      _startTicking(); // it may have stopped itself after expiry
    } catch (e) {
      if (mounted) setState(() => _error = _resendError(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// Shows the server's own message for auth errors (e.g. "wait N seconds");
  /// `friendlyError` would turn it into a generic one.
  String _resendError(Object e) {
    if (e is AuthException && e.message.trim().isNotEmpty) return e.message;
    return friendlyError(e);
  }

  @override
  Widget build(BuildContext context) {
    final masked = maskEmail(widget.email);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _expired ? AppColors.badgeAmberBg : AppColors.badgeGreenBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _expired
                        ? Icons.schedule_outlined
                        : Icons.check_circle_outline,
                    size: 20,
                    color: _expired
                        ? AppColors.badgeAmberText
                        : AppColors.sidebarActiveText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.message(masked),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: _expired
                            ? AppColors.badgeAmberText
                            : AppColors.sidebarActiveText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                // Line the countdown up under the text, not under the icon.
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  _expired
                      ? 'That link has expired. Send another one below.'
                      : 'The link expires in ${formatCountdown(_validFor)}, '
                          'and works once.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: _expired
                        ? AppColors.badgeAmberText
                        : AppColors.sidebarActiveText,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          // Disabled during the cooldown because the server would refuse.
          onPressed: (_resending || _coolingDown) ? null : _resend,
          child: _resending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_coolingDown
                  ? 'Resend in ${formatCountdown(_cooldownLeft)}'
                  : widget.resendLabel),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}
