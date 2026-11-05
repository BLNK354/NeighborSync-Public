import 'dart:convert';

import '../core/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_origin.dart';
import '../core/session_storage.dart';

/// Wrapper around the Supabase client: sign-up, sign-in, two-factor, profile
/// and permission lookups, device sessions and audit logging.
/// Use it through [SupabaseService.instance].
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;

  /// Starts Supabase. Call once at app start.
  static Future<void> init({
    required String url,
    required String anonKey,
  }) async {
    // Web keeps the session in sessionStorage unless the device is remembered,
    // so it ends with the browser. Android gets null, meaning the default.
    final storage = buildAuthStorage();
    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
      authOptions: storage == null
          ? const FlutterAuthClientOptions()
          : FlutterAuthClientOptions(localStorage: storage),
    );
    // Restore which login_sessions row this tab owns (survives refresh).
    currentLoginSessionId = readPersistedLoginSessionId();
  }

  // ---------------------------------------------------------------
  // REGISTER
  // ---------------------------------------------------------------
  /// Creates an account and mails the confirmation link.
  /// The extra details are read by the database's signup trigger.
  Future<AuthResponse> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? middleName,
    String? suffix,
    required String phoneNumber,
    required String role,
    String? termsVersion,
    String? honeypot,
    String? communityName,
  }) async {
    final res = await client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: '${appOrigin()}/verify-email',
      data: {
        'first_name': firstName,
        'last_name': lastName,
        if (middleName != null && middleName.isNotEmpty) 'middle_name': middleName,
        if (suffix != null && suffix.isNotEmpty) 'suffix': suffix,
        'phone_number': phoneNumber,
        'role': role,
        if (termsVersion != null && termsVersion.isNotEmpty)
          'terms_version': termsVersion,
        if (honeypot != null && honeypot.isNotEmpty) 'hp': honeypot,
        if (communityName != null && communityName.isNotEmpty)
          'community_name': communityName,
      },
    );

    // An address already in use does not raise an error: Supabase returns a
    // user with no identities and sends no email, so treat that as a refusal.
    final identities = res.user?.identities;
    if (res.user != null && identities != null && identities.isEmpty) {
      throw const AuthException('User already registered');
    }

    // /verify-email needs the address and there is no session yet to read it
    // from. Saved only after success, so a failed signup leaves nothing stale.
    writePendingVerifyEmail(email);
    return res;
  }

  // ---------------------------------------------------------------
  // VERIFY EMAIL
  // ---------------------------------------------------------------
  /// Mails another signup confirmation link.
  Future<void> resendVerificationEmail(String email) {
    return client.auth.resend(type: OtpType.signup, email: email);
  }

  bool get isEmailVerified =>
      client.auth.currentUser?.emailConfirmedAt != null;

  // ---------------------------------------------------------------
  // FORGOT / RESET PASSWORD
  // ---------------------------------------------------------------
  /// Mails a reset link for someone who forgot their password.
  Future<void> sendPasswordResetEmail(String email) {
    return client.auth.resetPasswordForEmail(
      email,
      redirectTo: '${appOrigin()}/reset-password',
    );
  }

  /// An officer sends a reset link to another account through the Edge
  /// Function. Returns the address it went to; throws the function's refusal.
  Future<String> adminSendPasswordReset(Object userId) async {
    final res = await client.functions.invoke(
      'admin-reset-password',
      body: {
        'user_id': userId,
        'redirect_to': '${appOrigin()}/reset-password',
      },
    );
    final data = res.data as Map<String, dynamic>?;
    if (data == null) throw Exception('No response from the reset service.');
    if (data['error'] != null) throw Exception(data['error'].toString());
    final email = (data['email'] ?? '').toString();
    await logAuditAction(
      'password_reset_sent',
      'users',
      resource: email,
      resourceId: userId is int ? userId : int.tryParse(userId.toString()),
    );
    return email;
  }

  /// Sets a new password during reset-link recovery, where no old one exists.
  /// Signed-in users go through [changePassword] instead.
  Future<UserResponse> updatePassword(String newPassword) {
    return client.auth.updateUser(UserAttributes(password: newPassword));
  }

  // ---------------------------------------------------------------
  // CHANGE PASSWORD (signed in)
  // ---------------------------------------------------------------
  /// Checks the current password, then sets the new one.
  /// Throws a plain message when the current password is wrong.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = client.auth.currentUser?.email;
    if (email == null) {
      throw 'You are not signed in. Please sign in again and retry.';
    }
    try {
      await client.auth
          .signInWithPassword(email: email, password: currentPassword);
    } on AuthException {
      throw 'That current password is not correct.';
    }
    await _updatePasswordWithCurrent(currentPassword, newPassword);
    await logAuditAction('password_change', 'auth');
  }

  /// Sends the password change with `current_password` over HTTP.
  /// The project requires it, and this gotrue-dart version has no such field,
  /// so a plain updateUser would be refused. Recovery sessions are exempt.
  Future<void> _updatePasswordWithCurrent(
      String currentPassword, String newPassword) async {
    final token = client.auth.currentSession?.accessToken;
    if (token == null) {
      throw 'You are not signed in. Please sign in again and retry.';
    }
    final res = await http.put(
      Uri.parse('$kSupabaseUrl/auth/v1/user'),
      headers: {
        'apikey': kSupabaseAnonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'password': newPassword,
        'current_password': currentPassword,
      }),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    Map<String, dynamic> body = const {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    final code = (body['error_code'] ?? body['code'] ?? '').toString();
    final reasons = (body['weak_password']?['reasons'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    if (code == 'weak_password') {
      // The SDK's own type, so friendlyError words it as on register and reset.
      throw AuthWeakPasswordException(
        message: (body['msg'] ?? body['message'] ?? 'Weak password').toString(),
        statusCode: res.statusCode.toString(),
        reasons: reasons,
      );
    }
    if (code == 'current_password_invalid' ||
        code == 'current_password_mismatch' ||
        code == 'current_password_required') {
      throw 'That current password is not correct.';
    }
    if (code == 'same_password') {
      throw 'The new password must be different from the current one.';
    }
    throw AuthApiException(
      (body['msg'] ?? body['message'] ?? 'Could not change the password.')
          .toString(),
      statusCode: res.statusCode.toString(),
      code: code.isEmpty ? null : code,
    );
  }

  // ---------------------------------------------------------------
  // SIGN IN
  // ---------------------------------------------------------------
  /// Signs in with a password, clearing the previous person's cached details.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    clearIdentityCache();
    final res =
        await client.auth.signInWithPassword(email: email, password: password);
    // Confirmed account, so the saved signup address is no longer needed.
    // A failed sign-in skips this: "email not confirmed" still needs resend.
    clearPendingVerifyEmail();
    return res;
  }

  /// Forgets the cached id, role, status and permissions.
  /// Call after any direct auth signOut, or the next person is judged as this one.
  void clearIdentityCache() {
    cachedUserRowId = null;
    cachedRole = null;
    cachedStatus = null;
    cachedPermissions = null;
  }

  // ---------------------------------------------------------------
  // MFA
  // ---------------------------------------------------------------
  /// The account's authenticator-app factors. Phone factors are not included.
  Future<List<Factor>> listMfaFactors() async {
    final resp = await client.auth.mfa.listFactors();
    return resp.totp;
  }

  /// Starts authenticator-app setup and returns the QR details.
  Future<AuthMFAEnrollResponse> enrollTotp() async {
    // A leftover unverified factor makes enrolling fail with "already exists".
    final existing = await client.auth.mfa.listFactors();
    for (final f in existing.all) {
      if (f.factorType == FactorType.totp && f.status == FactorStatus.unverified) {
        await client.auth.mfa.unenroll(f.id);
      }
    }
    return client.auth.mfa.enroll(factorType: FactorType.totp);
  }

  /// Checks a 6-digit authenticator code against one factor.
  Future<void> verifyMfaCodeForFactor({required String factorId, required String code}) async {
    await client.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  Future<void> unenrollMfa(String factorId) async {
    await client.auth.mfa.unenroll(factorId);
  }

  // ---------------------------------------------------------------
  // EMAIL SIGN-IN CODE (second step, app-checked)
  // ---------------------------------------------------------------
  // Built on passwordless email OTP: one call mails a code, the other turns
  // it into a session. The "Magic Link or OTP" template must show {{ .Token }}.
  // Enforced by the app, not RLS: the password alone still works on the API.

  /// The address being verified while the code screen is open.
  /// Kept in memory so the email never lands in the URL or browser history.
  static String? pendingEmailCodeAddress;

  /// Mails a sign-in code. Never creates a new account.
  Future<void> sendEmailLoginCode(String email) {
    return client.auth.signInWithOtp(email: email, shouldCreateUser: false);
  }

  /// Turns a mailed code into the real session at login.
  Future<void> verifyEmailLoginCode({required String email, required String code}) async {
    clearIdentityCache();
    await client.auth.verifyOTP(type: OtpType.email, email: email, token: code);
  }

  /// Checks an email code for someone already signed in, keeping their sign-in.
  /// verifyOTP issues a fresh AAL1 session, which could not remove an
  /// authenticator app, so the previous session is put back afterwards.
  Future<void> verifyEmailCodeKeepingSession({
    required String email,
    required String code,
  }) async {
    final previous = client.auth.currentSession?.refreshToken;
    await client.auth.verifyOTP(type: OtpType.email, email: email, token: code);
    if (previous != null) {
      try {
        await client.auth.setSession(previous);
      } catch (_) {
        // Restoring is a courtesy; the new session is still a valid one.
      }
    }
  }

  /// True when this sign-in has passed the authenticator-app step.
  bool get passedAuthenticator =>
      client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
      AuthenticatorAssuranceLevels.aal2;

  /// Re-checks the signed-in user's password; throws a message if it is wrong.
  /// Use before turning the email code off.
  Future<void> verifyCurrentPassword(String password) async {
    final email = client.auth.currentUser?.email;
    if (email == null) throw 'You are not signed in. Please sign in again and retry.';
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException {
      throw 'That password is not correct.';
    }
  }

  /// True when this sign-in still has to pass the authenticator app.
  bool needsMfaStepUp() {
    final level = client.auth.mfa.getAuthenticatorAssuranceLevel();
    return level.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
        level.nextLevel == AuthenticatorAssuranceLevels.aal2;
  }

  // ---------------------------------------------------------------
  // PROFILE / ROLE
  // ---------------------------------------------------------------
  /// The signed-in user's row with their role, or null when signed out.
  Future<Map<String, dynamic>?> getMyProfile() async {
    final authUid = client.auth.currentUser?.id;
    if (authUid == null) return null;
    return client
        .from('users')
        // Keep `phase`: Payment Channels reads it to offer the right scopes.
        .select('id, email, first_name, last_name, phone, address, status, '
            'phase, lot_id, requested_lot_id, preferences, '
            'ownership_proof_path, ownership_proof_type, '
            'ownership_proof_uploaded_at, '
            'mfa_enabled, profile_photo_url, created_at, '
            'roles(name, display_name)')
        .eq('supabase_uid', authUid)
        .maybeSingle();
  }

  /// The user's role name and account status, cached after the first read.
  Future<({String role, String status})?> getRoleAndStatus() async {
    if (cachedRole != null && cachedStatus != null) {
      return (role: cachedRole!, status: cachedStatus!);
    }
    final profile = await getMyProfile();
    if (profile == null) return null;
    final roles = profile['roles'];
    final roleName = roles is Map ? (roles['name'] as String? ?? '') : '';
    final status = (profile['status'] as String?) ?? '';
    cachedRole = roleName;
    cachedStatus = status;
    return (role: roleName, status: status);
  }

  Future<String?> getMyRole() async {
    final info = await getRoleAndStatus();
    return info?.role;
  }

  Future<String?> getMyStatus() async {
    final info = await getRoleAndStatus();
    return info?.status;
  }

  // Details of the signed-in person; cleared by clearIdentityCache().
  static int? cachedUserRowId;
  static String? cachedRole;
  static String? cachedStatus;
  static Map<String, Set<String>>? cachedPermissions;

  /// The user's `users.id`, which differs from the auth uid. Cached.
  Future<int?> getMyUserId() async {
    if (cachedUserRowId != null) return cachedUserRowId;
    final profile = await getMyProfile();
    final id = profile?['id'];
    if (id is int) {
      cachedUserRowId = id;
      return id;
    }
    if (id != null) {
      cachedUserRowId = int.tryParse(id.toString());
      return cachedUserRowId;
    }
    return null;
  }

  /// The user's permissions as module -> actions. Cached.
  Future<Map<String, Set<String>>> getMyPermissions() async {
    if (cachedPermissions != null) return cachedPermissions!;
    final uid = await getMyUserId();
    if (uid == null) return cachedPermissions = {};
    final rows = await client
        .from('role_permissions')
        .select('permissions(module, action), roles!inner(users!inner(id))')
        .eq('roles.users.id', uid);
    final map = <String, Set<String>>{};
    for (final row in (rows as List)) {
      final perm = row['permissions'];
      final module = perm?['module'] as String?;
      final action = perm?['action'] as String?;
      if (module == null || action == null) continue;
      map.putIfAbsent(module, () => <String>{}).add(action);
    }
    return cachedPermissions = map;
  }

  // ---------------------------------------------------------------
  // SESSIONS (single-device policy)
  // ---------------------------------------------------------------
  /// This device's `login_sessions` row. The id is a uuid, so keep it a String.
  static String? currentLoginSessionId;

  void _setCurrentLoginSessionId(String? id) {
    currentLoginSessionId = id;
    writePersistedLoginSessionId(id);
  }

  /// Adds this device to the sign-in list and logs the sign-in.
  Future<void> recordLoginSession(String device) async {
    final uid = await getMyUserId();
    if (uid == null) return;
    try {
      final row = await client.from('login_sessions').insert({
        'user_id': uid,
        'device': device,
      }).select('id').single();
      final id = row['id'];
      _setCurrentLoginSessionId(id?.toString());
    } catch (_) {
      // Best-effort: missing table/RLS must not block sign-in.
    }
    // Logged apart from the row above: sign-out deletes those rows, and the
    // audit trail must outlive them.
    await logAuditAction('sign_in', 'auth', resource: device);
  }

  /// Ends every session except this one and clears their sign-in rows.
  Future<void> signOutOtherDevices() async {
    final uid = await getMyUserId();
    if (uid == null) return;
    final keepId = currentLoginSessionId;
    try {
      var q = client.from('login_sessions').delete().eq('user_id', uid);
      if (keepId != null) {
        q = q.neq('id', keepId);
      }
      await q;
    } catch (_) {}
    try {
      await client.auth.signOut(scope: SignOutScope.others);
    } catch (_) {}
    await logAuditAction('sign_out', 'auth', resource: 'other devices');
  }

  /// Ends EVERY session on the account, including this one.
  Future<void> signOutEverywhere() async {
    await logAuditAction('sign_out', 'auth', resource: 'all devices (credential change)');
    final uid = await getMyUserId();
    if (uid != null) {
      try {
        await client.from('login_sessions').delete().eq('user_id', uid);
      } catch (_) {}
    }
    _setCurrentLoginSessionId(null);
    clearIdentityCache();
    await client.auth.signOut(scope: SignOutScope.global);
  }

  /// True while this device's login_sessions row still exists.
  /// False means another device removed it; the app then goes to login.
  Future<bool> isCurrentLoginSessionStillActive() async {
    currentLoginSessionId ??= readPersistedLoginSessionId();
    final id = currentLoginSessionId;
    if (id == null) {
      // Nothing recorded for this tab: do not sign the person out.
      return true;
    }
    try {
      final row = await client
          .from('login_sessions')
          .select('id')
          .eq('id', id)
          .maybeSingle();
      return row != null;
    } catch (_) {
      // A passing network error must not sign the person out.
      return true;
    }
  }

  /// Signs out on this device only and clears the cached details.
  Future<void> signOut() async {
    await logAuditAction('sign_out', 'auth');
    _setCurrentLoginSessionId(null);
    clearIdentityCache();
    await client.auth.signOut();
  }

  // ---------------------------------------------------------------
  // AUDIT
  // ---------------------------------------------------------------
  /// Records an event the database cannot see, such as a sign-in or a read.
  Future<void> logAuditAction(
    String action,
    String resourceType, {
    String? resource,
    int? resourceId,
  }) async {
    // Must go through the RPC: audit_logs has no INSERT policy, so a direct
    // insert is refused. A failed log must never block the action itself.
    try {
      await client.rpc('log_audit_action', params: {
        'p_action': action,
        'p_module': resourceType,
        'p_resource': resource,
        'p_resource_id': resourceId,
        'p_detail': null,
      });
    } catch (_) {}
  }
}
