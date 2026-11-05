import 'package:flutter/material.dart';

import '../core/form_helpers.dart';
import '../theme/app_theme.dart';

/// Live feedback for a password and confirm-password pair: a strength bar
/// under the first field and a match note under the second.
///
/// The meter is advice only. [passwordError] is the only check that blocks
/// submitting, so it must keep matching the server password policy.
///
/// Both widgets listen to the text controllers, so just drop them in.

/// How strong a password looks, in four levels.
enum PasswordStrength { weak, fair, good, strong }

/// What the bar is showing, and why.
class PasswordAssessment {
  final PasswordStrength level;

  /// How many of the five rules are met (length plus four character types).
  final int rulesMet;

  /// Shown when every rule is met but the password is still a poor choice.
  final String? caveat;

  const PasswordAssessment(this.level, this.rulesMet, this.caveat);

  /// True once [passwordError] would return null — i.e. this is submittable.
  bool get meetsPolicy => rulesMet == 5;

  String get label => switch (level) {
        PasswordStrength.weak => 'Weak',
        PasswordStrength.fair => 'Fair',
        PasswordStrength.good => 'Good',
        PasswordStrength.strong => 'Strong',
      };

  Color get color => switch (level) {
        PasswordStrength.weak => AppColors.badgeRedText,
        PasswordStrength.fair => AppColors.badgeAmberText,
        PasswordStrength.good => AppColors.badgeBlueText,
        PasswordStrength.strong => AppColors.badgeGreenText,
      };

  /// Segments to fill, out of four.
  int get filledSegments => switch (level) {
        PasswordStrength.weak => 1,
        PasswordStrength.fair => 2,
        PasswordStrength.good => 3,
        PasswordStrength.strong => 4,
      };
}

/// Common guessable words. The list is short on purpose; it is a hint, not
/// real protection.
const _kWeakSequences = <String>[
  'password', 'passw0rd', 'qwerty', 'asdf', 'zxcv',
  '123456', '12345', 'abc123', 'letmein', 'welcome',
  'admin', 'iloveyou', 'monkey', 'dragon', 'neighborsync',
];

/// Scores a password against the same five rules [passwordError] enforces.
PasswordAssessment assessPassword(String value) {
  if (value.isEmpty) return const PasswordAssessment(PasswordStrength.weak, 0, null);

  // Must mirror passwordError(); change both together or the bar and the
  // validator will disagree.
  final rules = <bool>[
    value.length >= kMinPasswordLength,
    RegExp(r'[a-z]').hasMatch(value),
    RegExp(r'[A-Z]').hasMatch(value),
    RegExp(r'\d').hasMatch(value),
    RegExp(r'[^A-Za-z0-9\s]').hasMatch(value),
  ];
  final met = rules.where((r) => r).length;

  // Rules not all met: show at most "Fair", never "Good".
  if (met < 5) {
    return PasswordAssessment(
      met >= 3 ? PasswordStrength.fair : PasswordStrength.weak,
      met,
      null,
    );
  }

  // Plain loop: package:collection is not a dependency.
  final lower = value.toLowerCase();
  for (final weak in _kWeakSequences) {
    if (lower.contains(weak)) {
      return PasswordAssessment(
        PasswordStrength.fair,
        met,
        'Contains "$weak" — a word attackers try first.',
      );
    }
  }

  // Catches one short block repeated, such as "Aa1!Aa1!Aa1!".
  if (RegExp(r'^(.{1,4})\1+$').hasMatch(value)) {
    return const PasswordAssessment(
      PasswordStrength.fair,
      5,
      'Mostly one repeated pattern.',
    );
  }

  // Once all rules are met, length is the only bonus.
  return PasswordAssessment(
    value.length >= 14 ? PasswordStrength.strong : PasswordStrength.good,
    met,
    null,
  );
}

/// Four-segment strength bar with a word. Shows nothing while the field is empty.
class PasswordStrengthBar extends StatelessWidget {
  final TextEditingController controller;

  /// Space above the bar.
  final double topGap;

  const PasswordStrengthBar({
    super.key,
    required this.controller,
    this.topGap = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.text.isEmpty) return const SizedBox.shrink();
        final a = assessPassword(value.text);
        return Padding(
          padding: EdgeInsets.only(top: topGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i < a.filledSegments
                              ? a.color
                              : AppColors.highlight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    if (i < 3) const SizedBox(width: 4),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Password strength: ${a.label}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: a.color,
                ),
              ),
              if (a.caveat != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    a.caveat!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Shows "Passwords match" or "Passwords do not match" under the confirm field.
/// Hidden while the confirm text is still a prefix of the password, so no
/// red error appears mid-typing.
class PasswordMatchNote extends StatelessWidget {
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final double topGap;

  const PasswordMatchNote({
    super.key,
    required this.passwordController,
    required this.confirmController,
    this.topGap = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([passwordController, confirmController]),
      builder: (context, _) {
        final pw = passwordController.text;
        final confirm = confirmController.text;
        if (confirm.isEmpty) return const SizedBox.shrink();

        final matches = confirm == pw;
        final stillTyping = !matches && pw.startsWith(confirm);
        if (stillTyping) return const SizedBox.shrink();

        return Padding(
          padding: EdgeInsets.only(top: topGap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                matches ? Icons.check_circle_outline : Icons.error_outline,
                size: 14,
                color: matches ? AppColors.badgeGreenText : AppColors.errorRed,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  matches ? 'Passwords match' : 'Passwords do not match',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color:
                        matches ? AppColors.badgeGreenText : AppColors.errorRed,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
