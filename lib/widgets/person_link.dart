import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

/// A person's name that opens their page at `/admin/people/:id`.
///
/// Pass [enabled] false when the officer lacks `accounts:read`; the name then
/// shows as plain text, because the router would bounce them back.
class PersonNameLink extends StatelessWidget {
  final Object? userId;
  final String name;
  final bool enabled;
  final TextStyle? style;

  /// `users.account_label` ('test' / 'evaluation'), shown as a small tag.
  final Object? accountLabel;

  const PersonNameLink({
    super.key,
    required this.userId,
    required this.name,
    required this.enabled,
    this.style,
    this.accountLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = name.trim().isEmpty ? '—' : name.trim();
    final live = enabled && userId != null && label != '—';
    final textStyle = live
        ? (style ?? const TextStyle()).copyWith(
            color: AppColors.sidebarActiveText,
            fontWeight: FontWeight.w600,
          )
        : style;
    // Text.rich, not a Row, so it truncates in an Expanded and fits a table cell.
    final text = Text.rich(
      TextSpan(children: [
        TextSpan(text: label),
        if (accountLabelText(accountLabel) != null)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: AccountLabelChip(accountLabel),
            ),
          ),
      ]),
      style: textStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!live) return text;
    return InkWell(
      onTap: () => context.go('/admin/people/$userId'),
      borderRadius: BorderRadius.circular(4),
      child: text,
    );
  }
}

/// "Test" / "Evaluation" for a `users.account_label`, or null for a real
/// account.
String? accountLabelText(Object? label) => switch (label) {
      'test' => 'Test',
      'evaluation' => 'Evaluation',
      _ => null,
    };

/// The small tag marking a test or evaluation account.
class AccountLabelChip extends StatelessWidget {
  final Object? label;
  const AccountLabelChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final text = accountLabelText(label);
    if (text == null) return const SizedBox.shrink();
    final eval = label == 'evaluation';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: eval ? AppColors.badgeBlueBg : AppColors.badgeAmberBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: eval ? AppColors.badgeBlueText : AppColors.badgeAmberText)),
    );
  }
}
