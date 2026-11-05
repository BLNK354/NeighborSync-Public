/// How long a signed-in session survives, and where its token is kept.
///
/// Two protections against someone inheriting a signed-in session:
///  * Non-persistent storage: on web the token lives in session storage,
///    so closing the tab or browser signs out.
///  * Idle timeout: signs out after a period with no interaction.
///
/// "Remember this device" turns off the first, never the second.
library;

import 'session_storage.dart';

class SessionPolicy {
  SessionPolicy._();

  /// Idle limit for officers, who often use shared desks.
  static const officerIdle = Duration(minutes: 15);

  /// Idle limit for residents, who are usually on their own phone.
  static const residentIdle = Duration(hours: 2);

  /// Grace period when the app returns from the background, so a quick
  /// switch to another app does not sign anyone out.
  static const resumeGrace = Duration(seconds: 30);

  /// Idle limit for the given role name (officer roles get the short one).
  static Duration idleFor(String? roleName) {
    const officers = {
      'super_admin', 'hoa_president', 'secretary',
      'treasurer', 'security', 'audit_officer',
    };
    return officers.contains(roleName) ? officerIdle : residentIdle;
  }

  /// True if this device is marked as trusted. Read it before Supabase
  /// starts, because it decides where the token is stored.
  static bool get rememberDevice => readRememberFlag();

  static void setRememberDevice(bool value) => writeRememberFlag(value);
}
