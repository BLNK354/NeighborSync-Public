import '../core/app_locale.dart' show tr;
import 'package:flutter/material.dart';
import '../core/text_utils.dart';
import '../theme/app_theme.dart';

/// Small colored pill for a status, priority or severity word. The color
/// is picked from the word itself; unknown words show grey.
class StatusBadge extends StatelessWidget {
  final String value;
  const StatusBadge(this.value, {super.key});

  static const _green = {
    'active', 'approved', 'paid', 'verified', 'published', 'resolved',
    'completed', 'going', 'upheld', 'owned', 'occupied', 'info', 'used',
    'on-site', 'ongoing', 'registered',
  };
  static const _amber = {
    'pending', 'pending_verification', 'submitted', 'draft', 'open',
    'scheduled', 'under_review', 'partial', 'investigating', 'reported',
    'noticed', 'unpaid', 'in_progress', 'medium', 'warning', 'vacant',
    'upcoming', 'expiring',
  };
  static const _red = {
    'suspended', 'rejected', 'overdue', 'cancelled', 'dismissed',
    'inactive', 'expired', 'revoked', 'critical', 'high', 'urgent',
    'escalated', 'contested', 'flagged',
  };
  static const _gray = {
    'closed', 'archived', 'waived', 'not_going', 'low', 'normal', 'departed',
    'sold',
    // Roster record nobody has claimed yet; grey because nothing is waiting.
    'imported',
  };

  @override
  Widget build(BuildContext context) {
    final v = value.toLowerCase().trim();
    Color bg;
    Color fg;
    if (_green.contains(v)) {
      bg = const Color(0xFFE3F1E9);
      fg = const Color(0xFF14532D);
    } else if (_amber.contains(v)) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
    } else if (_red.contains(v)) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFF991B1B);
    } else if (_gray.contains(v)) {
      bg = AppColors.highlight;
      fg = AppColors.textSecondary;
    } else {
      bg = AppColors.highlight;
      fg = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        tr(titleCase(value)),
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
