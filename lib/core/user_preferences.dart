/// Read and write `users.preferences` without destroying what is already
/// in it.
///
/// `preferences` is one jsonb column shared by several features. Always
/// save through [patchMyPreferences], which merges; writing the whole
/// object would erase other features' keys.
///
/// Read-modify-write is not atomic: two devices saving at the same instant
/// can lose one change.
library;

import '../services/supabase_service.dart';

/// The signed-in user's preferences map. Empty when the column is null,
/// so callers never have to null-check before reading a key.
Future<Map<String, dynamic>> readMyPreferences() async {
  final profile = await SupabaseService.instance.getMyProfile();
  final prefs = profile?['preferences'];
  return prefs is Map<String, dynamic> ? Map<String, dynamic>.from(prefs) : {};
}

/// Merges [patch] into the user's existing preferences and saves.
///
/// A null value removes that key.
Future<void> patchMyPreferences(int userId, Map<String, dynamic> patch) async {
  final current = await readMyPreferences();
  current.addAll(patch);
  current.removeWhere((_, v) => v == null);
  await SupabaseService.instance.client
      .from('users')
      .update({'preferences': current}).eq('id', userId);
}
