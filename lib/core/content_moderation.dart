import '../services/supabase_service.dart';

/// Asks the `moderate-text` Edge Function whether text is offensive.
/// Returns the reason to show the person, or null when the text is fine.
///
/// Fails open: if the function cannot be reached the save goes ahead, because
/// the database also blocks listed bad words (trg_01_block_profanity).
Future<String?> moderationProblem(Iterable<String?> texts) async {
  final joined = texts
      .whereType<String>()
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .join('\n');
  // No letters (numbers, dates, plates): nothing to check.
  if (!RegExp(r'[A-Za-z]').hasMatch(joined)) return null;
  try {
    // Time limit so a slow reply cannot hold up the save.
    final res = await SupabaseService.instance.client.functions
        .invoke('moderate-text', body: {'text': joined})
        .timeout(const Duration(seconds: 6));
    final data = res.data;
    if (data is Map && data['flagged'] == true) {
      final reason = (data['reason'] ?? '').toString().trim();
      return reason.isEmpty
          ? 'Please remove the offensive words before saving.'
          : reason;
    }
  } catch (_) {
    // Unreachable or too slow: the database check still applies.
  }
  return null;
}
