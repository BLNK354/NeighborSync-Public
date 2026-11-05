import 'package:flutter/material.dart';
import '../widgets/image_lightbox.dart';
import '../widgets/community_calendar.dart';
import '../core/form_helpers.dart';
import '../core/module_registry.dart';
import '../core/permissions.dart';
import '../core/text_utils.dart';
import '../services/crud_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/responsive_officer_shell.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';
import '../core/roles.dart';

/// Officer Announcements as a card grid. [AnnouncementsBody] is public because
/// the merged "Announcements & Events" screen embeds it as a tab; this
/// shell-wrapped screen serves direct routes.
class AdminAnnouncementsScreen extends StatelessWidget {
  const AdminAnnouncementsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const ResponsiveOfficerShell(
      title: 'Announcements',
      activeItem: 'Announcements',
      activeTab: 'News',
      desktopChild: AnnouncementsBody(officer: true),
    );
  }
}

/// Resident/tenant Announcements: the same card grid, read-only, published
/// posts only.
class MemberAnnouncementsScreen extends StatelessWidget {
  const MemberAnnouncementsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const MemberShell(
      title: 'Announcements',
      activeItem: 'Announcements',
      child: AnnouncementsBody(officer: false),
    );
  }
}

/// Badge colours and icon for each announcement category.
const _categoryStyles = <String, ({Color bg, Color fg, IconData icon})>{
  'general': (bg: Color(0xFFF3F6F4), fg: Color(0xFF63746A), icon: Icons.campaign_outlined),
  'emergency': (bg: Color(0xFFFBE4E4), fg: Color(0xFFA82F2F), icon: Icons.warning_amber_outlined),
  'maintenance': (bg: Color(0xFFE2F0F7), fg: Color(0xFF0C5C84), icon: Icons.build_outlined),
  'event': (bg: Color(0xFFE3F1E9), fg: Color(0xFF1A6B43), icon: Icons.event_outlined),
  'financial': (bg: Color(0xFFFBEFD6), fg: Color(0xFF8A6300), icon: Icons.payments_outlined),
  'security': (bg: Color(0xFFF3E8FB), fg: Color(0xFF6B21A8), icon: Icons.shield_outlined),
  'other': (bg: Color(0xFFF3F6F4), fg: Color(0xFF63746A), icon: Icons.info_outline),
};

const _months = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _friendlyDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  return '${_months[dt.month]} ${dt.day}, ${dt.year}';
}

/// The announcements list (cards or calendar) with filter and officer actions.
class AnnouncementsBody extends StatefulWidget {
  final bool officer;
  const AnnouncementsBody({super.key, required this.officer});

  @override
  State<AnnouncementsBody> createState() => _AnnouncementsBodyState();
}

class _AnnouncementsBodyState extends State<AnnouncementsBody> with SafeSetState<AnnouncementsBody> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _categoryFilter = 'all';

  /// Cards (default) or the shared community calendar.
  bool _calendarView = false;
  // Each action needs its own permission; a read-only officer can only view.
  bool _canCreate = false;
  bool _canEdit = false;
  bool _canDelete = false;

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
      var query = SupabaseService.instance.client
          .from('announcements')
          .select('*, author:author_id(first_name, last_name)');
      if (!widget.officer) {
        // Residents see only published, unexpired posts; officers see all.
        query = query
            .eq('status', 'published')
            .or('expire_at.is.null,expire_at.gt.${DateTime.now().toUtc().toIso8601String()}');
      }
      final data = await query.order('created_at', ascending: false).limit(100);
      final perms = widget.officer
          ? await SupabaseService.instance.getMyPermissions()
          : <String, Set<String>>{};
      // Must run before the cards build: canManageSharedPost reads the cached id.
      if (widget.officer) await SupabaseService.instance.getMyUserId();
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
        _canCreate = canPerform(perms, 'announcements', 'create');
        _canEdit = canPerform(perms, 'announcements', 'update');
        _canDelete = canPerform(perms, 'announcements', 'delete');
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

  Future<void> _openForm({Map<String, dynamic>? initial}) async {
    final saved = await showModuleFormDialog(context, announcements, initial: initial);
    if (saved == true) _load();
  }

  /// Publishes or archives a post from the card menu. The form has no status field.
  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    try {
      await SupabaseService.instance.client
          .from('announcements')
          .update({'status': status}).eq('id', row['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update status. ${friendlyError(e)}')));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: const Text('This will permanently delete this announcement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CrudService.instance.delete(announcements, row['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed. ${friendlyError(e)}')));
      }
    }
  }

  List<Map<String, dynamic>> get _visibleRows => _categoryFilter == 'all'
      ? _rows
      : _rows.where((r) => (r['category'] ?? 'general') == _categoryFilter).toList();

  @override
  Widget build(BuildContext context) {
    final border = widget.officer ? AppColors.border : ResidentColors.border;
    final textMuted = widget.officer ? AppColors.textMuted : ResidentColors.textSecondary;

    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 700;
      return Padding(
        padding: EdgeInsets.all(narrow ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!narrow)
                  Text('All announcements',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: textMuted)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _calendarView = !_calendarView),
                  icon: Icon(_calendarView ? Icons.view_agenda_outlined : Icons.calendar_month_outlined, size: 15),
                  label: Text(narrow ? '' : (_calendarView ? 'Card View' : 'Calendar View')),
                ),
                const SizedBox(width: 10),
                PopupMenuButton<String>(
                  onSelected: (v) => setState(() => _categoryFilter = v),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'all', child: Text('All categories')),
                    for (final c in _categoryStyles.keys)
                      PopupMenuItem(value: c, child: Text(titleCase(c))),
                  ],
                  child: narrow
                      ? const Icon(Icons.filter_list, size: 20, color: AppColors.textSecondary)
                      : OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.filter_list, size: 15),
                          label: Text(_categoryFilter == 'all' ? 'Filter' : titleCase(_categoryFilter)),
                        ),
                ),
                if (_canCreate) ...[
                  const SizedBox(width: 10),
                  narrow
                      ? FilledButton(
                          onPressed: () => _openForm(),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                          child: const Text('+ New', style: TextStyle(fontSize: 12.5)),
                        )
                      : FilledButton.icon(
                          onPressed: () => _openForm(),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('New Announcement'),
                        ),
                ],
              ],
            ),
            SizedBox(height: narrow ? 12 : 18),
            Expanded(child: _buildBody(border, textMuted)),
          ],
        ),
      );
    });
  }

  Widget _buildBody(Color border, Color textMuted) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 28),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(fontSize: 12, color: textMuted)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final rows = _visibleRows;
    if (_calendarView) {
      return SingleChildScrollView(
        child: CommunityCalendar(officer: widget.officer, announcements: rows),
      );
    }
    if (rows.isEmpty) {
      return Center(
        child: Text('No announcements yet.', style: TextStyle(fontSize: 13, color: textMuted)),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 560,
        mainAxisExtent: 212,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: rows.length,
      itemBuilder: (context, i) => _AnnouncementCard(
        row: rows[i],
        // Edit/delete controls need the permission. A post shared to every phase
        // is manageable only by the admin or the president who wrote it
        // (the database enforces this too).
        officer: (_canEdit || _canDelete) &&
            canManageSharedPost(rows[i],
                authorKey: 'author_id',
                role: SupabaseService.cachedRole,
                myUserId: SupabaseService.cachedUserRowId),
        border: border,
        textMuted: textMuted,
        onEdit: () => _openForm(initial: rows[i]),
        onDelete: () => _delete(rows[i]),
        onSetStatus: (s) => _setStatus(rows[i], s),
      ),
    );
  }
}

