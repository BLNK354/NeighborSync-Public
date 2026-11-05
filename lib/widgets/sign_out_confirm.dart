import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_locale.dart';
import '../services/supabase_service.dart';

/// Asks before signing out, then signs out and goes to the login screen.
///
/// Use this for every Sign Out button. The idle timeout and auth screens
/// sign out without asking.
Future<void> signOutWithConfirm(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      // Text goes through tr() so it follows the person's language.
      title: Text(tr('Log out?')),
      content: Text(tr('You will need your email and password to log back in.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
        FilledButton(
          // Red because it ends the session.
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFC62828),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Log Out')),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await SupabaseService.instance.signOut();
  if (context.mounted) context.go('/login');
}
