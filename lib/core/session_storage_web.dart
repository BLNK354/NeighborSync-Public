/// Web: the sign-in token lives in sessionStorage unless the device is
/// remembered, so closing the tab ends the session. A refresh keeps it.
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

const _rememberKey = 'ns_remember_device';
const _sessionKey = 'ns_supabase_session';
const _loginSessionKey = 'ns_login_session_id';

bool readRememberFlag() =>
    web.window.localStorage.getItem(_rememberKey) == 'true';

void writeRememberFlag(bool value) {
  if (value) {
    web.window.localStorage.setItem(_rememberKey, 'true');
  } else {
    web.window.localStorage.removeItem(_rememberKey);
    // Also clears the saved token, or it would stay in localStorage.
    web.window.localStorage.removeItem(_sessionKey);
  }
}

/// True on web: the "remember this device" control is shown.
const bool supportsNonPersistentSession = true;

LocalStorage? buildAuthStorage() => NeighborSyncAuthStorage();

/// Gets the `login_sessions` row id for this device, so it survives a refresh.
String? readPersistedLoginSessionId() {
  final raw = web.window.sessionStorage.getItem(_loginSessionKey) ??
      web.window.localStorage.getItem(_loginSessionKey);
  if (raw == null || raw.isEmpty) return null;
  return raw;
}

/// Saves the login session id (null clears it) in the store the remember flag picks.
void writePersistedLoginSessionId(String? id) {
  if (id == null) {
    web.window.sessionStorage.removeItem(_loginSessionKey);
    web.window.localStorage.removeItem(_loginSessionKey);
    return;
  }
  final store =
      readRememberFlag() ? web.window.localStorage : web.window.sessionStorage;
  store.setItem(_loginSessionKey, id.toString());
}

/// Keeps the Supabase session in sessionStorage or localStorage, depending on
/// the remember flag. The flag is read on every call, so changes apply at once.
class NeighborSyncAuthStorage extends LocalStorage {
  @override
  Future<void> initialize() async {}

  web.Storage get _store =>
      readRememberFlag() ? web.window.localStorage : web.window.sessionStorage;

  @override
  Future<String?> accessToken() async => _store.getItem(_sessionKey);

  @override
  Future<bool> hasAccessToken() async => _store.getItem(_sessionKey) != null;

  @override
  Future<void> persistSession(String persistSessionString) async {
    _store.setItem(_sessionKey, persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    // Clear both stores so no copy is left behind on sign-out.
    web.window.sessionStorage.removeItem(_sessionKey);
    web.window.localStorage.removeItem(_sessionKey);
    web.window.sessionStorage.removeItem(_loginSessionKey);
    web.window.localStorage.removeItem(_loginSessionKey);
  }
}

// ---------------------------------------------------------------------
// Pending verify-email address
// ---------------------------------------------------------------------

/// The address that just registered, kept for the /verify-email screen.
/// Sign-up returns no session, so that screen has no other way to know it.
/// Stored in sessionStorage: survives a refresh, gone when the tab closes.
const _pendingVerifyKey = 'ns_pending_verify_email';

String? readPendingVerifyEmail() =>
    web.window.sessionStorage.getItem(_pendingVerifyKey);

void writePendingVerifyEmail(String email) =>
    web.window.sessionStorage.setItem(_pendingVerifyKey, email);

void clearPendingVerifyEmail() =>
    web.window.sessionStorage.removeItem(_pendingVerifyKey);

