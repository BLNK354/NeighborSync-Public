import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/branding.dart';
import '../core/roles.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/centered_scroll_form.dart';
import '../widgets/community_logo.dart';
import '../core/safe_state.dart';

/// Shown for any URL that matches no route.
///
/// Needed because the host sends every path to the app, so bad links reach
/// the router instead of a server 404. The back button goes to the
/// signed-in person's own home, not always `/`.
class NotFoundScreen extends StatefulWidget {
  /// The path that matched nothing, shown so a mistyped link is easy to spot.
  final String? attemptedPath;

  const NotFoundScreen({super.key, this.attemptedPath});

  @override
  State<NotFoundScreen> createState() => _NotFoundScreenState();
}

class _NotFoundScreenState extends State<NotFoundScreen> with SafeSetState<NotFoundScreen> {
  String _home = '/';
  String _homeLabel = 'Go to the home page';

  @override
  void initState() {
    super.initState();
    _resolveHome();
  }

  /// Picks where the back button goes, like the router's redirect. If the
  /// lookup fails it keeps the public home page.
  Future<void> _resolveHome() async {
    final session = SupabaseService.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      final info = await SupabaseService.instance.getRoleAndStatus();
      if (info == null || !mounted) return;
      setState(() {
        if (officerRoles.contains(info.role)) {
          _home = '/admin';
          _homeLabel = 'Back to the officers portal';
        } else if (info.status == 'pending_verification') {
          // Pending residents have no dashboard; Profile is where they finish.
          _home = '/me/profile';
          _homeLabel = 'Back to your profile';
        } else {
          _home = '/dashboard';
          _homeLabel = 'Back to my dashboard';
        }
      });
    } catch (_) {
      // Keep the default home button.
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // Not Center + SingleChildScrollView: the scrollbar would sit at the
        // edge of the shrunken box, not the window.
        child: CenteredScrollForm(
          maxWidth: 460,
          padding: EdgeInsets.symmetric(horizontal: narrow ? 24 : 40, vertical: 32),
              child: ListenableBuilder(
                listenable: AppBranding.instance,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CommunityLogo(
                      size: 56,
                      monogramColor: Colors.white,
                      backgroundColor: AppColors.sidebarActiveText,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'That page does not exist',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: narrow ? 20 : 23,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'The link may be mistyped, or it may point at a page that '
                      'has since moved. Nothing is wrong with your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13.5, height: 1.55, color: AppColors.textMuted),
                    ),
                    if ((widget.attemptedPath ?? '').isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F6F5),
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          widget.attemptedPath!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontFamily: 'monospace',
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => context.go(_home),
                        child: Text(_homeLabel),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Open the community home page'),
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }
}
