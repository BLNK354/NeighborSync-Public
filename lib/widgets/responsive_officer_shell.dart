import 'package:flutter/material.dart';
import 'admin_shell.dart';
import 'mobile_admin_shell.dart';

/// Screen width in pixels below which the phone layout is used.
const kMobileBreakpoint = 700.0;

/// Wraps a screen in the desktop sidebar shell or the phone bottom-tab shell,
/// by width. Give it a [desktopChild] and optionally a [mobileChild]; without
/// one, the desktop body is shown inside the phone shell.
class ResponsiveOfficerShell extends StatelessWidget {
  final String title;
  final String activeItem;
  final String activeTab;
  final Widget desktopChild;
  final Widget? mobileChild;

  const ResponsiveOfficerShell({
    super.key,
    required this.title,
    required this.activeItem,
    required this.activeTab,
    required this.desktopChild,
    this.mobileChild,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < kMobileBreakpoint;
    if (isMobile) {
      return MobileAdminShell(
        title: title,
        activeTab: activeTab,
        child: mobileChild ?? desktopChild,
      );
    }
    return AdminShell(title: title, activeItem: activeItem, child: desktopChild);
  }
}
