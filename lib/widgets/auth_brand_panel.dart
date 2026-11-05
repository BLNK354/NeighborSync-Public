import 'package:flutter/material.dart';
import '../core/branding.dart';
import '../theme/app_theme.dart';
import 'community_logo.dart';

/// Green side panel for Login and Register with the logo, community name
/// and an optional description. Callers hide it on narrow windows.
/// Logo and name come from [AppBranding].
class AuthBrandPanel extends StatelessWidget {
  final String? description;
  const AuthBrandPanel({super.key, this.description});

  @override
  Widget build(BuildContext context) {
    final branding = AppBranding.instance;
    return Container(
      width: 480,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.sidebarBg, const Color(0xFF0C3620)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: CommunityLogo(size: 76, monogramColor: AppColors.sidebarActiveText),
          ),
          const SizedBox(height: 28),
          Text(branding.communityName,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 6),
          Text('NeighborSync HOA Platform',
              style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.85))),
          if (description != null) ...[
            const SizedBox(height: 24),
            Text(description!,
                style: TextStyle(
                    fontSize: 13.5, height: 1.5, color: Colors.white.withValues(alpha: 0.75))),
          ],
        ],
      ),
    );
  }
}
