import '../widgets/profile_avatar.dart';
import '../core/field_rules.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/address_sort.dart';
import '../core/form_helpers.dart';
import '../core/image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, Factor, FactorStatus;
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../widgets/password_feedback.dart';
import '../widgets/responsive_officer_shell.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/tour_anchors.dart';
import '../core/dialog_controllers.dart';
import '../core/safe_state.dart';
import '../core/personal_folders.dart';
import '../core/stored_file.dart';

/// Officer "My Profile" screen, also the Profile tab on phones.
/// [_ProfileBody] handles its own layout, so only the shell differs.
class AdminProfileScreen extends StatelessWidget {
  const AdminProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const ResponsiveOfficerShell(
      title: 'My Profile',
      activeItem: 'My Profile',
      activeTab: 'Profile',
      desktopChild: _ProfileBody(officer: true),
    );
  }
}

/// Resident "Profile & Settings" screen.
class MemberProfileScreen extends StatelessWidget {
  const MemberProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const MemberShell(
      title: 'Profile & Settings',
      activeItem: 'Profile & Settings',
      child: _ProfileBody(officer: false),
    );
  }
}

/// Shared profile body: an "Account Details" card (photo, name, phone,
/// address, proof of ownership) beside a "Security" card (password, 2FA,
/// recent sign-ins). Log out lives in the shell, not here.
class _ProfileBody extends StatefulWidget {
  final bool officer;
  const _ProfileBody({required this.officer});

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> with SafeSetState<_ProfileBody> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  Map<String, dynamic>? _profile;
  /// Signed URL shown on screen, and the stored path it came from. The
  /// avatars bucket is private, so the two differ.
  String? _photoUrl;
  String? _photoRef;
  bool _uploadingPhoto = false;
  bool _loading = true;
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;

  /// All lots, used by the address picker and to print an address.
  List<Map<String, dynamic>> _lots = const [];
  /// Lots nobody lives at and nobody else has claimed (open_lot_ids()).
  /// Null when the lookup failed.
  Set<int>? _openLotIds;
  List<Map<String, dynamic>> _sessions = const [];

  /// True while Sign Out Other Devices is running; disables the button so a
  /// double-tap cannot run it twice.
  bool _signingOutOthers = false;

  /// Comes from Supabase Auth's TOTP factor list, not `users.mfa_enabled`.
  bool _mfaVerified = false;

