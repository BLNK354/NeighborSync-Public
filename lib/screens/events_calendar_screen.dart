import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import '../core/module_registry.dart';
import '../core/permissions.dart';
import '../services/crud_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/resident_theme.dart';
import '../widgets/community_calendar.dart';
import '../widgets/member_shell.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/responsive_officer_shell.dart';
import '../widgets/status_badge.dart';
import '../widgets/event_details_dialog.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';
import '../core/roles.dart';

/// Officer Events screen: month calendar, Upcoming Events sidebar and a
/// List View toggle.
/// It has no bottom tab, so `activeTab` is just a placeholder.
class AdminEventsScreen extends StatelessWidget {
  const AdminEventsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const ResponsiveOfficerShell(
      title: 'Events',
      activeItem: 'Events',
      activeTab: 'Home',
      desktopChild: EventsBody(officer: true),
    );
  }
}

/// Resident Events screen: the same calendar, read-only, public events only.
class MemberEventsScreen extends StatelessWidget {
  const MemberEventsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const MemberShell(
      title: 'Events',
      activeItem: 'Events',
      child: EventsBody(officer: false),
    );
  }
}

/// Badge colours for each event category.
const _eventCategoryColors = <String, ({Color bg, Color fg})>{
  'meeting': (bg: Color(0xFFE2F0F7), fg: Color(0xFF0C5C84)),
  'social': (bg: Color(0xFFE3F1E9), fg: Color(0xFF1A6B43)),
  'sports': (bg: Color(0xFFFBEFD6), fg: Color(0xFF8A6300)),
  'maintenance': (bg: Color(0xFFF3E8FB), fg: Color(0xFF6B21A8)),
  'election': (bg: Color(0xFFFBE4E4), fg: Color(0xFFA82F2F)),
  'general': (bg: Color(0xFFF3F6F4), fg: Color(0xFF63746A)),
};

const _monthNames = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Calendar, list and upcoming sidebar. `officer` adds the manage actions.
class EventsBody extends StatefulWidget {
  final bool officer;
  const EventsBody({super.key, required this.officer});

  @override
  State<EventsBody> createState() => _EventsBodyState();
}

