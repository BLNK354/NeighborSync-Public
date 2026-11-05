import '../core/app_locale.dart' show tr;
import 'package:flutter/material.dart';
import '../core/branding.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'profile_avatar.dart';
import '../core/safe_state.dart';

/// Shared pieces of the phone slide-in menu: header, section label, rows,
/// and the Log Out row.

const Color _logoutRed = Color(0xFFA82F2F);

/// Friendly display name for a role key.
String roleDisplayName(String? role) {
  switch (role) {
    case 'super_admin':
      return 'Super Administrator';
    case 'hoa_president':
      return 'HOA President';
    case 'treasurer':
      return 'Treasurer';
    case 'secretary':
      return 'Secretary';
    case 'audit_officer':
      return 'Audit Officer';
    case 'security':
      return 'Security Personnel';
    case 'member_resident':
      return 'Member-Resident';
    case 'tenant':
      return 'Tenant';
    default:
      return (role == null || role.isEmpty) ? 'Member' : role;
  }
}

/// Menu header showing the signed-in name and role; it loads them itself.
/// [fallbackRoleLabel] shows until the role loads.
class MobileMenuHeader extends StatefulWidget {
  final VoidCallback onClose;
  final String? fallbackRoleLabel;
  const MobileMenuHeader({super.key, required this.onClose, this.fallbackRoleLabel});

  @override
  State<MobileMenuHeader> createState() => _MobileMenuHeaderState();
}

class _MobileMenuHeaderState extends State<MobileMenuHeader> with SafeSetState<MobileMenuHeader> {
  String _name = '';
  String? _role;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await SupabaseService.instance.getMyProfile();
    final role = await SupabaseService.instance.getMyRole();
    if (!mounted) return;
    final first = (profile?['first_name'] ?? '').toString().trim();
    final last = (profile?['last_name'] ?? '').toString().trim();
    setState(() {
      _name = [first, last].where((s) => s.isNotEmpty).join(' ');
      _role = role;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.isNotEmpty ? _name : AppBranding.instance.communityName;
    final roleLabel = _role != null ? roleDisplayName(_role) : (widget.fallbackRoleLabel ?? '');
    return Container(
      width: double.infinity,
      color: AppBranding.instance.sidebarColor,
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 18),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            ProfileAvatar(
              radius: 22,
              background: Colors.white,
              iconColor: AppBranding.instance.sidebarColor,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                  if (roleLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(roleLabel, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, color: Colors.white, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grey uppercase section heading (COMMUNITY / MY REQUESTS / ACCOUNT ...).
class MobileMenuSectionLabel extends StatelessWidget {
  final String label;
  const MobileMenuSectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(tr(label),
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.textMuted)),
    );
  }
}

/// One flat menu row: green outline icon, label, and a trailing chevron.
class MobileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const MobileMenuTile({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppBranding.instance.primaryColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(tr(label),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, color: AppColors.textPrimary)),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Red "Log Out" row with a divider above it.
class MobileMenuLogout extends StatelessWidget {
  final VoidCallback onTap;
  const MobileMenuLogout({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppColors.border),
        InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              children: [
                Icon(Icons.logout, size: 20, color: _logoutRed),
                SizedBox(width: 16),
                Text('Log Out',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _logoutRed)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
