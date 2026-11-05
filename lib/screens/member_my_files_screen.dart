import '../widgets/responsive_officer_shell.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/form_helpers.dart';
import '../services/supabase_service.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/safe_state.dart';
import '../core/stored_file.dart';
import '../core/personal_folders.dart';
import '../core/dialog_controllers.dart';

/// "My Files": a personal drive for uploading permits, IDs and receipts.
/// Residents' files are visible to them and to reviewing officers.
///
/// Files go under `<user_id>/personal/...` so storage rules limit them to the
/// uploader's own folder.
///
/// With [officer] set, this is an officer's own drive. Those files are
/// `is_private`: only the uploader can read them, not even the admin.
class MemberMyFilesScreen extends StatefulWidget {
  const MemberMyFilesScreen({super.key, this.officer = false});

  final bool officer;

  @override
  State<MemberMyFilesScreen> createState() => _MemberMyFilesScreenState();
}

class _MemberMyFilesScreenState extends State<MemberMyFilesScreen> with SafeSetState<MemberMyFilesScreen> {
  /// Folders this person made. Built-in folders come from
  /// core/personal_folders.dart.
  List<Map<String, dynamic>> _folders = const [];

  List<String> get _builtIns =>
      widget.officer ? kOfficerBuiltInFolders : kResidentBuiltInFolders;

  List<String> get _categories => folderOrder(
      _builtIns, _folders.map((f) => (f['name'] ?? '').toString()));

  Map<String, dynamic>? _customFolder(String name) {
    for (final f in _folders) {
      if ((f['name'] ?? '').toString().toLowerCase() == name.toLowerCase()) return f;
    }
    return null;
  }

  /// One line telling who can read the files shown.
  String get _privacyNote {
    if (widget.officer) {
      return _openFolder == null
          ? 'Only you can open these files. No other officer can, including the admin.'
          : '${_filesInFolder.length} file${_filesInFolder.length == 1 ? '' : 's'} — visible only to you.';
    }
    return _openFolder == null
        ? 'Your private storage for permits, IDs and other documents.'
        : '${_filesInFolder.length} file${_filesInFolder.length == 1 ? '' : 's'} in this folder.';
  }

  /// Files here are hidden from the office. An officer's drive is private
  /// throughout; for a resident only a folder they made and did not share.
  bool _isPrivateFolder(String name) {
    if (widget.officer) return true;
    final f = _customFolder(name);
    return f != null && f['shared'] != true;
  }

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  /// Which folder is open, or null for the folder grid. A folder is the
  /// file's `documents.category` value.
  String? _openFolder;

  /// Files in the currently open folder.
  List<Map<String, dynamic>> get _filesInFolder =>
      _rows.where((d) => _folderOf(d) == _openFolder).toList();

  /// Folder of a file; a missing category counts as "Other".
  String _folderOf(Map<String, dynamic> d) {
    final c = (d['category'] ?? '').toString().trim();
    return c.isEmpty ? 'Other' : c;
  }

  /// Folder name -> file count, including empty folders.
  Map<String, int> get _folderCounts {
    final counts = <String, int>{for (final c in _categories) c: 0};
    for (final d in _rows) {
      final f = _folderOf(d);
      counts[f] = (counts[f] ?? 0) + 1;
    }
    return counts;
  }

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads this person's files and folders.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final myId = await SupabaseService.instance.getMyUserId();
      if (myId == null) throw Exception('Could not resolve your account.');
      // Filter on owner_id, not uploaded_by, so files the office filed for
      // this household show up too.
      var q = SupabaseService.instance.client
          .from('documents')
          .select('*, uploader:uploaded_by(first_name, last_name)')
          .eq('owner_id', myId)
          .eq('is_personal', true);
      // An officer's drive shows only their private files.
      if (widget.officer) q = q.eq('is_private', true);
      final data = await q.order('created_at', ascending: false).limit(300);
      List<Map<String, dynamic>> folders = const [];
      try {
        folders = await loadPersonalFolders(myId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _rows = List<Map<String, dynamic>>.from(data as List);
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

  String _mimeFor(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      default:
        return 'application/octet-stream';
    }
  }

  /// Picks a file, asks for a folder, then uploads it.
  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _snack('Could not read that file — try again.', error: true);
      return;
    }