class _EventsBodyState extends State<EventsBody> with SafeSetState<EventsBody> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  bool _listView = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  // Needs the events permission, not just an officer role.
  bool _canCreate = false;
  bool _canManage = false;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads events (and the officer's permissions).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = SupabaseService.instance.client.from('events').select('*');
      if (!widget.officer) {
        // Residents see public, non-cancelled events that haven't ended.
        // Filter on end time, not stored status, which goes stale.
        query = query
            .eq('is_public', true)
            .neq('status', 'cancelled')
            .gt('end_datetime', DateTime.now().toUtc().toIso8601String());
      }
      final data = await query.order('start_datetime', ascending: true).limit(300);
      final perms = widget.officer
          ? await SupabaseService.instance.getMyPermissions()
          : <String, Set<String>>{};
      if (widget.officer) await SupabaseService.instance.getMyUserId();
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
        _canCreate = canPerform(perms, 'events', 'create');
        _canManage = canPerform(perms, 'events', 'update') || canPerform(perms, 'events', 'delete');
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

  /// Opens the create/edit form and reloads if saved.
  Future<void> _openForm({Map<String, dynamic>? initial}) async {
    final saved = await showModuleFormDialog(context, events, initial: initial);
    if (saved == true) _load();
  }

  /// Deletes an event after confirmation.
  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete event?'),
        content: const Text('This will permanently delete this event.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CrudService.instance.delete(events, row['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed. ${friendlyError(e)}')));
      }
    }
  }

  /// Cancels an event (with confirmation) or restores a cancelled one.
  /// Other statuses come from the event's dates.
  Future<void> _toggleCancelled(Map<String, dynamic> row) async {
    final isCancelled = (row['status'] ?? '') == 'cancelled';
    if (!isCancelled) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cancel this event?'),
          content: Text('"${row['title']}" will show as Cancelled and stop '
              'appearing on the resident side. You can restore it later.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Event')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel Event')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await SupabaseService.instance.client
          .from('events')
          .update({'status': isCancelled ? 'upcoming' : 'cancelled'}).eq('id', row['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update. ${friendlyError(e)}')));
      }
    }
  }

  List<PopupMenuEntry<String>> _eventMenuItems(Map<String, dynamic> e) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(
          value: 'cancel',
          child: Text((e['status'] ?? '') == 'cancelled' ? 'Restore Event' : 'Cancel Event'),
        ),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ];

  void _onEventMenu(String v, Map<String, dynamic> e) {
    switch (v) {
      case 'edit':
        _openForm(initial: e);
      case 'cancel':
        _toggleCancelled(e);
      case 'delete':
        _delete(e);
    }
  }

  DateTime? _startOf(Map<String, dynamic> row) => DateTime.tryParse((row['start_datetime'] ?? '').toString());

  /// Next six future events, soonest first.
  List<Map<String, dynamic>> get _upcoming {
    final now = DateTime.now();
    final list = _rows.where((r) {
      final dt = _startOf(r);
      // Cancelled events aren't "upcoming" no matter their date.
      return dt != null && dt.isAfter(now) && (r['status'] ?? '') != 'cancelled';
    }).toList()
      ..sort((a, b) => _startOf(a)!.compareTo(_startOf(b)!));
    return list.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.officer ? AppColors.border : ResidentColors.border;
    final textMuted = widget.officer ? AppColors.textMuted : ResidentColors.textSecondary;
    final textPrimary = widget.officer ? AppColors.textPrimary : ResidentColors.textPrimary;

    // Phones get the calendar and a Calendar/List switch, without the sidebar.
    final narrow = MediaQuery.of(context).size.width < kMobileBreakpoint;

    return Padding(
      padding: EdgeInsets.all(narrow ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1)),
                icon: const Icon(Icons.chevron_left, size: 20),
              ),
              Text('${_monthNames[_month.month]} ${_month.year}',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: textMuted)),
              IconButton(
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1)),
                icon: const Icon(Icons.chevron_right, size: 20),
              ),
              const Spacer(),
              // Calendar/List switch, icon-only on phones.
              narrow
                  ? IconButton(
                      tooltip: _listView ? 'Calendar view' : 'List view',
                      onPressed: () => setState(() => _listView = !_listView),
                      icon: Icon(_listView ? Icons.calendar_month_outlined : Icons.view_agenda_outlined, size: 20),
                    )
                  : OutlinedButton(
                      onPressed: () => setState(() => _listView = !_listView),
                      child: Text(_listView ? 'Calendar View' : 'List View'),
                    ),
              if (_canCreate) ...[
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(narrow ? 'New' : 'New Event'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: TextStyle(fontSize: 12, color: textMuted)))
                    : narrow
                        ? (_listView
                            ? _buildList(border, textMuted, textPrimary)
                            : _buildCalendar(border, textMuted, textPrimary))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final stacked = constraints.maxWidth < 940;
                              final main = _listView
                                  ? _buildList(border, textMuted, textPrimary)
                                  : _buildCalendar(border, textMuted, textPrimary);
                              final sidebar = _buildUpcomingSidebar(border, textMuted, textPrimary);
                              if (stacked) {
                                return SingleChildScrollView(
                                  child: Column(children: [
                                    SizedBox(height: 560, child: main),
                                    const SizedBox(height: 20),
                                    sidebar,
                                  ]),
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 7, child: main),
                                  const SizedBox(width: 20),
                                  SizedBox(width: 320, child: sidebar),
                                ],
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  /// The shared community calendar, following this screen's month switcher.
  Widget _buildCalendar(Color border, Color textMuted, Color textPrimary) {
    return SingleChildScrollView(
      child: CommunityCalendar(
        officer: widget.officer,
        month: _month,
        // Residents' rows are upcoming-only, so null makes the calendar
        // load its own events, past ones included.
        events: widget.officer ? _rows : null,
        title: 'Calendar',
      ),
    );
  }

  /// This month's events as a list, soonest first.
  Widget _buildList(Color border, Color textMuted, Color textPrimary) {
    final monthEvents = _rows.where((r) {
      final dt = _startOf(r);
      return dt != null && dt.year == _month.year && dt.month == _month.month;
    }).toList()
      ..sort((a, b) => _startOf(a)!.compareTo(_startOf(b)!));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: monthEvents.isEmpty
          ? Center(child: Text('No events this month.', style: TextStyle(fontSize: 13, color: textMuted)))
          : ListView.separated(
              itemCount: monthEvents.length,
              separatorBuilder: (_, __) => Divider(color: border, height: 24),
              itemBuilder: (context, i) {
                final e = monthEvents[i];
                final dt = _startOf(e)!;
                final style = _eventCategoryColors[e['category']] ?? _eventCategoryColors['general']!;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showEventDetails(context, e),
                  child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: Icon(Icons.event, color: style.fg, size: 18),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((e['title'] ?? '').toString(),
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                              '${_monthNames[dt.month].substring(0, 3)} ${dt.day}, ${dt.year} - ${(e['venue'] ?? 'TBD')}',
                              style: TextStyle(fontSize: 11.5, color: textMuted)),
                        ],
                      ),
                    ),
                    StatusBadge(derivedEventStatus(e)),
                    const SizedBox(width: 6),
                    // Shared events: only the admin or the organiser (HOA president) may manage.
                    if (_canManage &&
                        canManageSharedPost(e,
                            authorKey: 'organizer_id',
                            role: SupabaseService.cachedRole,
                            myUserId: SupabaseService.cachedUserRowId))
                      PopupMenuButton<String>(
                        onSelected: (v) => _onEventMenu(v, e),
                        itemBuilder: (context) => _eventMenuItems(e),
                      ),
                  ],
                ),
                );
              },
            ),
    );
  }

  /// Sidebar card listing the next upcoming events.
  Widget _buildUpcomingSidebar(Color border, Color textMuted, Color textPrimary) {
    final upcoming = _upcoming;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Upcoming Events',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary)),
          const SizedBox(height: 16),
          if (upcoming.isEmpty)
            Text('No upcoming events.', style: TextStyle(fontSize: 12.5, color: textMuted))
          else
            for (final e in upcoming) ...[
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showEventDetails(context, e),
                child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: (_eventCategoryColors[e['category']] ?? _eventCategoryColors['general']!).bg,
                      child: Icon(Icons.event,
                          size: 16, color: (_eventCategoryColors[e['category']] ?? _eventCategoryColors['general']!).fg),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((e['title'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textPrimary)),
                          const SizedBox(height: 2),
                          Text(_friendlyWhen(_startOf(e)),
                              style: TextStyle(fontSize: 11, color: textMuted)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: textMuted),
                  ],
                ),
              ),
              ),
            ],
        ],
      ),
    );
  }

  /// Formats a start time like "Jul 18, 2026 · 3:30 PM".
  String _friendlyWhen(DateTime? dt) {
    if (dt == null) return '';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    // The year stays in so events in different years aren't confused.
    return '${_monthNames[dt.month].substring(0, 3)} ${dt.day}, ${dt.year} · $h:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }
}
