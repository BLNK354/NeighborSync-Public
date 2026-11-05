import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/personal_folders.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../core/dialog_sizing.dart';
import '../core/form_helpers.dart';
import '../core/permissions.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../core/safe_state.dart';
import '../core/stored_file.dart';

/// Shows one person's private files to an officer, and lets an officer with
/// `documents:update` add files. Used by both Residents and Tenants.
///
/// `owner_id` is whose file it is; `uploaded_by` is who uploaded it. An
/// officer's upload has owner_id = the resident, uploaded_by = the officer.
Future<void> showPersonFilesDialog(
  BuildContext context, {
  required Object userId,
  required String personName,
  String roleLabel = 'resident',
}) async {
  await showDialog(
    context: context,
    builder: (context) => _PersonFilesDialog(
      userId: userId,
      personName: personName,
      roleLabel: roleLabel,
    ),
  );
}

class _PersonFilesDialog extends StatefulWidget {
  final Object userId;
  final String personName;
  final String roleLabel;

  const _PersonFilesDialog({
    required this.userId,
    required this.personName,
    required this.roleLabel,
  });

  @override
  State<_PersonFilesDialog> createState() => _PersonFilesDialogState();
}

class _PersonFilesDialogState extends State<_PersonFilesDialog> with SafeSetState<_PersonFilesDialog> {
  List<Map<String, dynamic>> _files = const [];
  bool _loading = true;
  bool _uploading = false;
  bool _canUpload = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        SupabaseService.instance.client
            .from('documents')
            .select('id, name, category, storage_path, created_at, uploaded_by, '
                'uploader:uploaded_by(first_name, last_name)')
            .eq('owner_id', widget.userId)
            .eq('is_personal', true)
            .order('created_at', ascending: false)
            .limit(200),
        SupabaseService.instance.getMyPermissions(),
      ]);
      if (!mounted) return;
      setState(() {
        _files = List<Map<String, dynamic>>.from(results[0] as List);
        // Mirrors the server-side check, so the button only shows if allowed.
        _canUpload =
            canPerform(results[1] as Map<String, Set<String>>, 'documents', 'update');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  /// Opens a file through a short-lived signed link (the bucket is private).
  Future<void> _open(String? path) async {
    if (path == null) return;
    try {
      await openStoredFile(context, path: path);
    } catch (e) {
      if (mounted) _snack('Could not open that file. ${friendlyError(e)}', error: true);
    }
  }

  /// Asks for a folder and a file, then uploads it to this person's files.
  Future<void> _upload() async {
    // Offer only folders shared with the office; private ones stay hidden.
    final ownerId = int.tryParse(widget.userId.toString());
    final folders = ownerId == null
        ? ([...kResidentBuiltInFolders]..sort())
        : await sharedFoldersFor(ownerId);
    if (!mounted || folders.isEmpty) return;
    var category = folders.contains('Other') ? 'Other' : folders.first;
    final picked = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          insetPadding: dialogInset(context),
          title: const Text('Add a file'),
          content: SizedBox(
            width: dialogContentWidth(context, 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This goes into ${widget.personName.trim().isEmpty ? 'this account' : widget.personName.trim()}\'s '
                  'files, where they can see it. The record will show that you '
                  'uploaded it.',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Folder',
                      helperText: 'Folders shared with the office, A-Z'),
                  items: [
                    for (final c in folders)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setLocal(() => category = v ?? category),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Choose file…')),
          ],
        ),
      ),
    );
    if (picked != true || !mounted) return;

    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _snack('Could not read that file — try another one.', error: true);
      return;
    }
    if (bytes.length > 15 * 1024 * 1024) {
      _snack('That file is over 15 MB. Please upload a smaller one.', error: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      final c = SupabaseService.instance.client;
      final me = await SupabaseService.instance.getMyUserId();
      if (me == null) throw Exception('Could not resolve your account.');
      final ext = (file.extension ?? 'bin').toLowerCase();
      // Stored under the owner's folder; documents_bucket_insert_staff
      // allows an officer to write there.
      final path =
          '${widget.userId}/office-${DateTime.now().millisecondsSinceEpoch}.$ext';

      await c.storage.from('documents').uploadBinary(
            path,
            bytes,
            // Do not use upsert: it also checks SELECT/UPDATE on a row that
            // does not exist yet, so the upload is refused.
            fileOptions: FileOptions(upsert: false, contentType: _mimeFor(ext)),
          );
      await c.from('documents').insert({
        'name': file.name,
        'original_name': file.name,
        'mime_type': _mimeFor(ext),
        'size_bytes': bytes.length,
        'storage_path': path,
        'category': category,
        'uploaded_by': me,      // who uploaded (RLS requires the caller)
        'owner_id': widget.userId, // whose file it is
        'is_personal': true,
      });
      if (!mounted) return;
      setState(() => _uploading = false);
      _snack('File added to ${widget.personName.trim()}\'s files.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _snack('Upload failed. ${friendlyError(e)}', error: true);
    }
  }

  static String _mimeFor(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'doc':
      case 'docx':
        return 'application/msword';
      default:
        return 'application/octet-stream';
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFA82F2F) : null,
    ));
  }

  /// "Added by ..." note, only when someone other than the owner uploaded it.
  String? _uploaderNote(Map<String, dynamic> d) {
    if (d['uploaded_by'].toString() == widget.userId.toString()) return null;
    final u = d['uploader'] as Map<String, dynamic>?;
    final n = [u?['first_name'], u?['last_name']].where((s) => s != null).join(' ').trim();
    return n.isEmpty ? 'Added by the office' : 'Added by $n';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.personName.trim();
    // List height: 160 to 340, scaled to the screen so phones fit.
    final viewport = MediaQuery.of(context).size.height * 0.42;
    final listMax = viewport < 160.0 ? 160.0 : (viewport > 340.0 ? 340.0 : viewport);
    return AlertDialog(
      insetPadding: dialogInset(context),
      title: Text('${name.isEmpty ? 'Account' : name} — Files'),
      content: SizedBox(
        width: dialogContentWidth(context, 440),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text(_error!,
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFA82F2F)))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_files.isEmpty)
                        Text("This ${widget.roleLabel} hasn't uploaded any files.",
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textSecondary))
                      else
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: listMax),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final d in _files)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.insert_drive_file_outlined,
                                        size: 20),
                                    title: Text((d['name'] ?? 'File').toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12.5)),
                                    subtitle: Builder(builder: (_) {
                                      final parts = <String>[
                                        if ((d['category'] ?? '').toString().isNotEmpty)
                                          (d['category']).toString(),
                                        if (_uploaderNote(d) != null) _uploaderNote(d)!,
                                      ];
                                      return parts.isEmpty
                                          ? const SizedBox.shrink()
                                          : Text(parts.join(' · '),
                                              style: const TextStyle(fontSize: 11));
                                    }),
                                    trailing: TextButton(
                                      onPressed: () => _open(d['storage_path'] as String?),
                                      child: const Text('View'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (_canUpload) ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _uploading ? null : _upload,
                          icon: _uploading
                              ? const SizedBox(
                                  height: 14,
                                  width: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.upload_file_outlined, size: 16),
                          label: Text(_uploading ? 'Uploading…' : 'Add a file'),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Use this for paperwork the office holds for this '
                          '${widget.roleLabel} — a scanned lease, a signed contract, '
                          'a notice. They will see it in My Files.',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textMuted, height: 1.45),
                        ),
                      ],
                    ],
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
