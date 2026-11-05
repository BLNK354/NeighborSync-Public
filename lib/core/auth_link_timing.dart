/// How long an emailed auth link lasts, and how soon another can be sent.
/// These mirror Supabase settings so the screens can count down against them.
/// The wording and the countdown both read these constants.
library;

/// How long an emailed link stays valid. Must match the Supabase setting
/// Authentication > Email > Email OTP expiration; change it here if that changes.
const Duration kAuthLinkValidity = Duration(hours: 1);

/// Wait before a new link can be requested: the link's own lifetime, so only
/// one link is live at a time. Longer than the server's 60-second minimum.
const Duration kAuthResendCooldown = kAuthLinkValidity;

/// Wait before another email sign-in code can be sent. Used by the code
/// screen and the two-factor page.
const Duration kEmailCodeResendCooldown = Duration(minutes: 3);

/// Formats a time left as `M:SS`, or `H:MM:SS` past an hour. Negative shows 0:00.
String formatCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// The link validity in words, such as "one hour", for use in sentences.
String get authLinkValidityInWords {
  const d = kAuthLinkValidity;
  if (d.inMinutes % 60 == 0) {
    final h = d.inHours;
    return h == 1 ? 'one hour' : '$h hours';
  }
  final m = d.inMinutes;
  return m == 1 ? 'one minute' : '$m minutes';
}