/// One announcement in the grid.
class _AnnouncementCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool officer;
  final Color border;
  final Color textMuted;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final void Function(String status) onSetStatus;

  const _AnnouncementCard({
    required this.row,
    required this.officer,
    required this.border,
    required this.textMuted,
    required this.onEdit,
    required this.onDelete,
    required this.onSetStatus,
  });

  /// True once expire_at has passed; worked out on the fly, not stored.
  bool get isExpired {
    final exp = DateTime.tryParse((row['expire_at'] ?? '').toString());
    return exp != null && exp.isBefore(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final category = (row['category'] as String?) ?? 'general';
    final style = _categoryStyles[category] ?? _categoryStyles['general']!;
    // Prefer the stored author_name; the users lookup fails across phases.
    final author = row['author'] as Map<String, dynamic>?;
    final stored = (row['author_name'] ?? '').toString().trim();
    final looked = author == null
        ? ''
        : [author['first_name'], author['last_name']]
            .where((s) => s != null && s.toString().isNotEmpty)
            .join(' ');
    final authorName = stored.isNotEmpty
        ? stored
        : looked.isNotEmpty
            ? looked
            : 'the HOA office';
    final date = _friendlyDate((row['publish_at'] ?? row['created_at'])?.toString());
    final expiry = _friendlyDate(row['expire_at']?.toString());
    final content = (row['content'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The photo (tap to enlarge) if there is one, else the category icon.
              if ((row['image_url'] ?? '').toString().isNotEmpty)
                TapToPreview(
                  imageUrl: row['image_url'].toString(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(row['image_url'].toString(),
                        width: 44, height: 44, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            width: 44, height: 44, color: style.bg,
                            child: Icon(style.icon, color: style.fg, size: 20))),
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Icon(style.icon, color: style.fg, size: 20),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (row['title'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text('Posted by $authorName${date.isEmpty ? '' : ' - $date'}',
                        style: TextStyle(fontSize: 11, color: textMuted)),
                  ],
                ),
              ),
              if (officer)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.more_vert, size: 18, color: textMuted),
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        onEdit();
                      case 'delete':
                        onDelete();
                      case 'publish':
                        onSetStatus('published');
                      case 'archive':
                        onSetStatus('archived');
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    // Shows Archive for published posts, otherwise Publish.
                    if ((row['status'] ?? '') == 'published')
                      const PopupMenuItem(value: 'archive', child: Text('Archive'))
                    else
                      const PopupMenuItem(value: 'publish', child: Text('Publish')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Text(
              content.isEmpty ? 'No content.' : content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: textMuted, height: 1.5),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  category[0].toUpperCase() + category.substring(1),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: style.fg),
                ),
              ),
              // Marks posts residents cannot see (draft or archived).
              if ((row['status'] ?? 'published') != 'published') ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF3F6F4), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    (row['status'] ?? '').toString() == 'draft' ? 'Draft' : 'Archived',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF63746A)),
                  ),
                ),
              ],
              if (isExpired) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFBE4E4), borderRadius: BorderRadius.circular(12)),
                  child: const Text('Expired',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFFA82F2F))),
                ),
              ] else if (expiry.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Expires $expiry',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: textMuted)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
