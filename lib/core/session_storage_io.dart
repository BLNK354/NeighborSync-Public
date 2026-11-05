/// Android / desktop: default storage, and "remember this device" does not apply.
///
/// Closing the app can't be detected reliably here, so the session persists
/// as Supabase normally does and the idle timeout in SessionPolicy protects it.
///
/// [buildAuthStorage] returns null here, meaning "use the default".
library;

import 'package:supabase_flutter/supabase_flutter.dart';

bool _remember = true;

/// Always true here: the session persists regardless.
bool readRememberFlag() => _remember;

void writeRememberFlag(bool value) => _remember = value;

/// Whether to show the "remember this device" control. False here, so it is hidden.
const bool supportsNonPersistentSession = false;

LocalStorage? buildAuthStorage() => null;

String? readPersistedLoginSessionId() => null;

void writePersistedLoginSessionId(String? id) {}

// ---------------------------------------------------------------------
// Pending verify-email address
// ---------------------------------------------------------------------

/// The address that just registered, kept for the /verify-email screen.
/// Memory only; a fresh app launch starts at login.
String? _pendingVerifyEmail;

String? readPendingVerifyEmail() => _pendingVerifyEmail;

void writePendingVerifyEmail(String email) => _pendingVerifyEmail = email;

void clearPendingVerifyEmail() => _pendingVerifyEmail = null;
