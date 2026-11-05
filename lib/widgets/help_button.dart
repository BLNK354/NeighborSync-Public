/// The ? button beside the bell, and the "How do I…?" menu it opens.
/// Choosing a guide hands its steps to [TourController.runGuide].
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/dialog_sizing.dart';
import '../core/help_guides.dart';
import '../core/roles.dart';
import '../core/screen_tips.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'guided_tour.dart';
import '../core/branding.dart';
import '../core/safe_state.dart';
import '../core/stored_file.dart';

/// The ? icon button that opens the help menu.
class HelpButton extends StatelessWidget {
  final Color iconColor;
  const HelpButton({super.key, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'How do I…?',
      icon: Icon(Icons.help_outline, color: iconColor),
      onPressed: () => showHelpMenu(context),
    );
  }
}

/// Opens the help menu and starts the guide the person picks.
Future<void> showHelpMenu(BuildContext context) async {
  final String path =
      GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;

  // Opens at once and loads inside, so the tap never feels dead.
  final HelpGuide? picked = await showDialog<HelpGuide>(
    context: context,
    builder: (_) => _HelpMenu(guides: _loadGuides(), currentPath: path),
  );
  if (picked != null) TourController.runGuide(picked.steps);
}

/// The printable guide for the signed-in role, or null if not uploaded.
Future<String?> _guidePdfUrl() async {
  try {
    final profile = await SupabaseService.instance.getMyProfile();
    final role =
        (profile?['roles'] as Map<String, dynamic>?)?['name'] as String? ?? '';
    return AppBranding.instance.guideUrlForRole(role);
  } catch (_) {
    return null;
  }
}

/// The guides this person's role and permissions allow.
Future<List<HelpGuide>> _loadGuides() async {
  try {
    final profile = await SupabaseService.instance.getMyProfile();
    final perms = await SupabaseService.instance.getMyPermissions();
    final role =
        (profile?['roles'] as Map<String, dynamic>?)?['name'] as String? ?? '';
    return helpGuidesFor(
      role: role,
      isOfficer: officerRoles.contains(role),
      perms: perms,
    );
  } catch (_) {
    // The menu shows a message instead of an error dialog.
    return const [];
  }
}

/// The searchable list of guides, with the current screen's guides first.
class _HelpMenu extends StatefulWidget {
  final Future<List<HelpGuide>> guides;
  final String currentPath;
  const _HelpMenu({required this.guides, required this.currentPath});

  @override
  State<_HelpMenu> createState() => _HelpMenuState();
}

class _HelpMenuState extends State<_HelpMenu> with SafeSetState<_HelpMenu> {
  String _query = '';
  List<HelpGuide>? _guides;
  String? _pdfUrl;

  @override
  void initState() {
    super.initState();
    widget.guides.then((g) {
      if (mounted) setState(() => _guides = g);
    });
    _guidePdfUrl().then((u) {
      if (mounted) setState(() => _pdfUrl = u);
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = _guides ?? const <HelpGuide>[];
    final q = _query.trim().toLowerCase();
    final matching = q.isEmpty
        ? all
        : all
            .where((g) =>
                g.question.toLowerCase().contains(q) ||
                g.section.toLowerCase().contains(q))
            .toList();

    // Guides for the page being viewed come first.
    final here = tipKeyFor(widget.currentPath);
    final onThisScreen = matching
        .where((g) => g.route != null && tipKeyFor(g.route!) == here)
        .toList();

    final sections = <String, List<HelpGuide>>{};
    for (final g in matching) {
      if (onThisScreen.contains(g)) continue;
      sections.putIfAbsent(g.section, () => []).add(g);
    }

    return AlertDialog(
      insetPadding: dialogInset(context),
      title: const Text('How do I…?'),
      content: SizedBox(
        width: dialogContentWidth(context, 460),
        height: dialogMaxHeight(context, 480),
        child: Column(
          children: [
            TextField(
              autofocus: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search the guides',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            // Full guide as a PDF; shown only once the office uploads it.
            if (_pdfUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.menu_book_outlined, size: 20),
                  title: const Text('Download the full guide (PDF)',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Everything in one document, for your role',
                      style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () =>
                      openStoredFile(context, publicUrl: _pdfUrl).catchError((_) {}),
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: _guides == null
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : matching.isEmpty
                      ? Center(
                          child: Text(
                            all.isEmpty
                                ? 'The guides could not be loaded. Check your '
                                    'connection and try again.'
                                : 'No guide matches that.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : ListView(
                          children: [
                            if (onThisScreen.isNotEmpty) ...[
                              _heading('On this screen'),
                              for (final g in onThisScreen) _tile(g),
                            ],
                            for (final e in sections.entries) ...[
                              _heading(e.key),
                              for (final g in e.value) _tile(g),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textMuted,
          ),
        ),
      );

  Widget _tile(HelpGuide g) => ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: const Icon(Icons.play_circle_outline, size: 20),
        title: Text(g.question, style: const TextStyle(fontSize: 13.5)),
        trailing: Text(
          g.steps.length == 1 ? '1 step' : '${g.steps.length} steps',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
        onTap: () => Navigator.pop(context, g),
      );
}