  Color get _accent =>
      widget.officer ? AppColors.sidebarActiveText : ResidentColors.sidebarActiveText;
  Color get _accentBg =>
      widget.officer ? AppColors.badgeGreenBg : ResidentColors.badgeBg;
  Color get _textPrimary =>
      widget.officer ? AppColors.textPrimary : ResidentColors.textPrimary;
  Color get _textSecondary =>
      widget.officer ? AppColors.textSecondary : ResidentColors.textSecondary;
  Color get _border => widget.officer ? AppColors.border : ResidentColors.border;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Loads the profile, 2FA status, lots, sign-ins and proof files.
  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      SupabaseService.instance.getMyProfile(),
      SupabaseService.instance.listMfaFactors(),
      // Residents request a lot; officers assign their own.
      SupabaseService.instance.client
          .from('lots')
          .select('id, lot_number, status, street_address, blocks(block_name, phase)')
          .order('lot_number'),
      // This user's sign-in records; RLS limits them to the caller.
      SupabaseService.instance.client
          .from('login_sessions')
          .select('id, device, signed_in_at, last_seen_at')
          .order('last_seen_at', ascending: false)
          .limit(20),
      // Lots free to claim. If this fails, the picker just hides occupied lots.
      SupabaseService.instance.client
          .rpc('open_lot_ids')
          .then<dynamic>((v) => v, onError: (_) => null),
    ]);
    if (!mounted) return;
    final profile = results[0] as Map<String, dynamic>?;
    final factors = results[1] as List<Factor>;
    _lots = List<Map<String, dynamic>>.from(results[2] as List)..sort(compareLotRows);
    final open = results[4];
    _openLotIds = open is List
        ? {for (final v in open) (v is num ? v : num.parse(v.toString())).toInt()}
        : null;
    _sessions = List<Map<String, dynamic>>.from(results[3] as List);
    setState(() {
      _profile = profile;
      _firstName.text = (profile?['first_name'] ?? '').toString();
      _lastName.text = (profile?['last_name'] ?? '').toString();
      _phone.text = (profile?['phone'] ?? '').toString();
      _photoRef = (profile?['profile_photo_url'] as String?)?.trim();
      if (_photoRef != null && _photoRef!.isEmpty) _photoRef = null;
      _mfaVerified = factors.any((f) => f.status == FactorStatus.verified);
      _loading = false;
    });
    _loadProofs();
    // The photo is in a private bucket: turn the stored path into a link.
    final signed = await resolveProfilePhoto(_photoRef);
    if (mounted) setState(() => _photoUrl = signed);
  }

  /// Upload content type for an image file extension; defaults to PNG.
  static String _contentTypeFor(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'png':
      default:
        return 'image/png';
    }
  }

  /// Picks a photo, shrinks it, uploads it to the user's own folder in the
  /// `avatars` bucket and saves it right away (no Save Changes needed).
  Future<void> _pickAndUploadPhoto() async {
    final authUid = SupabaseService.instance.client.auth.currentUser?.id;
    if (authUid == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() {
        _message = 'Could not read that file -- try a different image.';
        _messageIsError = true;
      });
      return;
    }
    // Phone camera photos are large; an avatar only needs a small size.
    final shrunk =
        compressImageBytes(bytes, file.name, maxEdge: kMaxAvatarEdge);
    final dot = shrunk.filename.lastIndexOf('.');
    final ext =
        dot < 0 ? 'jpg' : shrunk.filename.substring(dot + 1).toLowerCase();
    final path = '$authUid/photo.$ext';
    setState(() => _uploadingPhoto = true);
    try {
      final client = SupabaseService.instance.client;
      await client.storage.from('avatars').uploadBinary(
            path,
            shrunk.bytes,
            fileOptions: FileOptions(upsert: true, contentType: _contentTypeFor(ext)),
          );
      // The bucket is private: store the PATH and show a signed link.
      final url = await resolveProfilePhoto(path);
      // Saved now so the photo sticks and the top bar can show it.
      await client
          .from('users')
          .update({'profile_photo_url': path})
          .eq('supabase_uid', authUid);
      MyPhoto.instance.set(url);
      if (!mounted) return;
      setState(() {
        _photoRef = path;
        _photoUrl = url;
        _uploadingPhoto = false;
        _message = 'Profile photo updated.';
        _messageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _message = 'Photo upload failed. ${friendlyError(e)}';
        _messageIsError = true;
      });
    }
  }

  /// Saves name, phone and photo. Role and status are never sent from here.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final myId = _profile?['id'];
    if (myId == null) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await SupabaseService.instance.client.from('users').update({
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'phone': _phone.text.trim(),
        // The address is not saved here; see _addressSection.
        'profile_photo_url': _photoRef,
      }).eq('id', myId);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Profile updated.';
        _messageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Could not save. ${friendlyError(e)}';
        _messageIsError = true;
      });
    }
  }

  /// Change Password dialog. Asks for the current password first, so someone
  /// at an already-signed-in device cannot change it and lock the owner out.
  Future<void> _openChangePasswordDialog() async {
    final currentPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    var changing = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (currentPassword.text.isEmpty) {
                setDialogState(() => dialogError = 'Enter your current password.');
                return;
              }
              // Same password rule as the register and reset screens.
              final pwError = passwordError(newPassword.text);
              if (pwError != null) {
                setDialogState(() => dialogError = pwError);
                return;
              }
              if (newPassword.text != confirmPassword.text) {
                setDialogState(() => dialogError = 'Passwords do not match.');
                return;
              }
              // Checked here because the server may report success for the
              // same password, telling the user it changed when it did not.
              if (newPassword.text == currentPassword.text) {
                setDialogState(() =>
                    dialogError = 'Your new password must be different from your current one.');
                return;
              }
              setDialogState(() {
                changing = true;
                dialogError = null;
              });
              try {
                await SupabaseService.instance.changePassword(
                  currentPassword: currentPassword.text,
                  newPassword: newPassword.text,
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                if (mounted) {
                  setState(() {
                    _message = 'Password changed.';
                    _messageIsError = false;
                  });
                }
              } catch (e) {
                setDialogState(() {
                  changing = false;
                  // A String is changePassword's own clear message; passing
                  // it through friendlyError would turn it into a generic one.
                  dialogError = e is String
                      ? e
                      : 'Could not change password. ${friendlyError(e)}';
                });
              }
            }

            // AlertDialog takes 128px of side padding; a fixed width would
            // overflow on a phone, so cap it to what is left.
            final maxW = MediaQuery.of(dialogContext).size.width - 128;
            return AlertDialog(
              title: const Text('Change Password'),
              content: SizedBox(
                width: maxW < 360 ? (maxW < 200 ? 200 : maxW) : 360,
                // Scrolls so the fields fit a landscape phone with the keyboard up.
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: currentPassword,
                      obscureText: true,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Current password',
                        helperText: 'Confirms it is really you making this change.',
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    TextField(
                      controller: newPassword,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        helperText: kPasswordHint,
                        helperMaxLines: 3,
                      ),
                    ),
                    PasswordStrengthBar(controller: newPassword, topGap: 10),
                    const SizedBox(height: 14),
                    TextField(
                      controller: confirmPassword,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Confirm new password'),
                      onSubmitted: (_) => submit(),
                    ),
                    PasswordMatchNote(
                      passwordController: newPassword,
                      confirmController: confirmPassword,
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(dialogError!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                    ],
                  ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: changing ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: changing ? null : submit,
                  child: Text(changing ? 'Updating...' : 'Update Password'),
                ),
              ],
            );
          },
        );
      },
    );

    // These hold passwords in plain text, so drop them when the dialog closes.
    // Disposing before its exit animation ends crashes, hence this helper.
    disposeAfterDialogCloses([currentPassword, newPassword, confirmPassword]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final email = (_profile?['email'] ?? '').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_message != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _messageIsError ? const Color(0xFFFBE4E4) : const Color(0xFFE3F1E9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_message!,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: _messageIsError
                            ? const Color(0xFFA82F2F)
                            : const Color(0xFF1A6B43))),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 860;
                final accountCard = _accountDetailsCard(email);
                final securityCard = _securityCard(_mfaVerified);
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      accountCard,
                      const SizedBox(height: 20),
                      securityCard,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: accountCard),
                    const SizedBox(width: 20),
                    Expanded(flex: 3, child: securityCard),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Photo, name, read-only email, phone, address and the Save button.
  Widget _accountDetailsCard(String email) {
    return _card(
      title: 'Account Details',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Semantics(
                  image: true,
                  label: _photoUrl == null
                      ? 'No profile photo set'
                      : 'Your profile photo',
                  child: ExcludeSemantics(
                    child: CircleAvatar(
                      radius: 42,
                      backgroundColor: _accentBg,
                      backgroundImage:
                          _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                      child: _photoUrl == null
                          ? Icon(Icons.person_outline, size: 36, color: _accent)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _uploadingPhoto ? null : _pickAndUploadPhoto,
                  icon: _uploadingPhoto
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.photo_camera_outlined, size: 16),
                  label: Text(_photoUrl == null ? 'Change Photo' : 'Change Photo'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _field('First Name', _firstName, inputFormatters: nameInputFormatters,
                  validator: (v) => _required(v) ?? nameRule(v, const {}))),
              const SizedBox(width: 16),
              Expanded(child: _field('Last Name', _lastName, inputFormatters: nameInputFormatters,
                  validator: (v) => _required(v) ?? nameRule(v, const {}))),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _readOnlyField('Email Address', email),
              ),
              const SizedBox(width: 16),
              Expanded(child: _field('Phone', _phone, inputFormatters: phoneInputFormatters, keyboardType: TextInputType.phone,
                  validator: (v) => (v == null || v.trim().isEmpty) ? null : phoneError(v))),
            ]),
            const SizedBox(height: 14),
            // Residents request an address; officers assign their own.
            _addressSection(),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: _accent),
                child: Text(_saving ? 'Saving...' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- address (block/lot) ----------

  /// Readable address, e.g. "Phase 4 · Block A · Lot 12 — Hillview". Used by
  /// the lot picker and to show the person's own address.
  String _lotLabel(dynamic lotId) {
    if (lotId == null) return '—';
    final lot = _lots.where((l) => l['id'] == lotId).cast<Map<String, dynamic>?>().firstOrNull;
    if (lot == null) return '—';
    final blocks = lot['blocks'] as Map<String, dynamic>?;
    final block = blocks?['block_name'] ?? '—';
    final phase = (blocks?['phase'] ?? '').toString().trim();
    var base = 'Block $block · Lot ${lot['lot_number'] ?? ''}';
    if (phase.isNotEmpty) base = 'Phase $phase · $base';
    final street = (lot['street_address'] ?? '').toString().trim();
    return street.isEmpty ? base : '$base — $street';
  }

  /// Searchable lot picker for residents and officers. Offers open lots only,
  /// except to a tenant, who rents a home somebody already owns.
  Future<Map<String, dynamic>?> _pickLot() {
    final isTenant = SupabaseService.cachedRole == 'tenant';
    final available = isTenant
        ? _lots
        : _openLotIds != null
            ? _lots.where((l) => _openLotIds!.contains((l['id'] as num).toInt())).toList()
            : _lots.where((l) => (l['status'] ?? '') != 'occupied').toList();
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        var query = '';
        return StatefulBuilder(builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? available
              : available.where((l) => _lotLabel(l['id']).toLowerCase().contains(q)).toList();
          return AlertDialog(
            title: const Text('Select Address'),
            content: SizedBox(
              width: dialogContentWidth(context, 360),
              height: dialogMaxHeight(context, 380),
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setDialogState(() => query = v),
                    decoration: const InputDecoration(
                        hintText: 'Search block or lot...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text('No available addresses.',
                                style: TextStyle(fontSize: 12.5, color: _textSecondary)))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) => ListTile(
                              dense: true,
                              title: Text(_lotLabel(filtered[i]['id']),
                                  style: const TextStyle(fontSize: 13)),
                              onTap: () => Navigator.pop(context, filtered[i]),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ],
          );
        });
      },
    );
  }

  /// Resident/tenant: records a requested address for an officer to approve.
  /// lot_id itself is protected by a database trigger.
  Future<void> _requestAddress() async {
    final picked = await _pickLot();
    if (picked == null) return;
    try {
      await SupabaseService.instance.client
          .from('users')
          .update({'requested_lot_id': picked['id']}).eq('id', _profile?['id'] as Object);
      if (!mounted) return;
      setState(() {
        _message =
            'Address request submitted (${_lotLabel(picked['id'])}) — waiting for HOA approval.';
        _messageIsError = false;
      });
      _load();
    } catch (e) {
      setState(() {
        _message = 'Could not submit the request. ${friendlyError(e)}';
        _messageIsError = true;
      });
    }
  }

  /// Officer: sets their own lot with no approval step, copies the label into
  /// the address column and marks the lot occupied. The database still refuses
  /// an officer whose role lacks users:update.
  Future<void> _setOfficerAddress() async {
    final picked = await _pickLot();
    if (picked == null) return;
    try {
      final client = SupabaseService.instance.client;
      await client.from('users').update({
        'lot_id': picked['id'],
        'requested_lot_id': null,
        'address': _lotLabel(picked['id']),
      }).eq('id', _profile?['id'] as Object);
      await client.from('lots').update({'status': 'occupied'}).eq('id', picked['id']);
      if (!mounted) return;
      setState(() {
        _message = 'Address set to ${_lotLabel(picked['id'])}.';
        _messageIsError = false;
      });
      _load();
    } catch (e) {
      setState(() {
        _message = 'Could not set your address. ${friendlyError(e)}';
        _messageIsError = true;
      });
    }
  }

  /// Withdraws a pending address request.
  Future<void> _cancelAddressRequest() async {
    try {
      await SupabaseService.instance.client
          .from('users')
          .update({'requested_lot_id': null}).eq('id', _profile?['id'] as Object);
      if (!mounted) return;
      setState(() {
        _message = 'Address request cancelled.';
        _messageIsError = false;
      });
      _load();
    } catch (e) {
      setState(() {
        _message = 'Could not cancel the request. ${friendlyError(e)}';
        _messageIsError = true;
      });
    }
  }

  /// Proof of ownership files, one per document type, stored as `documents`
  /// rows at ownership/<user_id>/... (the path the storage policies allow).
  /// `is_personal` hides them from other residents but not from officers.
  /// Keep `users.ownership_proof_*` on the newest file; the approvals card reads it.
  List<Map<String, dynamic>> _proofs = const [];

  /// Loads this resident's proof files, oldest first. Officers have none.
  Future<void> _loadProofs() async {
    final myId = _profile?['id'];
    if (myId == null || widget.officer) return;
    try {
      final rows = await SupabaseService.instance.client
          .from('documents')
          .select('id, name, proof_type, storage_path, mime_type, created_at')
          .eq('owner_id', myId as Object)
          .not('proof_type', 'is', null)
          .order('created_at');
      if (mounted) setState(() => _proofs = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {}
  }

  /// The file on record for a document type, or null.
  Map<String, dynamic>? _proofOf(String kind) {
    for (final p in _proofs) {
      if (p['proof_type'] == kind) return p;
    }
    return null;
  }

  /// Shows a message in the banner at the top of the page.
  void _say(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = msg;
      _messageIsError = error;
    });
  }

  /// Points users.ownership_proof_* at the newest remaining file, or clears
  /// it, so the approvals card matches what is on file.
  Future<void> _syncProofPointer() async {
    final myId = _profile?['id'];
    if (myId == null) return;
    await _loadProofs();
    final newest = _proofs.isEmpty ? null : _proofs.last;
    await SupabaseService.instance.client.from('users').update({
      'ownership_proof_path': newest?['storage_path'],
      'ownership_proof_type': newest?['proof_type'],
      'ownership_proof_uploaded_at':
          newest == null ? null : DateTime.now().toUtc().toIso8601String(),
    }).eq('id', myId as Object);
  }

  /// Picks and uploads a proof file (image or PDF, up to 8 MB) for a document
  /// type, replacing any file already held for that type.
  Future<void> _uploadOwnershipProof(String kind) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return _say('Could not read that file — try again.', error: true);
    if (bytes.length > 8 * 1024 * 1024) {
      return _say('That file is over 8 MB. Please upload a smaller scan or photo.',
          error: true);
    }
    try {
      final myId = _profile?['id'];
      if (myId == null) throw Exception('Could not resolve your account.');
      final client = SupabaseService.instance.client;
      // Officers read small print on these, so keep them large and sharp.
      // PDFs pass through untouched.
      final shrunk = compressImageBytes(bytes, file.name,
          maxEdge: kMaxSurveyPlanEdge, quality: 88);
      final dot = shrunk.filename.lastIndexOf('.');
      final ext = dot < 0
          ? (file.extension ?? 'jpg').toLowerCase()
          : shrunk.filename.substring(dot + 1).toLowerCase();
      final path = 'ownership/$myId/$kind-${DateTime.now().millisecondsSinceEpoch}.$ext';
      await client.storage.from('documents').uploadBinary(
            path,
            shrunk.bytes,
            fileOptions: FileOptions(
                contentType: ext == 'pdf' ? 'application/pdf' : 'image/$ext'),
          );

      // One file per type: the new one replaces the old.
      final old = _proofOf(kind);
      if (old != null) {
        await client.from('documents').delete().eq('id', old['id']);
        final oldPath = old['storage_path'] as String?;
        if (oldPath != null) {
          try {
            await client.storage.from('documents').remove([oldPath]);
          } catch (_) {}
        }
      }
      await client.from('documents').insert({
        'name': '${kProofTypes[kind] ?? 'Proof'} — ${file.name}',
        'original_name': file.name,
        'mime_type': ext == 'pdf' ? 'application/pdf' : 'image/$ext',
        'size_bytes': shrunk.bytes.length,
        'storage_path': path,
        'category': kProofFolder,
        'proof_type': kind,
        'uploaded_by': myId,
        'is_public': false,
        'is_personal': true,
        'is_private': false,
      });
      await _syncProofPointer();
      _say(old == null
          ? '${kProofTypes[kind]} uploaded. The HOA office will review it.'
          : '${kProofTypes[kind]} replaced.');
    } catch (e) {
      _say('Could not upload your proof. ${friendlyError(e)}', error: true);
    }
  }

  /// Asks first, then deletes a proof's record and its stored file.
  Future<void> _removeOwnershipProof(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this document?'),
        content: Text('"${p['name']}" will be deleted from your Proof of Ownership folder.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA82F2F)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final client = SupabaseService.instance.client;
      await client.from('documents').delete().eq('id', p['id']);
      final path = p['storage_path'] as String?;
      if (path != null) {
        try {
          await client.storage.from('documents').remove([path]);
        } catch (_) {}
      }
      await _syncProofPointer();
      _say('Document removed.');
    } catch (e) {
      _say('Could not remove it. ${friendlyError(e)}', error: true);
    }
  }

  /// Opens a proof file inside the app.
  Future<void> _viewProof(Map<String, dynamic> p) async {
    try {
      await openStoredFile(context,
          path: p['storage_path']?.toString(),
          name: p['name']?.toString(),
          mimeType: p['mime_type']?.toString());
    } catch (e) {
      _say('Could not open that file. ${friendlyError(e)}', error: true);
    }
  }

  /// The Proof of Ownership box: one row per document type.
  Widget _ownershipProofSection() {
    // An older proof recorded only on the users row, with no documents row.
    final legacyPath = _profile?['ownership_proof_path'] as String?;
    final hasLegacy = _proofs.isEmpty && legacyPath != null && legacyPath.isNotEmpty;

    return TourAnchor(
      id: TourAnchorId.ownershipProof,
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Proof of Ownership',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500, color: _textSecondary)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  for (final e in kProofTypes.entries) _proofRow(e.key, e.value),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  hasLegacy
                      ? 'You uploaded a document earlier. It is still on file; upload by type above to replace it.'
                      : 'One file per document type. They are kept in My Files → $kProofFolder. '
                          'Only you and HOA officers can open them.',
                  style: TextStyle(fontSize: 11, color: _textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  /// One document type with its View, Remove and Upload/Replace actions.
  Widget _proofRow(String kind, String label) {
    final p = _proofOf(kind);
    final has = p != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Icon(has ? Icons.verified_outlined : Icons.upload_file_outlined,
              size: 18, color: has ? _accent : _textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: _textPrimary,
                    fontWeight: has ? FontWeight.w600 : FontWeight.w400)),
          ),
          if (has) ...[
            TextButton(onPressed: () => _viewProof(p), child: const Text('View')),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFA82F2F)),
              onPressed: () => _removeOwnershipProof(p),
            ),
          ],
          TextButton(
            onPressed: () => _uploadOwnershipProof(kind),
            child: Text(has ? 'Replace' : 'Upload'),
          ),
        ],
      ),
    );
  }

  /// Address box. Officers can pick or change their own. For residents an
  /// approved address is read-only (a database trigger enforces it), a pending
  /// request can be cancelled, and otherwise they can pick an open address.
  Widget _addressSection() {
    final lotId = _profile?['lot_id'];
    final requestedLotId = _profile?['requested_lot_id'];

    Widget inner;
    // ---- Officer: self-assign, changeable, no approval step ----
    if (widget.officer) {
      if (lotId != null) {
        inner = Row(
          children: [
            Icon(Icons.home_outlined, size: 18, color: _accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_lotLabel(lotId),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimary)),
            ),
            TextButton(onPressed: _setOfficerAddress, child: const Text('Change')),
          ],
        );
      } else {
        inner = Row(
          children: [
            Expanded(
              child: Text('No address on your account yet.',
                  style: TextStyle(fontSize: 12.5, color: _textSecondary)),
            ),
            OutlinedButton.icon(
              onPressed: _setOfficerAddress,
              icon: const Icon(Icons.add_location_alt_outlined, size: 15),
              label: const Text('Select Address'),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Address (Block / Lot)',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _textSecondary)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(border: Border.all(color: _border), borderRadius: BorderRadius.circular(8)),
            child: inner,
          ),
        ],
      );
    }

    // ---- Resident / tenant: request -> officer approval ----
    if (lotId != null) {
      inner = Row(
        children: [
          Icon(Icons.home_outlined, size: 18, color: _accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_lotLabel(lotId),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimary)),
          ),
          Text('Verified by HOA', style: TextStyle(fontSize: 11, color: _textSecondary)),
        ],
      );
    } else if (requestedLotId != null) {
      inner = Row(
        children: [
          Icon(Icons.hourglass_top_outlined, size: 18, color: _accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${_lotLabel(requestedLotId)} — awaiting HOA approval',
                style: TextStyle(fontSize: 12.5, color: _textPrimary)),
          ),
          TextButton(onPressed: _cancelAddressRequest, child: const Text('Cancel Request')),
        ],
      );
    } else {
      inner = Row(
        children: [
          Expanded(
            child: Text('No address on your account yet.',
                style: TextStyle(fontSize: 12.5, color: _textSecondary)),
          ),
          TourAnchor(
            id: TourAnchorId.selectAddress,
            child: OutlinedButton.icon(
              onPressed: _requestAddress,
              icon: const Icon(Icons.add_location_alt_outlined, size: 15),
              label: const Text('Select Address'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Address (Block / Lot)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _textSecondary)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: inner,
        ),
        if (lotId != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Contact the HOA office if this needs to change.',
                style: TextStyle(fontSize: 11, color: _textSecondary)),
          ),
        _ownershipProofSection(),
      ],
    );
  }

  /// Change password, two-factor setup, sign out other devices, recent sign-ins.
  Widget _securityCard(bool mfaEnabled) {
    final session = SupabaseService.instance.client.auth.currentSession;
    final lastSignIn = session?.user.lastSignInAt;
    String sessionSub = 'Signed in now';
    if (lastSignIn != null) {
      final dt = DateTime.tryParse(lastSignIn);
      if (dt != null) {
        sessionSub = 'Signed in ${dt.toLocal().toString().split('.').first}';
      }
    }

    return _card(
      title: 'Security',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _openChangePasswordDialog,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Change Password'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await context.push('/mfa-setup');
                // Reload so the 2FA badge and button match what was done there.
                if (mounted) _load();
              },
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(mfaEnabled ? 'Manage Two-Factor Auth' : 'Set Up Two-Factor Auth'),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: mfaEnabled ? const Color(0xFFE3F1E9) : const Color(0xFFF3F6F4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                mfaEnabled ? '2FA enabled' : '2FA not enabled',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: mfaEnabled ? const Color(0xFF1A6B43) : _textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // The only control here that ends sessions elsewhere. It is all or
          // nothing: Supabase's signOut cannot target a single session.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _signingOutOthers ? null : _signOutOtherDevices,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _signingOutOthers
                  ? const SizedBox(
                      height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Sign Out Other Devices'),
            ),
          ),
          const SizedBox(height: 20),
          // A record of sign-ins, not live sessions: deleting a row does not
          // sign that device out, so do not label this "Active Sessions".
          Text('Recent Sign-ins',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _textSecondary)),
          const SizedBox(height: 10),
          if (_sessions.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _accentBg,
                    child: Icon(Icons.devices_outlined, size: 18, color: _accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lastSignIn == null
                          ? 'This device · signed in now'
                          : 'This device · signed in $sessionSub',
                      style: TextStyle(fontSize: 12.5, color: _textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final s in _sessions) _sessionRow(s),
          const SizedBox(height: 8),
          Text(
            'Every device that signs in is listed here, so you can spot one you '
            'do not recognise. The × clears an entry from this list only — it '
            'does not sign that device out. To actually end them, use Sign Out '
            'Other Devices above; those devices lose access within the hour. '
            'If you think someone else has your account, change your password '
            'too — that stops them signing back in.',
            style: TextStyle(fontSize: 11, color: _textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// One sign-in record; other devices get an × that clears the entry.
  Widget _sessionRow(Map<String, dynamic> s) {
    final isCurrent = s['id'] == SupabaseService.currentLoginSessionId;
    final device = (s['device'] ?? 'Device').toString();
    final when = DateTime.tryParse((s['signed_in_at'] ?? '').toString())?.toLocal();
    final whenLabel = when == null
        ? ''
        : 'Signed in ${when.toString().split('.').first}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: isCurrent ? _accent : _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _accentBg,
            child: Icon(Icons.devices_outlined, size: 18, color: _accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(device,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimary)),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: _accentBg, borderRadius: BorderRadius.circular(6)),
                        child: Text('This device',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: _accent)),
                      ),
                    ],
                  ],
                ),
                if (whenLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(whenLabel, style: TextStyle(fontSize: 11.5, color: _textSecondary)),
                ],
              ],
            ),
          ),
          if (!isCurrent)
            IconButton(
              tooltip: 'Remove from this list — does not sign the device out',
              icon: const Icon(Icons.close, size: 16),
              color: _textSecondary,
              onPressed: () => _removeSession(s['id']?.toString()),
            ),
        ],
      ),
    );
  }

  /// Ends every session except this one, after a confirmation. The dialog must
  /// say it covers ALL other devices and takes effect within the hour, because
  /// an access token stays valid until it expires.
  Future<void> _signOutOtherDevices() async {
    final others = _sessions
        .where((s) => s['id'] != SupabaseService.currentLoginSessionId)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out other devices?'),
        content: SizedBox(
          width: dialogContentWidth(context, 380),
          child: Text(
            'This signs out every device except the one you are using'
            '${others == 0 ? '' : ' — $others other ${others == 1 ? 'entry' : 'entries'} in your list'}. '
            'You will stay signed in here.\n\n'
            'Those devices lose access within the hour rather than straight '
            'away: an already-issued token stays valid until it expires. If '
            'you think someone else has your password, change it as well — '
            'otherwise they can simply sign back in.',
            // Not const: `_textSecondary` is a getter, a compile error in const.
            style: TextStyle(
                fontSize: 12.5, color: _textSecondary, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign Out Others')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _signingOutOthers = true);
    try {
      await SupabaseService.instance.signOutOtherDevices();
      if (!mounted) return;
      // Reload, because the service also cleared the other sign-in records.
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Other devices signed out. They lose access within the hour.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not sign out other devices. ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _signingOutOthers = false);
    }
  }

  /// Deletes the sign-in record only. The device stays signed in until its
  /// token expires; [_signOutOtherDevices] is what actually ends sessions.
  Future<void> _removeSession(String? id) async {
    if (id == null) return;
    try {
      await SupabaseService.instance.client.from('login_sessions').delete().eq('id', id);
      if (!mounted) return;
      setState(() => _sessions = _sessions.where((s) => s['id'] != id).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove. ${friendlyError(e)}')));
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  /// White titled card, styled for the officer or resident theme.
  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(widget.officer ? 12 : 16),
        boxShadow: widget.officer ? null : ResidentColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textPrimary)),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  /// Labelled grey box for a value that cannot be edited here.
  Widget _readOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _textSecondary)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6F4),
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(value.isEmpty ? '—' : value,
              style: TextStyle(fontSize: 13.5, color: _textSecondary)),
        ),
      ],
    );
  }

  /// Labelled text box.
  Widget _field(String label, TextEditingController controller,
      {bool obscure = false,
      String? Function(String?)? validator,
      List<TextInputFormatter>? inputFormatters,
      TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _textSecondary)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          inputFormatters: inputFormatters,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 13.5, color: _textPrimary),
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          ),
        ),
      ],
    );
  }
}
