/// CMS -> Official Forms -> User Guides.
///
/// Three PDF slots, one per audience, stored in the public `branding` bucket
/// with the link saved to `homepage.guide_*_url`. Kept apart from the other
/// forms because the Admin and Officers guides are shown only to those roles.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding.dart';
import '../core/form_helpers.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';
import '../core/safe_state.dart';
import '../core/stored_file.dart';

class UserGuidesCard extends StatefulWidget {
  final bool canEdit;
  const UserGuidesCard({super.key, required this.canEdit});

  @override
  State<UserGuidesCard> createState() => _UserGuidesCardState();
}

/// One guide: its settings key, label, who sees it, and file name prefix.
class _Slot {
  final String key;
  final String label;
  final String who;
  final String slug;
  const _Slot(this.key, this.label, this.who, this.slug);
}

const _slots = [
  _Slot('homepage.guide_admin_url', 'Administrator guide',
      'Shown to the system administrator.', 'admin'),
  _Slot('homepage.guide_officers_url', 'HOA Officers guide',
      'Shown to the President, Secretary, Treasurer, Security and Audit Officer.', 'officers'),
  _Slot('homepage.guide_residents_url', 'Residents & Others guide',
      'Shown to residents, tenants, guests and agents, and linked on the public home page.', 'residents'),
];

class _UserGuidesCardState extends State<UserGuidesCard> with SafeSetState<UserGuidesCard> {
  String? _busy;

  String? _urlFor(String key) {
    final b = AppBranding.instance;
    return switch (key) {
      'homepage.guide_admin_url' => b.guideAdminUrl,
      'homepage.guide_officers_url' => b.guideOfficersUrl,
      _ => b.guideResidentsUrl,
    };
  }

  /// Picks a PDF and saves it as this slot's guide.
  Future<void> _upload(_Slot slot) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      if (mounted) AppToast.error(context, message: 'Could not read that file.');
      return;
    }
    setState(() => _busy = slot.key);
    try {
      final client = SupabaseService.instance.client;
      // New path each time so old links keep the old document.
      final path = 'guides/${slot.slug}-${DateTime.now().millisecondsSinceEpoch}.pdf';
      await client.storage.from('branding').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true, contentType: 'application/pdf'),
          );
      final url = client.storage.from('branding').getPublicUrl(path);
      final updatedBy = await SupabaseService.instance.getMyUserId();
      await client.from('system_settings').upsert({
        'setting_key': slot.key,
        'value': url,
        'type': 'string',
        'category': 'homepage',
        'is_public': true,
        if (updatedBy != null) 'updated_by': updatedBy,
      }, onConflict: 'setting_key');
      await AppBranding.instance.load();
      if (mounted) AppToast.success(context, message: '${slot.label} uploaded.');
    } catch (e) {
      if (mounted) AppToast.error(context, message: 'Upload failed. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('User Guides',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text(
              'The printable guide for each group, as a PDF. Each person is offered only '
              'their own guide, from the ? menu beside the bell.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.45)),
          const SizedBox(height: 12),
          for (final slot in _slots) _row(slot),
        ],
      ),
    );
  }

  Widget _row(_Slot slot) {
    final url = _urlFor(slot.key);
    final busy = _busy == slot.key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(Icons.menu_book_outlined, size: 18,
              color: url == null ? AppColors.textMuted : AppColors.sidebarActiveText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.label, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                Text(url == null ? 'Not uploaded yet. ${slot.who}' : slot.who,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (url != null)
            IconButton(
              tooltip: 'Preview',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.open_in_new, size: 18, color: AppColors.textMuted),
              onPressed: () => openStoredFile(context, publicUrl: url).catchError((_) {}),
            ),
          if (widget.canEdit)
            busy
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(
                    onPressed: _busy != null ? null : () => _upload(slot),
                    child: Text(url == null ? 'Upload PDF' : 'Replace'),
                  ),
        ],
      ),
    );
  }
}
