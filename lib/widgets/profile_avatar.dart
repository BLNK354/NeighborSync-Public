import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../core/safe_state.dart';

/// Turns the stored profile photo value into a signed URL to display, or null.
/// The value is a path in the private `avatars` bucket; a full URL is also accepted.
Future<String?> resolveProfilePhoto(String? stored) async {
  final raw = stored?.trim() ?? '';
  if (raw.isEmpty) return null;
  var path = raw;
  const marker = '/avatars/';
  final i = path.indexOf(marker);
  if (path.startsWith('http') && i >= 0) path = path.substring(i + marker.length);
  final q = path.indexOf('?');
  if (q >= 0) path = path.substring(0, q);
  if (path.isEmpty) return null;
  try {
    return await SupabaseService.instance.client.storage
        .from('avatars')
        .createSignedUrl(path, 60 * 60 * 6);
  } catch (_) {
    return null;
  }
}

/// Holds the signed-in person's photo URL, shared by the top-bar avatar and Profile screen.
class MyPhoto extends ValueNotifier<String?> {
  MyPhoto._() : super(null);
  static final MyPhoto instance = MyPhoto._();

  String? _loadedFor;

  /// Loads the photo once per signed-in account, and reloads if the account changes.
  Future<void> ensureLoaded() async {
    final uid = SupabaseService.instance.client.auth.currentUser?.id;
    if (uid == null) {
      _loadedFor = null;
      value = null;
      return;
    }
    if (_loadedFor == uid) return;
    _loadedFor = uid;
    value = null;
    try {
      final p = await SupabaseService.instance.getMyProfile();
      value = await resolveProfilePhoto(p?['profile_photo_url'] as String?);
    } catch (_) {
      _loadedFor = null;
    }
  }

  /// Called after an upload with the new signed URL.
  void set(String? signedUrl) {
    _loadedFor = SupabaseService.instance.client.auth.currentUser?.id;
    value = signedUrl;
  }
}

/// A circle showing the person's photo, or a person icon when there is none
/// or it fails to load.
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.radius,
    required this.background,
    required this.iconColor,
  });

  final double radius;
  final Color background;
  final Color iconColor;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> with SafeSetState<ProfileAvatar> {
  @override
  void initState() {
    super.initState();
    MyPhoto.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.person_outline,
        size: widget.radius, color: widget.iconColor);
    return ValueListenableBuilder<String?>(
      valueListenable: MyPhoto.instance,
      builder: (context, url, _) => CircleAvatar(
        radius: widget.radius,
        backgroundColor: widget.background,
        child: url == null
            ? icon
            : ClipOval(
                child: Image.network(
                  url,
                  width: widget.radius * 2,
                  height: widget.radius * 2,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => icon,
                ),
              ),
      ),
    );
  }
}
