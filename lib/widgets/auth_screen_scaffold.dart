import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/branding.dart';
import '../theme/app_theme.dart';
import 'auth_brand_panel.dart';
import 'centered_scroll_form.dart';
import 'community_logo.dart';

/// Shared layout for every signed-out screen: login, register, forgot /
/// reset password, verify email and both MFA screens.
///
/// Wide: branded panel on the left, form on the right.
/// Narrow: centred logo and community name above the form.
class AuthScreenScaffold extends StatelessWidget {
  /// The form content, laid out in a Column. Plain `Text` and
  /// `TextFormField` children work as they are.
  final List<Widget> children;

  /// Shown under the wordmark on the wide brand panel. Login only.
  final String? brandDescription;

  /// Screen width at which the brand panel appears.
  final double brandPanelBreakpoint;

  /// Widest the form column may get.
  final double maxContentWidth;

  /// Shows a way back to the public landing page.
  final bool showBackToHome;

  /// Wraps the content in a [Form] when given. Callers must not add their
  /// own Form with the same key.
  final GlobalKey<FormState>? formKey;

  /// Stretch fields (default) or centre content, as on verify and MFA screens.
  final CrossAxisAlignment crossAxisAlignment;

  const AuthScreenScaffold({
    super.key,
    required this.children,
    this.brandDescription,
    this.brandPanelBreakpoint = 900,
    this.maxContentWidth = 380,
    this.showBackToHome = false,
    this.formKey,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= brandPanelBreakpoint;
          return Row(
            children: [
              if (wide) AuthBrandPanel(description: brandDescription),
              // Keep CenteredScrollForm: Center(SingleChildScrollView) puts
              // the scrollbar mid-page. It also adds keyboard room itself.
              Expanded(
                child: CenteredScrollForm(
                  maxWidth: maxContentWidth,
                  padding: EdgeInsets.fromLTRB(
                    wide ? 32 : 24,
                    wide ? 40 : 28,
                    wide ? 32 : 24,
                    40,
                  ),
                  child: _touchSized(
                    context,
                    narrow: !wide,
                    child: _maybeForm(
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: crossAxisAlignment,
                        children: [
                          if (showBackToHome) _backControl(context, wide),
                          if (!wide) ...[
                            const _MobileBrandHeader(),
                            const SizedBox(height: 26),
                          ] else if (showBackToHome)
                            const SizedBox(height: 12),
                          ...children,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Wraps in a Form that re-validates as the person types.
  Widget _maybeForm(Widget child) => formKey == null
      ? child
      : Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: child,
        );

  /// Wide: labelled "Back to Home" button. Narrow: a bare arrow.
  Widget _backControl(BuildContext context, bool wide) {
    if (wide) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => context.go('/'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back to Home'),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        onPressed: () => context.go('/'),
        tooltip: 'Back to Home',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: const Icon(Icons.arrow_back, size: 20, color: AppColors.textMuted),
      ),
    );
  }

  /// Makes fields and buttons larger on narrow (touch) screens.
  Widget _touchSized(BuildContext context,
      {required bool narrow, required Widget child}) {
    if (!narrow) return child;
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
            minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)),
            textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (base.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(
            minimumSize: WidgetStateProperty.all(const Size.fromHeight(48)),
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Logo + community name, centred, on the plain background.
class _MobileBrandHeader extends StatelessWidget {
  const _MobileBrandHeader();

  @override
  Widget build(BuildContext context) {
    final branding = AppBranding.instance;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: AppColors.badgeGreenBg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: CommunityLogo(size: 56, monogramColor: AppColors.sidebarActiveText),
        ),
        const SizedBox(height: 14),
        Text(
          branding.communityName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'NeighborSync HOA Platform',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
