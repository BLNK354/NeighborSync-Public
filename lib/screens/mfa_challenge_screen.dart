import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Factor, FactorStatus;
import '../core/roles.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../core/refresh_bus.dart';
import '../widgets/auth_screen_scaffold.dart';
import '../core/safe_state.dart';

/// Asks for the 6-digit authenticator code right after password sign-in.
/// It cannot be skipped.
class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({super.key});

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> with SafeSetState<MfaChallengeScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = true;
  bool _verifying = false;
  String? _error;
  Factor? _factor;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final factors = await SupabaseService.instance.listMfaFactors();
      final verified = factors.where((f) => f.status == FactorStatus.verified);
      setState(() {
        _factor = verified.isEmpty ? null : verified.first;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load your authenticator. ${friendlyError(e)}';
        _loading = false;
      });
    }
  }

  Future<void> _verify(String code) async {
    // Drop focus first: navigating away with the code box focused throws an assertion.
    FocusManager.instance.primaryFocus?.unfocus();
    if (_factor == null || code.trim().length != 6) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await SupabaseService.instance
          .verifyMfaCodeForFactor(factorId: _factor!.id, code: code.trim());
      if (!mounted) return;
      final info = await SupabaseService.instance.getRoleAndStatus();
      if (!mounted) return;
      if (info != null && officerRoles.contains(info.role)) {
        context.go('/admin');
      } else if (info?.status == 'pending_verification') {
        // Not yet approved: send them to Profile to fill in their address.
        context.go('/me/profile');
      } else {
        context.go('/dashboard');
      }
    } catch (e) {
      _codeCtrl.clear();
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = "That code didn't match -- try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return AuthScreenScaffold(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
      Text('Enter your authentication code',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      const Text(
        'Open your authenticator app and enter the 6-digit code '
        'for NeighborSync.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
      ),
      const SizedBox(height: 28),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
        ),
      Pinput(
        length: 6,
        controller: _codeCtrl,
        enabled: !_verifying && _factor != null,
        onCompleted: _verify,
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: (_verifying || _factor == null)
              ? null
              : () => _verify(_codeCtrl.text.trim()),
          child: _verifying
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Verify'),
        ),
      ),
      const SizedBox(height: 20),
      InkWell(
        onTap: () async {
          await SupabaseService.instance.signOut();
          if (context.mounted) context.go('/login');
        },
        child: Text('Sign out',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.sidebarActiveText)),
      ),
      ],
    );
  }
}
