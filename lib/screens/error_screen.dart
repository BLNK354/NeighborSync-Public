import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/roles.dart';
import '../services/supabase_service.dart';
import '../widgets/community_logo.dart';
import '../widgets/request_error_view.dart';
import '../theme/app_theme.dart';

/// Full-page error, at `/error?code=400&from=/admin/billing`.
///
/// Shown when the server refused a request (unlike [NotFoundScreen], which is
/// for unknown addresses). [from] is where "Try again" goes back to.
class ErrorScreen extends StatelessWidget {
  final String? code;
  final String? from;

  const ErrorScreen({super.key, this.code, this.from});

  /// Finds the right home page for whoever is signed in; '/' if nobody is.
  Future<String> _home() async {
    if (SupabaseService.instance.client.auth.currentSession == null) return '/';
    try {
      final info = await SupabaseService.instance.getRoleAndStatus();
      if (info == null) return '/';
      if (officerRoles.contains(info.role)) return '/admin';
      if (info.status == 'pending_verification') return '/me/profile';
      return '/dashboard';
    } catch (_) {
      return '/';
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = RequestErrorKind.fromCode(code);
    final back = (from ?? '').startsWith('/') ? from! : null;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).height - 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CommunityLogo(
                  size: 48,
                  monogramColor: Colors.white,
                  backgroundColor: AppColors.sidebarActiveText,
                ),
                RequestErrorView(
                  kind: kind,
                  onRetry: kind == RequestErrorKind.unauthorized
                      ? () => context.go('/login')
                      : back == null
                          ? null
                          : () => context.go(back),
                  retryLabel: kind == RequestErrorKind.unauthorized
                      ? 'Sign in'
                      : 'Try again',
                  extra: TextButton(
                    onPressed: () async {
                      final home = await _home();
                      if (context.mounted) context.go(home);
                    },
                    child: const Text('Go to my home page'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
