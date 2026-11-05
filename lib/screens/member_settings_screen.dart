import '../widgets/language_picker.dart';
import '../core/app_locale.dart' show tr;
import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../core/refresh_bus.dart';
import '../core/user_preferences.dart';
import '../widgets/guided_tour.dart';
import '../core/safe_state.dart';

const _timezones = ['GMT+8 Manila'];

/// Resident Settings: notification preferences, language and time zone.
/// Saved in the `preferences` JSON column on the user's row.
/// "Manage 2FA" opens the MFA setup page.
class MemberSettingsScreen extends StatefulWidget {
  const MemberSettingsScreen({super.key});

  @override
  State<MemberSettingsScreen> createState() => _MemberSettingsScreenState();
}

class _MemberSettingsScreenState extends State<MemberSettingsScreen> with SafeSetState<MemberSettingsScreen> {
  int? _myId;
  bool _loading = true;
  bool _saving = false;
  String? _message;

  bool _email = true;
  bool _push = true;
  bool _billing = true;
  bool _announcements = true;
  String _timezone = _timezones.first;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  Future<void> _load() async {
    try {
      final authUid = SupabaseService.instance.client.auth.currentUser?.id;
      final row = await SupabaseService.instance.client
          .from('users')
          .select('id, preferences')
          .eq('supabase_uid', authUid as Object)
          .maybeSingle();
      if (!mounted) return;
      final prefs = (row?['preferences'] as Map<String, dynamic>?) ?? const {};
      setState(() {
        _myId = row?['id'] as int?;
        _email = prefs['email_notifications'] ?? true;
        _push = prefs['push_notifications'] ?? true;
        _billing = prefs['billing_reminders'] ?? true;
        _announcements = prefs['announcement_alerts'] ?? true;
        _timezone = (prefs['timezone'] as String?) ?? _timezones.first;
        if (!_timezones.contains(_timezone)) _timezone = _timezones.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Could not load settings. ${friendlyError(e)}';
      });
    }
  }

  Future<void> _save() async {
    if (_myId == null) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      // Merge, never replace: `preferences` also holds keys this screen does
      // not know (e.g. the tour's "already seen" flag).
      await patchMyPreferences(_myId as int, {
        'email_notifications': _email,
        'push_notifications': _push,
        'billing_reminders': _billing,
        'announcement_alerts': _announcements,
        'timezone': _timezone,
      });
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Settings saved.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Could not save. ${friendlyError(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'Settings',
      activeItem: 'Settings',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: ResidentColors.cardShadow),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Notification Preferences'),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                        const SizedBox(height: 8),
                        _toggleRow('Email notifications', _email, (v) => setState(() => _email = v)),
                        _toggleRow('Push notifications', _push, (v) => setState(() => _push = v)),
                        _toggleRow('Billing & dues reminders', _billing, (v) => setState(() => _billing = v)),
                        _toggleRow('Announcement alerts', _announcements, (v) => setState(() => _announcements = v)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: ResidentColors.cardShadow),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Preferences'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 20,
                          runSpacing: 16,
                          children: [
                            // Applies immediately, to this account only.
                            const LanguagePicker(),
                            SizedBox(
                              width: 260,
                              child: DropdownButtonFormField<String>(
                                initialValue: _timezone,
                                decoration: InputDecoration(labelText: tr('Time Zone')),
                                items: [for (final t in _timezones) DropdownMenuItem(value: t, child: Text(t))],
                                onChanged: (v) => setState(() => _timezone = v ?? _timezones.first),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextButton.icon(
                          onPressed: () => context.go('/mfa-setup'),
                          icon: const Icon(Icons.shield_outlined, size: 16),
                          label: Text(tr('Manage 2FA')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _replayTutorialRow(),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      FilledButton(onPressed: _saving ? null : _save, child: Text(tr(_saving ? 'Saving…' : 'Save Settings'))),
                      if (_message != null) ...[
                        const SizedBox(width: 12),
                        Text(_message!, style: const TextStyle(fontSize: 12.5, color: ResidentColors.textSecondary)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  /// Button row that replays the first-time tutorial over the current screen
  /// (it does not navigate).
  Widget _replayTutorialRow() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ResidentColors.iconGrayBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Replay the tutorial',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ResidentColors.textPrimary)),
                SizedBox(height: 2),
                Text(
                    'Walks you through the portal again, and shows each screen\'s tips again.',
                    style: TextStyle(
                        fontSize: 12, color: ResidentColors.textSecondary)),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: TourController.replay,
            icon: const Icon(Icons.play_circle_outline, size: 16),
            label: const Text('Replay'),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(tr(label), style: const TextStyle(fontSize: 13, color: ResidentColors.textPrimary))),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
