import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'sign_out_confirm.dart';
import 'mobile_menu_ui.dart';

/// One row in a [RoleMobileMenu].
class RoleMenuItem {
  final String label;
  final IconData icon;
  final String route;
  const RoleMenuItem(this.label, this.icon, this.route);
}

/// Phone menu for one officer role: a fixed list of rows plus Log Out.
/// [items] is used as given, not filtered by permissions.
class RoleMobileMenu extends StatelessWidget {
  final String roleLabel;
  final List<RoleMenuItem> items;

  const RoleMobileMenu({super.key, required this.roleLabel, required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          MobileMenuHeader(
            onClose: () => Navigator.of(context).pop(),
            fallbackRoleLabel: roleLabel,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final item in items)
                  MobileMenuTile(
                    icon: item.icon,
                    label: item.label,
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(item.route);
                    },
                  ),
                MobileMenuLogout(
                  onTap: () => signOutWithConfirm(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
