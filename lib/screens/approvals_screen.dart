import 'package:flutter/material.dart';
import '../widgets/pending_approvals_view.dart';
import '../widgets/responsive_officer_shell.dart';

/// Standalone "User Approvals" page. It only wraps [PendingApprovalsView],
/// which is also a tab on the All Accounts screen.
class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveOfficerShell(
      title: 'User Approvals',
      activeItem: 'All Accounts',
      activeTab: 'Home',
      desktopChild: PendingApprovalsView(),
      mobileChild: PendingApprovalsView(),
    );
  }
}
