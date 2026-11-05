import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/module_registry.dart';
import '../core/permissions.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/responsive_officer_shell.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/safe_state.dart';
import '../core/stored_file.dart';

/// Officer Documents library, organised in folders like Google Drive.
/// Files go to a private bucket; the `documents` row holds path, type, size
/// and folder. A folder's `visible_roles` (empty = everyone who can read
/// documents) is enforced by RLS, so the screen shows what the user may see.
///
/// Deleting a file is a soft delete (`deleted_at`). Deleting a folder is
/// real; its files fall back to the root.
class AdminDocumentsScreen extends StatefulWidget {
  const AdminDocumentsScreen({super.key});

  @override
  State<AdminDocumentsScreen> createState() => _AdminDocumentsScreenState();
}

class _AdminDocumentsScreenState extends State<AdminDocumentsScreen>
    with SafeSetState<AdminDocumentsScreen>, TableSortState {
  // Current page (1-based) for the pager.
  int _page = 1;

  /// Files as a list (default) or as Drive-style tiles.
  bool _gridView = false;


  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _folders = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  int? _currentFolderId; // null = root

  // Current user and permissions. An uploader can always edit/delete their
  // own file; folders and other people's files need update/delete.
  int? _myId;
  bool _canManageDocs = false; // documents:update
  bool _canDeleteDocs = false; // documents:delete

  /// Uploading needs documents:create; read-only roles reach this screen too.
  bool _canUploadDocs = false;

  bool _ownsFile(Map<String, dynamic> d) => _myId != null && d['uploaded_by'] == _myId;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = SupabaseService.instance.client;
      final results = await Future.wait<dynamic>([
        c
            .from('documents')
            .select('*, uploader:uploaded_by(first_name, last_name)')
            .filter('deleted_at', 'is', null)
            .order('created_at', ascending: false)
            .limit(500),
        c.from('document_folders').select('*').order('name'),
        SupabaseService.instance.getMyUserId(),
        SupabaseService.instance.getMyPermissions(),
      ]);
      if (!mounted) return;
      final perms = results[3] as Map<String, Set<String>>;
      setState(() {
        _docs = List<Map<String, dynamic>>.from(results[0] as List);
        _folders = List<Map<String, dynamic>>.from(results[1] as List);
        _myId = results[2] as int?;
        _canManageDocs = canPerform(perms, 'documents', 'update');
        _canDeleteDocs = canPerform(perms, 'documents', 'delete');
        _canUploadDocs = canPerform(perms, 'documents', 'create');
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

  // ---- derived views ----
  List<Map<String, dynamic>> get _childFolders =>
      _folders.where((f) => f['parent_id'] == _currentFolderId).toList();

  List<Map<String, dynamic>> get _childFiles =>
      _docs.where((d) => d['folder_id'] == _currentFolderId).toList();

  /// Root -> ... -> current, for the breadcrumb.
  List<Map<String, dynamic>> get _breadcrumb {
    final path = <Map<String, dynamic>>[];
    int? id = _currentFolderId;
    var guard = 0;
    while (id != null && guard++ < 50) {
      final f = _folders.firstWhere((x) => x['id'] == id, orElse: () => {});
      if (f.isEmpty) break;
      path.insert(0, f);
      id = f['parent_id'] as int?;
    }
    return path;
  }

  List<String> _rolesOf(Map<String, dynamic> folder) =>
      (folder['visible_roles'] as List?)?.map((e) => e.toString()).toList() ??
      [];

  // Badge text: "HOA Members" by default, "Everyone" once shared with
  // non-HOA members.
  String _visibilityLabel(Map<String, dynamic> folder) =>
      folder['member_visible'] == true ? 'Everyone' : 'HOA Members';

  int get _total => _docs.length;
  int get _folderCount => _folders.length;
  int get _totalBytes =>
      _docs.fold(0, (sum, d) => sum + (d['size_bytes'] as num? ?? 0).toInt());

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return '—';
    return [p['first_name'], p['last_name']]
        .where((s) => s != null && s.toString().isNotEmpty)
        .join(' ');
  }

  // ---- file actions ----
  /// Picks a file, stores it, and adds it to the current folder.
  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _snack('Could not read that file -- try again.', error: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      final profile = await SupabaseService.instance.getMyProfile();
      final myId = profile?['id'];
      if (myId == null) throw Exception('Could not resolve your user id.');

      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$myId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final client = SupabaseService.instance.client;
      await client.storage.from('documents').uploadBinary(path, bytes);

      // A file in a shared folder is public so residents can see it.
      final currentFolder = _folders.firstWhere(
          (x) => x['id'] == _currentFolderId,
          orElse: () => const {});
      final inheritsPublic = currentFolder['member_visible'] == true;
      await client.from('documents').insert({
        'name': file.name,
        'original_name': file.name,
        'mime_type': _mimeFor(file.extension),
        'size_bytes': bytes.length,
        'storage_path': path,
        'category': 'general',
        'uploaded_by': myId,
        'is_public': inheritsPublic,
        'folder_id': _currentFolderId,
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

  /// Guesses the file type from its extension.
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
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      default:
        return 'application/octet-stream';
    }
  }

  /// Opens or downloads the file.
  Future<void> _download(Map<String, dynamic> d) async {
    // Photos from announcements and events are in the public bucket; use their link.
    final pub = (d['public_url'] ?? '').toString();
    final path = d['storage_path'] as String?;
    if (pub.isEmpty && path == null) return;
    try {
      await openStoredFile(
        context,
        path: pub.isEmpty ? path : null,
        publicUrl: pub,
        name: d['name']?.toString(),
        mimeType: d['mime_type']?.toString(),
      );
    } catch (e) {
      _snack('Could not generate a download link. ${friendlyError(e)}', error: true);
    }
  }

  /// Soft-deletes a file after confirming.
  Future<void> _delete(Map<String, dynamic> d) async {
    final confirm = await _confirm(
        'Delete document?',
        '"${d['name']}" will be removed from this list. The file itself isn\'t purged '
            '(there\'s no restore feature yet, so this can\'t be undone from the UI).');
    if (!confirm) return;
    try {
      await SupabaseService.instance.client.from('documents').update(
          {'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', d['id']);
      _load();
    } catch (e) {
      _snack('Delete failed. ${friendlyError(e)}', error: true);
    }
  }

  Future<void> _editMeta(Map<String, dynamic> d) async {
    final saved = await showModuleFormDialog(context, documents, initial: d);
    if (saved == true) _load();
  }

  Future<void> _moveFile(Map<String, dynamic> d) async {
    final choice = await _pickFolderDialog(currentId: d['folder_id'] as int?);
    if (choice == null) return; // cancelled (barrier dismiss)
    final int? target = choice == 'ROOT' ? null : choice as int;
    try {
      await SupabaseService.instance.client
          .from('documents')
          .update({'folder_id': target}).eq('id', d['id']);
      _load();
    } catch (e) {
      _snack('Move failed. ${friendlyError(e)}', error: true);
    }
  }

  // ---- folder actions ----
  Future<void> _createFolder() async {
    final res = await _folderDialog();
    if (res == null) return;
    try {
      final client = SupabaseService.instance.client;
      final myId = (await SupabaseService.instance.getMyProfile())?['id'];
      final inserted = await client
          .from('document_folders')
          .insert({
            'name': res.name,
            'parent_id': _currentFolderId,
            'visible_roles': res.roles,
            'member_visible': res.memberVisible,
            if (myId != null) 'created_by': myId,
          })
          .select('id')
          .single();
      await _syncFolderMemberVisibility(
          inserted['id'] as int, res.memberVisible);
      _load();
    } catch (e) {
      _snack('Could not create folder. ${friendlyError(e)}', error: true);
    }
  }

  Future<void> _editFolder(Map<String, dynamic> f) async {
    final res = await _folderDialog(initial: f);
    if (res == null) return;
    try {
      await SupabaseService.instance.client.from('document_folders').update({
        'name': res.name,
        'visible_roles': res.roles,
        'member_visible': res.memberVisible,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', f['id']);
      // Copy the folder's sharing onto its files so residents see the change.
      await _syncFolderMemberVisibility(f['id'] as int, res.memberVisible);
      _load();
    } catch (e) {
      _snack('Could not update folder. ${friendlyError(e)}', error: true);
    }
  }

  /// Sets `is_public` on every live file in [folderId] to match the folder's
  /// sharing; the resident page lists only public files.
  Future<void> _syncFolderMemberVisibility(
      int folderId, bool memberVisible) async {
    await SupabaseService.instance.client
        .from('documents')
        .update({'is_public': memberVisible})
        .eq('folder_id', folderId)
        .filter('deleted_at', 'is', null);
  }

  Future<void> _deleteFolder(Map<String, dynamic> f) async {
    final childFolders =
        _folders.where((x) => x['parent_id'] == f['id']).length;
    final childFiles = _docs.where((x) => x['folder_id'] == f['id']).length;
    final confirm = await _confirm(
        'Delete folder?',
        'Delete "${f['name']}"?'
            '${childFolders > 0 ? '\n\nIt has $childFolders sub-folder(s) which will also be deleted.' : ''}'
            '${childFiles > 0 ? '\n\n$childFiles file(s) inside will move back to the root (not deleted).' : ''}');
    if (!confirm) return;
    try {
      await SupabaseService.instance.client
          .from('document_folders')
          .delete()
          .eq('id', f['id']);
      _load();
    } catch (e) {
      _snack('Delete failed. ${friendlyError(e)}', error: true);
    }
  }

  // ---- dialogs ----
  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    return r == true;
  }

  /// Create/rename a folder, choose which officer roles can see it, and
  /// optionally share it with non-HOA members (residents & tenants).
  /// Returns null on cancel.
  Future<({String name, List<String> roles, bool memberVisible})?>
      _folderDialog({Map<String, dynamic>? initial}) async {
    final nameCtrl =
        TextEditingController(text: initial?['name']?.toString() ?? '');
    final selected = <String>{
      ...(initial == null ? const <String>[] : _rolesOf(initial))
    };
    var memberVisible = initial?['member_visible'] == true;
    // Sharing makes files public, so it must be re-confirmed each time it is ticked.
    var confirmedMemberVisible = false;
    return showDialog<({String name, List<String> roles, bool memberVisible})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(initial == null ? 'New folder' : 'Edit folder'),
          content: SizedBox(
            width: dialogContentWidth(context, 380),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Folder name',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 18),
                  const Text('Share with non-HOA members',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  const Text(
                      'When on, residents and tenants can see this folder and every file inside it from their Documents page.',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: memberVisible,
                    activeColor: const Color(0xFFA82F2F),
                    title: const Text(
                        'Non-HOA members (residents & tenants) can see this folder',
                        style: TextStyle(fontSize: 12.5)),
                    subtitle: memberVisible
                        ? Text(
                            confirmedMemberVisible
                                ? 'Confirmed — files in this folder will be public to members.'
                                : 'Please confirm below.',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: confirmedMemberVisible
                                    ? const Color(0xFF1A6B43)
                                    : const Color(0xFFA82F2F)))
                        : null,
                    onChanged: (v) => setLocal(() {
                      memberVisible = v == true;
                      confirmedMemberVisible = false;
                    }),
                  ),
                  if (memberVisible)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: confirmedMemberVisible,
                        title: const Text(
                            'I confirm making this folder visible to all residents and tenants',
                            style: TextStyle(fontSize: 12)),
                        onChanged: (v) =>
                            setLocal(() => confirmedMemberVisible = v == true),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              // Disabled until sharing is confirmed.
              onPressed: (memberVisible && !confirmedMemberVisible)
                  ? null
                  : () {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      Navigator.pop(context, (
                        name: name,
                        roles: selected.toList(),
                        memberVisible: memberVisible
                      ));
                    },
              child: Text(initial == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Pick a destination folder for a file. Returns null on cancel (barrier
  /// dismiss), the string 'ROOT' for the root, or an int folder id.
  Future<Object?> _pickFolderDialog({int? currentId}) async {
    return showDialog<Object?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to…'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'ROOT'),
            child: Row(children: [
              const Icon(Icons.home_outlined,
                  size: 18, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Text('Root',
                  style: TextStyle(
                      fontWeight: currentId == null
                          ? FontWeight.w700
                          : FontWeight.w400)),
            ]),
          ),
          for (final f in _folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f['id'] as int),
              child: Row(children: [
                const Icon(Icons.folder_outlined,
                    size: 18, color: Color(0xFF8A6300)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(f['name'].toString(),
                      style: TextStyle(
                          fontWeight: currentId == f['id']
                              ? FontWeight.w700
                              : FontWeight.w400)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg), backgroundColor: error ? Colors.redAccent : null),
    );
  }

  /// 0 Name · 1 Size · 2 Uploaded by · 3 Date
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> d, int col) {
    switch (col) {
      case 0:
        return text(d['name'] ?? d['original_name']);
      case 1:
        return number(d['size_bytes']);
      case 2:
        return text(_name(d['uploader'] as Map<String, dynamic>?));
      case 3:
        return date(d['created_at']);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: 'Documents',
      activeItem: 'Documents',
      activeTab: 'Home',
      desktopChild: _body(desktop: true),
      mobileChild: _body(desktop: false),
    );
  }

  // ---------------------------------------------------------------------
  // Layout: breadcrumb title with a "New" menu, a storage summary line,
  // folder tiles, then files as a list or tiles.
  // ---------------------------------------------------------------------

  static const _driveTile = Color(0xFFF1F3F4);
  static const _driveTileHover = Color(0xFFE3E7EA);

  Widget _body({required bool desktop}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child:
              Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    }
    final pad = desktop ? 24.0 : 16.0;
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(desktop ? 24 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _toolbar(desktop: desktop),
            const SizedBox(height: 6),
            _storageLine(),
            const SizedBox(height: 22),
            _foldersSection(),
            _filesSection(desktop: desktop),
          ],
        ),
      ),
    );
  }

  Widget _toolbar({required bool desktop}) {
    final canNew = _canManageDocs || _canUploadDocs;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _breadcrumbBar()),
        if (canNew)
          PopupMenuButton<String>(
            tooltip: 'New',
            offset: const Offset(0, 46),
            onSelected: (v) {
              if (v == 'folder') _createFolder();
              if (v == 'upload') _upload();
            },
            itemBuilder: (context) => [
              // New folder needs documents:update, not create, so uploaders can't restructure folders.
              if (_canManageDocs)
                const PopupMenuItem(
                  value: 'folder',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.create_new_folder_outlined, size: 20),
                    title: Text('New folder'),
                  ),
                ),
              if (_canUploadDocs)
                const PopupMenuItem(
                  value: 'upload',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.upload_file_outlined, size: 20),
                    title: Text('File upload'),
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _uploading
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add, size: 22, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Text(_uploading ? 'Uploading...' : 'New',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ]),
            ),
          ),
      ],
    );
  }

  /// The folder path ("Documents > Rule Book > 2026"); tap a part to jump there.
  Widget _breadcrumbBar() {
    final crumbs = _breadcrumb;
    Widget crumb(String label, VoidCallback onTap, {required bool last}) => InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(label,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: last ? FontWeight.w600 : FontWeight.w400,
                    color: last ? AppColors.textPrimary : AppColors.textSecondary)),
          ),
        );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        crumb('Documents', () => setState(() => _currentFolderId = null), last: crumbs.isEmpty),
        for (var i = 0; i < crumbs.length; i++) ...[
          const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
          crumb(crumbs[i]['name'].toString(),
              () => setState(() => _currentFolderId = crumbs[i]['id'] as int),
              last: i == crumbs.length - 1),
        ],
      ],
    );
  }

  /// One line with file count, folder count and space used.
  Widget _storageLine() {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(children: [
        const Icon(Icons.cloud_outlined, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text('$_total files \u00b7 $_folderCount folders \u00b7 ${_formatBytes(_totalBytes)} used',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]),
    );
  }

  Widget _sectionLabel(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 12),
        child: Row(children: [
          Expanded(
            child: Text(t,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          if (trailing != null) trailing,
        ]),
      );

  Widget _foldersSection() {
    final folders = _childFolders;
    if (folders.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Folders'),
          // Every tile gets the same width and height.
          LayoutBuilder(builder: (context, c) {
            const gap = 12.0;
            final cols = (c.maxWidth / 230).floor().clamp(1, 6);
            final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final f in folders) SizedBox(width: w, height: 52, child: _folderCard(f))],
            );
          }),
        ],
      ),
    );
  }

  /// One folder tile; tap to open it.
  Widget _folderCard(Map<String, dynamic> f) {
    final shared = f['member_visible'] == true;
    return _HoverTile(
      color: _driveTile,
      hoverColor: _driveTileHover,
      onTap: () => setState(() {
        _currentFolderId = f['id'] as int;
        _page = 1;
      }),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.folder, color: Color(0xFF5F6368), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Tooltip(
              message: _visibilityLabel(f),
              child: Text(f['name'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
          ),
          if (shared)
            const Tooltip(
              message: 'Shared with members',
              child: Icon(Icons.people_alt_outlined, size: 16, color: AppColors.textMuted),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
            onSelected: (v) {
              if (v == 'open') setState(() => _currentFolderId = f['id'] as int);
              if (v == 'edit') _editFolder(f);
              if (v == 'delete') _deleteFolder(f);
            },
            // Edit needs documents:update and delete needs documents:delete; others only Open.
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'open', child: Text('Open')),
              if (_canManageDocs) const PopupMenuItem(value: 'edit', child: Text('Edit / sharing')),
              if (_canDeleteDocs) const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filesSection({required bool desktop}) {
    final files = _childFiles;
    final toggle = Row(mainAxisSize: MainAxisSize.min, children: [
      _viewToggle(Icons.view_list_outlined, 'List view', !_gridView, () => setState(() => _gridView = false)),
      _viewToggle(Icons.grid_view_outlined, 'Grid view', _gridView, () => setState(() => _gridView = true)),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Files', trailing: files.isEmpty ? null : toggle),
        if (files.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE0E3E1)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(children: [
              Icon(Icons.folder_open_outlined, size: 36, color: AppColors.textMuted),
              SizedBox(height: 8),
              Text('No files in this folder yet.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ]),
          )
        else if (_gridView)
          _filesGrid(files)
        else if (desktop)
          _filesTable(files)
        else
          Column(children: [
            for (final d in pageSlice(sortRows(files), _page)) _fileCard(d),
            pagerFor(files.length, _page, (p) => setState(() => _page = p)),
          ]),
      ],
    );
  }

  Widget _viewToggle(IconData icon, String tip, bool on, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: on ? AppColors.badgeGreenBg : Colors.transparent,
              border: Border.all(color: const Color(0xFFC4C9C6)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 18, color: on ? AppColors.sidebarActiveText : AppColors.textSecondary),
          ),
        ),
      );

  /// Icon and colour for a file, chosen from its extension.
  ({IconData icon, Color color}) _typeOf(Map<String, dynamic> d) {
    final name = (d['name'] ?? '').toString().toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : '';
    switch (ext) {
      case 'pdf':
        return (icon: Icons.picture_as_pdf, color: const Color(0xFFD93025));
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return (icon: Icons.image, color: const Color(0xFFD93025));
      case 'doc':
      case 'docx':
      case 'txt':
        return (icon: Icons.description, color: const Color(0xFF1A73E8));
      case 'xls':
      case 'xlsx':
      case 'csv':
        return (icon: Icons.table_chart, color: const Color(0xFF188038));
      case 'ppt':
      case 'pptx':
        return (icon: Icons.slideshow, color: const Color(0xFFF9AB00));
      default:
        return (icon: Icons.insert_drive_file, color: const Color(0xFF5F6368));
    }
  }

  PopupMenuButton<String> _fileMenu(Map<String, dynamic> d) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
        onSelected: (v) {
          if (v == 'download') _download(d);
          if (v == 'move') _moveFile(d);
          if (v == 'edit') _editMeta(d);
          if (v == 'delete') _delete(d);
        },
        // Uploaders can change their own files; others are download-only without permission.
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'download', child: Text('Download')),
          if (_ownsFile(d) || _canManageDocs) ...[
            const PopupMenuItem(value: 'move', child: Text('Move')),
            const PopupMenuItem(value: 'edit', child: Text('Rename / details')),
          ],
          if (_ownsFile(d) || _canDeleteDocs)
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );

  String _modified(Map<String, dynamic> d) {
    final dt = DateTime.tryParse((d['created_at'] ?? '').toString())?.toLocal();
    if (dt == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _filesTable(List<Map<String, dynamic>> files) {
    return fullWidthTable(
      footer: pagerFor(files.length, _page, (p) => setState(() => _page = p)),
      DataTable(
        showCheckboxColumn: false,
        sortColumnIndex: sortColumn,
        sortAscending: sortAsc,
        columnSpacing: 28,
        horizontalMargin: 12,
        headingRowHeight: 40,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 52,
        dividerThickness: 0.6,
        headingTextStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        dataTextStyle: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        columns: [
          DataColumn(label: const Text('Name'), onSort: onSort),
          DataColumn(label: const Text('File size'), onSort: onSort),
          DataColumn(label: const Text('Owner'), onSort: onSort),
          DataColumn(label: const Text('Last modified'), onSort: onSort),
          const DataColumn(label: Text('')),
        ],
        rows: [
          for (final d in pageSlice(sortRows(files), _page))
            DataRow(
              // Clicking a row downloads the file.
              onSelectChanged: (_) => _download(d),
              cells: [
                DataCell(Row(children: [
                  Icon(_typeOf(d).icon, size: 20, color: _typeOf(d).color),
                  const SizedBox(width: 12),
                  Flexible(
                      child: Text((d['name'] ?? '').toString(),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500))),
                ])),
                DataCell(Text(_formatBytes((d['size_bytes'] as num? ?? 0).toInt()),
                    style: const TextStyle(color: AppColors.textSecondary))),
                DataCell(Text(_name(d['uploader'] as Map<String, dynamic>?),
                    style: const TextStyle(color: AppColors.textSecondary))),
                DataCell(Text(_modified(d), style: const TextStyle(color: AppColors.textSecondary))),
                DataCell(_fileMenu(d)),
              ],
            ),
        ],
      ),
    );
  }

  /// Files as tiles: file name on top, a large type icon below.
  Widget _filesGrid(List<Map<String, dynamic>> files) {
    return Column(children: [
      LayoutBuilder(builder: (context, c) {
        const gap = 12.0;
        final cols = (c.maxWidth / 200).floor().clamp(2, 6);
        final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final d in pageSlice(sortRows(files), _page))
              SizedBox(
                width: w,
                height: 190,
                child: _HoverTile(
                  color: _driveTile,
                  hoverColor: _driveTileHover,
                  onTap: () => _download(d),
                  child: Column(children: [
                    Row(children: [
                      const SizedBox(width: 12),
                      Icon(_typeOf(d).icon, size: 18, color: _typeOf(d).color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text((d['name'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ),
                      _fileMenu(d),
                    ]),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Icon(_typeOf(d).icon, size: 52, color: _typeOf(d).color.withValues(alpha: 0.85)),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        );
      }),
      pagerFor(files.length, _page, (p) => setState(() => _page = p)),
    ]);
  }

  /// Phone list row: type icon, name, size and owner, the same menu.
  Widget _fileCard(Map<String, dynamic> d) {
    return InkWell(
      onTap: () => _download(d),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(_typeOf(d).icon, size: 26, color: _typeOf(d).color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((d['name'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('${_formatBytes((d['size_bytes'] as num? ?? 0).toInt())} \u00b7 ${_modified(d)}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
            _fileMenu(d),
          ],
        ),
      ),
    );
  }
}

/// A grey tile that darkens on hover and shows a hand cursor.
class _HoverTile extends StatefulWidget {
  final Color color;
  final Color hoverColor;
  final VoidCallback onTap;
  final Widget child;
  const _HoverTile({required this.color, required this.hoverColor, required this.onTap, required this.child});

  @override
  State<_HoverTile> createState() => _HoverTileState();
}

class _HoverTileState extends State<_HoverTile> with SafeSetState<_HoverTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hover ? widget.hoverColor : widget.color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
