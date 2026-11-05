import 'package:flutter/material.dart';
import '../core/branding.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';

/// Read-only Community Rules page for residents. Shows the text officers
/// wrote, so their edits appear here right away.
class MemberRulesScreen extends StatelessWidget {
  const MemberRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'Community Rules',
      activeItem: 'Community Rules',
      child: ListenableBuilder(
        listenable: AppBranding.instance,
        builder: (context, _) {
          final b = AppBranding.instance;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: ResidentColors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.rulesTitle,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700, color: ResidentColors.textPrimary)),
                      const SizedBox(height: 16),
                      if (b.rulesContent.trim().isEmpty)
                        const Text(
                          "The HOA hasn't published the community rules yet. Please check back later.",
                          style: TextStyle(fontSize: 13.5, height: 1.6, color: ResidentColors.textSecondary),
                        )
                      else
                        SelectableText(
                          b.rulesContent,
                          style: const TextStyle(fontSize: 14, height: 1.7, color: ResidentColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
