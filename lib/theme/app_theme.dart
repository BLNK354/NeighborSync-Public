import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/branding.dart';

/// Shrinks buttons for phone-width screens.
///
/// The default buttons are desktop-sized and clip toolbars on a narrow phone.
/// Apply once around a phone shell's body so every screen inside inherits it.
ThemeData compactButtonTheme(ThemeData base) {
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStatePropertyAll(
            (base.textTheme.labelLarge ?? const TextStyle())
                .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 7)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStatePropertyAll(
            (base.textTheme.labelLarge ?? const TextStyle())
                .copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

/// Colour and shadow tokens shared by the officer and resident portals.
class AppColors {
  // Sidebar colours. The getters read the saved branding, so screens
  // re-theme as soon as it changes. Don't use them inside a const.
  static Color get sidebarBg => AppBranding.instance.sidebarColor;
  static const sidebarLogoSub = Color(0xFF9DC3AC);      // "HOA Officers Portal"
  static const sidebarSectionLabel = Color(0xFF7FA98F); // "OVERVIEW", etc.
  static const sidebarInactiveText = Color(0xFFC2DBCD);
  static Color get sidebarActiveText => AppBranding.instance.primaryColor;

  // Core neutrals
  static const textPrimary = Color(0xFF1B2A22);   // headings
  static const textSecondary = Color(0xFF63746A); // nav items, body
  static const textMuted = Color(0xFF63746A);      // section labels, hints

  // Text drawn directly on the portal background turns white when the
  // background colour is dark. Photos count as light (they have a white scrim).
  static bool get portalBgIsDark {
    final b = AppBranding.instance;
    // A photo in use means light.
    if (b.usePortalPhoto) return false;
    return ThemeData.estimateBrightnessForColor(b.portalBgColor) == Brightness.dark;
  }

  static Color get onPortalPrimary => portalBgIsDark ? Colors.white : textPrimary;
  static Color get onPortalSecondary => portalBgIsDark ? const Color(0xE6FFFFFF) : textSecondary;
  static Color get onPortalMuted => portalBgIsDark ? const Color(0xCCFFFFFF) : textMuted;

  // Same idea for the home page's lower "About" section.
  static bool get homeBodyIsDark {
    final b = AppBranding.instance;
    // Only a photo that is switched on counts; an unused upload must not.
    if (b.useHomeBodyPhoto) return false;
    return ThemeData.estimateBrightnessForColor(b.homeBodyColor) == Brightness.dark;
  }

  static Color get onHomeBodyPrimary => homeBodyIsDark ? Colors.white : textPrimary;
  static Color get onHomeBodySecondary => homeBodyIsDark ? const Color(0xE6FFFFFF) : textSecondary;
  static const contentBg = Color(0xFFF3F6F4);
  static const border = Color(0xFFE7ECE8);
  static const highlight = Color(0xFFECEFED);      // active nav, placeholders

  // Border for form controls. Kept darker than `border` so field edges stay
  // visible against white.
  static const inputBorder = Color(0xFF7D8C83);
  static const errorRed = Color(0xFFA82F2F);
  static const errorRedBg = Color(0xFFFBE4E4);
  static const errorRedBorder = Color(0xFFF3C6C6);

  /// Soft two-layer card shadow.
  static const cardShadow = [
    BoxShadow(color: Color(0x0F0D2617), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(
      color: Color(0x140D2617),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -6,
    ),
  ];

  // Stat/badge tint pairs (bg, text)
  static const badgeGreenBg = Color(0xFFE3F1E9);
  static const badgeGreenText = Color(0xFF1A6B43);
  static const badgeBlueBg = Color(0xFFE2F0F7);
  static const badgeBlueText = Color(0xFF0C5C84);
  static const badgeAmberBg = Color(0xFFFBEFD6);
  static const badgeAmberText = Color(0xFF8A6300);
  static const badgeRedBg = Color(0xFFFBE4E4);
  static const badgeRedText = Color(0xFFA82F2F);
  static const badgeGrayBg = Color(0xFFECEFED);
  static const badgeGrayText = Color(0xFF63746A);

  // ---- Neutral surface tokens ---------------------------------------
  // Getters so call sites don't change if the values ever do. Light theme only.
  /// Card / panel background.
  static Color get surface => Colors.white;

  /// Page/scaffold background behind cards.
  static Color get pageBg => contentBg;

  /// Primary text.
  static Color get textMain => textPrimary;

  /// Secondary/muted text.
  static Color get textSub => textSecondary;

  /// Divider/border.
  static Color get line => border;

  /// Card shadow.
  static List<BoxShadow> get surfaceShadow => cardShadow;
}

/// Page transition with no animation. Each route rebuilds the whole shell,
/// so the default zoom would flash the sidebar.
class _NoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

/// Builds the app's single (light) theme for MaterialApp.
ThemeData buildAppTheme() {
  const surface = Colors.white;
  const pageBg = Colors.white;
  const bodyColor = AppColors.textSecondary;
  const displayColor = AppColors.textPrimary;
  const inputFill = Colors.white;
  const inputBorderColor = AppColors.inputBorder;

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: pageBg,
    canvasColor: surface,
    // Dialog background is set in dialogTheme below.
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.textPrimary,
      brightness: Brightness.light,
      surface: surface,
    ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: bodyColor,
      displayColor: displayColor,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: const BorderSide(color: AppColors.border),
      backgroundColor: surface,
      selectedColor: AppColors.badgeGreenBg,
      labelStyle: GoogleFonts.inter(fontSize: 12.5, color: displayColor),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: AppColors.textSecondary),
      dividerThickness: 0.6,
    ),
    // Style for every scrollbar. Margins can only be set here, not on Scrollbar.
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(8),
      // Faint at rest, firmer on hover and drag.
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) return const Color(0x73000000);
        if (states.contains(WidgetState.hovered)) return const Color(0x59000000);
        return const Color(0x2E000000);
      }),
      crossAxisMargin: 3,
      mainAxisMargin: 6,
      interactive: true,
    ),
    cardColor: surface,
    // Black text cursor so it shows on every field.
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Colors.black,
      selectionColor: Color(0x401A6B43),
      selectionHandleColor: Colors.black,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // All text fields, dropdowns and date inputs use these borders.
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: inputBorderColor, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: inputBorderColor, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.sidebarActiveText, width: 1.8),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: AppColors.errorRed, width: 1.2),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: AppColors.errorRed, width: 1.8),
      ),
      // Bold and wraps up to 4 lines so long messages aren't cut off.
      errorStyle: const TextStyle(
          color: AppColors.errorRed, fontSize: 12.5, fontWeight: FontWeight.w700),
      errorMaxLines: 4,
      hintStyle: const TextStyle(color: bodyColor, fontSize: 13),
      labelStyle: const TextStyle(color: bodyColor, fontSize: 13),
    ),
    // Keeps outlined buttons looking enabled even when onPressed is null
    // (Filter buttons inside a PopupMenuButton).
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: displayColor,
        disabledForegroundColor: displayColor,
        backgroundColor: surface,
        disabledBackgroundColor: surface,
        side: const BorderSide(color: inputBorderColor, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Brand green.
        backgroundColor: AppColors.sidebarActiveText,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        minimumSize: const Size(64, 44),
        textStyle: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoPageTransitionsBuilder(),
        TargetPlatform.iOS: _NoPageTransitionsBuilder(),
        TargetPlatform.linux: _NoPageTransitionsBuilder(),
        TargetPlatform.macOS: _NoPageTransitionsBuilder(),
        TargetPlatform.windows: _NoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: _NoPageTransitionsBuilder(),
      },
    ),
  );
}
