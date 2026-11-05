import 'package:flutter/material.dart';
import '../core/branding.dart';

/// Colors and shadows for the resident/tenant portal (dark sidebar, shadow
/// cards). Sidebar colors follow the live branding, like [AppColors].
class ResidentColors {
  // Sidebar (dark green)
  static Color get sidebarBg => AppBranding.instance.sidebarColor;
  static const sidebarLogoSub = Color(0xFF9DC3AC); // "Resident Portal"
  static const sidebarSectionLabel = Color(0xFF7FA98F); // "OVERVIEW", etc.
  static const sidebarInactiveText = Color(0xFFC2DBCD);
  static Color get sidebarActiveText => AppBranding.instance.primaryColor;

  // Surfaces
  static const contentBg = Color(0xFFF3F6F4);
  static const border = Color(0xFFE7ECE8);

  // Text
  static const textPrimary = Color(0xFF1B2A22);
  static const textSecondary = Color(0xFF63746A);

  // Text drawn on the portal background; turns white when the background is dark.
  static bool get _portalBgIsDark {
    final b = AppBranding.instance;
    // A photo background is never treated as dark.
    if (b.usePortalPhoto) return false;
    return ThemeData.estimateBrightnessForColor(b.portalBgColor) == Brightness.dark;
  }

  static Color get onPortalPrimary => _portalBgIsDark ? Colors.white : textPrimary;
  static Color get onPortalSecondary => _portalBgIsDark ? const Color(0xE6FFFFFF) : textSecondary;

  // Role badge pill
  static const badgeBg = Color(0xFFE3F1E9);
  static const badgeText = Color(0xFF1A6B43);

  // Stat/quick-action icon tile tints
  static const iconAmberBg = Color(0xFFFBEFD6);
  static const iconAmberText = Color(0xFF8A6300);
  static const iconBlueBg = Color(0xFFE2F0F7);
  static const iconGreenBg = Color(0xFFE3F1E9);
  static const iconGrayBg = Color(0xFFECEFED);

  // Skeleton/placeholder bars (list rows before real content loads)
  static const skeletonDark = Color(0xFFD7DED9);
  static const skeletonLight = Color(0xFFE7ECE8);

  /// Soft two-layer card shadow, same as [AppColors.cardShadow].
  static const cardShadow = [
    BoxShadow(color: Color(0x0F0D2617), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(
      color: Color(0x140D2617),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -6,
    ),
  ];
}
