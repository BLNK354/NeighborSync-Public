/// Reads the reason a failed email link (such as an expired password reset)
/// sends back in the URL fragment, e.g. `#error_code=otp_expired`.
/// It is captured once at boot so the password screens can explain it.
///
/// Only failures are handled. Never clear the fragment: supabase_flutter
/// reads the tokens of a good link from it during init.
library;

import 'auth_link_timing.dart';

/// Set at boot by [AuthLinkError.capture]; null on a normal load.
AuthLinkError? authLinkError;

/// A failed email link, with Supabase's reason and wording.
class AuthLinkError {
  /// Supabase's machine-readable reason, e.g. `otp_expired`.
  final String code;

  /// Supabase's own sentence, used when we have no wording for the code.
  final String description;

  /// True once the router has acted on this, so it only redirects once.
  bool consumed = false;

  AuthLinkError({required this.code, required this.description});

  /// Reads the error from the URL fragment, or returns null if there is none
  /// (always null on Android, where the URL has no fragment).
  static AuthLinkError? capture() {
    final fragment = Uri.base.fragment;
    if (fragment.isEmpty || !fragment.contains('error')) return null;

    // The fragment is form-encoded like a query string.
    final Map<String, String> parts;
    try {
      parts = Uri.splitQueryString(fragment);
    } catch (_) {
      // An unreadable fragment must not crash startup.
      return null;
    }

    final code = parts['error_code'] ?? parts['error'];
    if (code == null || code.isEmpty) return null;

    return AuthLinkError(
      code: code,
      description: parts['error_description'] ?? '',
    );
  }

  /// True when asking for a fresh link fixes it; shows the request button.
  bool get isExpiredLink =>
      code == 'otp_expired' || code == 'access_denied';

  /// Plain wording to show the person, with what to do next.
  String get message {
    switch (code) {
      // Keep the time from authLinkValidityInWords so the text matches the
      // on-screen countdown.
      case 'otp_expired':
        return 'That reset link has expired or has already been used. '
            'Links last $authLinkValidityInWords and work once — '
            'request a new one below.';
      case 'access_denied':
        return 'That reset link is no longer valid. '
            'Request a new one below.';
      default:
        return description.isEmpty
            ? 'That link could not be used. Request a new one below.'
            : '$description Request a new one below.';
    }
  }
}