    if (!mounted) return;
    // Folder choice defaults to the folder currently open.
    String category = _openFolder ?? _categories.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Upload file'),
          content: SizedBox(
            width: dialogContentWidth(context, 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                const Text('Folder', style: TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setLocal(() => category = v ?? category),
                ),
                const SizedBox(height: 10),
                Text(
                    _isPrivateFolder(category)
                        ? 'Only you can see files in this folder.'
                        : 'Only you and HOA officers can see this file.',
                    style: const TextStyle(fontSize: 11, color: ResidentColors.textSecondary)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Upload')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _uploading = true);
    try {
      final myId = await SupabaseService.instance.getMyUserId();
      if (myId == null) throw Exception('Could not resolve your account.');
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path =
          '$myId/${widget.officer ? 'private' : 'personal'}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final client = SupabaseService.instance.client;
      await client.storage.from('documents').uploadBinary(path, bytes);
      await client.from('documents').insert({
        'name': file.name,
        'original_name': file.name,
        'mime_type': _mimeFor(file.extension),
        'size_bytes': bytes.length,
        'storage_path': path,
        'category': category,
        'uploaded_by': myId,
        'is_public': false,
        'is_personal': true,
        'is_private': _isPrivateFolder(category),
      });
      if (!mounted) return;
      setState(() => _uploading = false);
      _snack('Uploaded "${file.name}".');
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _snack('Upload failed. ${friendlyError(e)}', error: true);
    }
  }

  /// Opens a file.
  Future<void> _view(Map<String, dynamic> d) async {
    final pub = (d['public_url'] ?? '').toString();
    final path = d['storage_path'] as String?;
    if (pub.isEmpty && path == null) {
      _snack('This file has no attachment.', error: true);
      return;
    }
    try {
      await openStoredFile(
        context,
        path: pub.isEmpty ? path : null,
        publicUrl: pub,
        name: d['name']?.toString(),
        mimeType: d['mime_type']?.toString(),
      );
    } catch (e) {
      _snack('Could not open that file. ${friendlyError(e)}', error: true);
    }
  }

  /// Deletes a file from storage and the list, after confirming.
  Future<void> _delete(Map<String, dynamic> d) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text('Permanently delete "${d['name']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA82F2F)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final client = SupabaseService.instance.client;
      final path = d['storage_path'] as String?;
      if (path != null) {
        await client.storage.from('documents').remove([path]);
      }
      await client.from('documents').delete().eq('id', d['id']);
      _snack('File deleted.');
      _load();
    } catch (e) {
      _snack('Delete failed. ${friendlyError(e)}', error: true);
    }
  }

  /// Asks for a name and creates a new folder.
  Future<void> _newFolder() async {
    final nameCtrl = TextEditingController();
    var shared = false;
    String? problem;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New folder'),
          content: SizedBox(
            width: dialogContentWidth(context, 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  maxLength: 40,
                  decoration: const InputDecoration(
                      labelText: 'Folder name', border: OutlineInputBorder()),
                ),
                if (!widget.officer)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: shared,
                    onChanged: (v) => setLocal(() => shared = v),
                    title: const Text('Share with the HOA office',
                        style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                        shared
                            ? 'Officers can see these files and add to this folder.'
                            : 'Only you can see files in this folder.',
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                if (problem != null)
                  Text(problem!,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFA82F2F))),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final n = nameCtrl.text.trim();
                if (n.isEmpty) {
                  setLocal(() => problem = 'Give the folder a name.');
                  return;
                }
                if (_categories.any((c) => c.toLowerCase() == n.toLowerCase())) {
                  setLocal(() => problem = 'You already have a folder called "$n".');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    disposeAfterDialogCloses([nameCtrl]);
    if (ok != true) return;
    try {
      final myId = await SupabaseService.instance.getMyUserId();
      await SupabaseService.instance.client.from('personal_folders').insert({
        'owner_id': myId,
        'name': name,
        'shared': widget.officer ? false : shared,
      });
      _snack('Folder "$name" created.');
      _load();
    } catch (e) {
      _snack('Could not create the folder. ${friendlyError(e)}', error: true);
    }
  }

  /// Share / make private / delete menu for a folder the person made.
  /// Built-in folders have no menu.
  Widget _folderMenu(Map<String, dynamic> f, int count) {
    final name = (f['name'] ?? '').toString();
    final isShared = f['shared'] == true;
    return PopupMenuButton<String>(
      tooltip: 'Folder options',
      icon: const Icon(Icons.more_vert, size: 18, color: ResidentColors.textSecondary),
      onSelected: (v) async {
        final client = SupabaseService.instance.client;
        try {
          if (v == 'share') {
            final myId = await SupabaseService.instance.getMyUserId();
            await client
                .from('personal_folders')
                .update({'shared': !isShared}).eq('id', f['id']);
            // Files follow the folder's sharing. Only the person's own
            // uploads change; files the office filed are left alone.
            await client
                .from('documents')
                .update({'is_private': isShared})
                .eq('owner_id', myId as Object)
                .eq('uploaded_by', myId as Object)
                .eq('category', name);
            _snack(isShared
                ? '"$name" is now private.'
                : '"$name" is now shared with the office.');
          } else if (v == 'delete') {
            if (count > 0) {
              _snack(
                  'Move or delete the $count file${count == 1 ? '' : 's'} in "$name" first.',
                  error: true);
              return;
            }
            await client.from('personal_folders').delete().eq('id', f['id']);
            _snack('Folder "$name" deleted.');
          }
          _load();
        } catch (e) {
          _snack('Could not update the folder. ${friendlyError(e)}', error: true);
        }
      },
      itemBuilder: (_) => [
        if (!widget.officer)
          PopupMenuItem(
              value: 'share',
              child: Text(isShared ? 'Make private' : 'Share with the HOA office')),
        const PopupMenuItem(value: 'delete', child: Text('Delete folder')),
      ],
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.redAccent : null),
    );
  }

  String _formatBytes(num? bytes) {
    final n = (bytes ?? 0).toInt();
    if (n <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = n.toDouble();
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final body = _body();
    if (widget.officer) {
      return ResponsiveOfficerShell(
        title: 'My Files',
        activeItem: 'My Files',
        activeTab: 'Home',
        desktopChild: body,
      );
    }
    return MemberShell(title: 'My Files', activeItem: 'My Files', child: body);
  }

  Widget _body() {
    return _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Breadcrumb; tapping "My Files" goes back.
                                if (_openFolder == null)
                                  const Text('My Files',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ResidentColors.textPrimary))
                                else
                                  Row(
                                    children: [
                                      InkWell(
                                        onTap: () => setState(() => _openFolder = null),
                                        child: const Text('My Files',
                                            style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: ResidentColors.textSecondary)),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 6),
                                        child: Icon(Icons.chevron_right,
                                            size: 18, color: ResidentColors.textSecondary),
                                      ),
                                      Text(_openFolder!,
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: ResidentColors.textPrimary)),
                                    ],
                                  ),
                                const SizedBox(height: 2),
                                // Privacy line, shown at the root and in folders.
                                Row(
                                  children: [
                                    const Icon(Icons.lock_outline,
                                        size: 13, color: ResidentColors.textSecondary),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        _privacyNote,
                                        style: const TextStyle(
                                            fontSize: 12, color: ResidentColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (_openFolder == null) ...[
                            OutlinedButton.icon(
                              onPressed: _newFolder,
                              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                              label: const Text('New Folder'),
                            ),
                            const SizedBox(width: 8),
                          ],
                          FilledButton.icon(
                            onPressed: _uploading ? null : _upload,
                            icon: _uploading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.upload_file_outlined, size: 18),
                            label: Text(_uploading ? 'Uploading…' : 'Upload'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_openFolder == null)
                        _folderGrid()
                      else if (_filesInFolder.isEmpty)
                        _emptyCard('Nothing in this folder yet. '
                            'Tap Upload and choose "$_openFolder".')
                      else
                        for (final d in _filesInFolder) _row(d),
                    ],
                  ),
                );
  }

  /// Moves a file to another folder by changing its category. The stored
  /// file itself is not moved.
  Future<void> _moveToFolder(Map<String, dynamic> d) async {
    var target = _folderOf(d);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Move to folder'),
          content: SizedBox(
            width: dialogContentWidth(context, 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((d['name'] ?? '').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: target,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [
                    for (final c in _categories) DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setLocal(() => target = v ?? target),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Move')),
          ],
        ),
      ),
    );
    if (ok != true || target == _folderOf(d)) return;
    try {
      await SupabaseService.instance.client.from('documents').update({
        'category': target,
        // The file takes on the privacy of the folder it moves into.
        if (!widget.officer) 'is_private': _isPrivateFolder(target),
      }).eq('id', d['id']);
      if (!mounted) return;
      _snack('Moved to $target.');
      _load();
    } catch (e) {
      if (mounted) _snack('Could not move the file. ${friendlyError(e)}', error: true);
    }
  }

  Widget _emptyCard(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: ResidentColors.cardShadow),
        child: Text(message,
            style: const TextStyle(fontSize: 12.5, color: ResidentColors.textSecondary)),
      );

  /// Folder tiles, sized to fill the row.
  Widget _folderGrid() {
    final counts = _folderCounts;
    return LayoutBuilder(builder: (context, box) {
      const gap = 16.0;
      // clamp(1, 0) throws, so guard against an empty folder list.
      var cols = ((box.maxWidth + gap) / (200 + gap)).floor().clamp(1, counts.isEmpty ? 1 : counts.length);
      while (cols > 2 && counts.length % cols == 1) {
        cols--;
      }
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final entry in counts.entries) _folderTile(entry.key, entry.value, w),
        ],
      );
    });
  }

  /// One folder tile; tap to open it.
  Widget _folderTile(String name, int count, double width) {
    final empty = count == 0;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () => setState(() => _openFolder = name),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: ResidentColors.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: empty ? ResidentColors.border : ResidentColors.iconAmberBg,
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(empty ? Icons.folder_outlined : Icons.folder,
                    size: 20, color: ResidentColors.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ResidentColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                        [
                          count == 0 ? 'Empty' : '$count file${count == 1 ? '' : 's'}',
                          if (!widget.officer && _customFolder(name) != null)
                            _isPrivateFolder(name) ? 'Private' : 'Shared with office',
                        ].join(' · '),
                        style: const TextStyle(
                            fontSize: 11.5, color: ResidentColors.textSecondary)),
                  ],
                ),
              ),
              if (_customFolder(name) != null) _folderMenu(_customFolder(name)!, count),
            ],
          ),
        ),
      ),
    );
  }

  /// One file in the open folder.
  Widget _row(Map<String, dynamic> d) {
    final ext = ((d['mime_type'] ?? '').toString().contains('pdf')) ? 'PDF' : 'FILE';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: ResidentColors.cardShadow),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ResidentColors.iconBlueBg, borderRadius: BorderRadius.circular(8)),
            child: Text(ext, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: ResidentColors.textPrimary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((d['name'] ?? 'File').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if ((d['category'] ?? '').toString().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: ResidentColors.iconGrayBg, borderRadius: BorderRadius.circular(6)),
                        child: Text((d['category'] ?? '').toString(),
                            style: const TextStyle(fontSize: 10.5, color: ResidentColors.textSecondary)),
                      ),
                    if (_formatBytes(d['size_bytes'] as num?).isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(_formatBytes(d['size_bytes'] as num?), style: const TextStyle(fontSize: 10.5, color: ResidentColors.textSecondary)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          TextButton(onPressed: () => _view(d), child: const Text('View')),
          IconButton(
            tooltip: 'Move to folder',
            icon: const Icon(Icons.drive_file_move_outlined,
                size: 18, color: ResidentColors.textSecondary),
            onPressed: () => _moveToFolder(d),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFA82F2F)),
            onPressed: () => _delete(d),
          ),
        ],
      ),
    );
  }
}
