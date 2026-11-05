import 'package:flutter/material.dart';
import '../core/dialog_sizing.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'event_details_dialog.dart';
import '../core/safe_state.dart';

/// One month calendar for events, announcements and waste collection.
/// Collection days are shaded in their waste colour, today is outlined, and
/// each day has a dot for events and for announcements. Tap a day for details.
///
/// Pass [events], [announcements] or [wasteDays] if the screen already has
/// them; anything left null is loaded here.
/// [month] follows the screen's own month switcher; if null, the calendar
/// shows its own arrows.
class CommunityCalendar extends StatefulWidget {
  final bool officer;
  final DateTime? month;
  final List<Map<String, dynamic>>? events;
  final List<Map<String, dynamic>>? announcements;
  final List<Map<String, dynamic>>? wasteDays;
  final String title;

  const CommunityCalendar({
    super.key,
    required this.officer,
    this.month,
    this.events,
    this.announcements,
    this.wasteDays,
    this.title = 'Community Calendar',
  });

  @override
  State<CommunityCalendar> createState() => _CommunityCalendarState();
}

/// Waste colours, identical to the Waste Schedule screens: (tint, ink).
const kWasteTypeColors = {
  'biodegradable': (Color(0xFFE3F1E9), Color(0xFF1A6B43)),
  'recyclable': (Color(0xFFE2F0F7), Color(0xFF0C5C84)),
  'residual': (Color(0xFFFBEFD6), Color(0xFF8A6300)),
  'rest_day': (Color(0xFFECEFED), Color(0xFF63746A)),
};
const _wasteLabels = {
  'biodegradable': 'Biodegradable',
  'recyclable': 'Recyclable',
  'residual': 'Residual',
  'rest_day': 'Rest Day',
};

/// Dot colours for events and announcements.
const _eventDot = Color(0xFFE8590C);
const _announcementDot = Color(0xFF7C3AED);

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class _CommunityCalendarState extends State<CommunityCalendar> with SafeSetState<CommunityCalendar> {
  late DateTime _ownMonth;
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _waste = [];
  bool _loading = true;

  DateTime get _month => widget.month ?? _ownMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _ownMonth = DateTime(now.year, now.month, 1);
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunityCalendar old) {
    super.didUpdateWidget(old);
    // Reload when the screen passes in a new list.
    if (old.events != widget.events ||
        old.announcements != widget.announcements ||
        old.wasteDays != widget.wasteDays) {
      _load();
    }
  }

  Future<void> _load() async {
    final db = SupabaseService.instance.client;
    try {
      final ev = widget.events ??
          List<Map<String, dynamic>>.from(await (widget.officer
              ? db.from('events').select('*')
              : db.from('events').select('*').eq('is_public', true).neq('status', 'cancelled'))
              .order('start_datetime')
              .limit(500) as List);
      final an = widget.announcements ??
          List<Map<String, dynamic>>.from(await db
              .from('announcements')
              .select('id, title, content, category, publish_at, created_at, phase, status, image_url')
              .eq('status', 'published')
              .order('publish_at', ascending: false)
              .limit(500) as List);
      // RLS limits this to the caller's own phase.
      final ws = widget.wasteDays ??
          List<Map<String, dynamic>>.from(await db.from('waste_schedules').select('*') as List);
      if (!mounted) return;
      setState(() {
        _events = ev;
        _announcements = an;
        _waste = ws;
        _loading = false;
      });
    } catch (_) {
      // A failed load just leaves the calendar empty.
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime? _local(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();

  List<Map<String, dynamic>> _eventsOn(DateTime day) =>
      _events.where((e) {
        final d = _local(e['start_datetime']);
        return d != null && _sameDay(d, day);
      }).toList();

  List<Map<String, dynamic>> _announcementsOn(DateTime day) =>
      _announcements.where((a) {
        final d = _local(a['publish_at'] ?? a['created_at']);
        return d != null && _sameDay(d, day);
      }).toList();

  /// Collections on this weekday. day_of_week is 0 = Sunday, which matches
  /// DateTime.weekday % 7.
  List<Map<String, dynamic>> _wasteOn(DateTime day) =>
      _waste.where((w) => w['day_of_week'] == day.weekday % 7 && (w['waste_type'] ?? '') != 'rest_day').toList();

  @override
  Widget build(BuildContext context) {
    final month = _month;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = DateTime(month.year, month.month, 1).weekday % 7;
    final now = DateTime.now();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${widget.title} · ${_monthNames[month.month - 1]} ${month.year}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              if (widget.month == null) ...[
                IconButton(
                  tooltip: 'Previous month',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _ownMonth = DateTime(month.year, month.month - 1, 1)),
                  icon: const Icon(Icons.chevron_left, size: 20),
                ),
                IconButton(
                  tooltip: 'Next month',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _ownMonth = DateTime(month.year, month.month + 1, 1)),
                  icon: const Icon(Icons.chevron_right, size: 20),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          const Text('Shaded days have a garbage collection. Dots mark events and announcements. Tap a day to see them.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 10),
          _legend(),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            LayoutBuilder(builder: (context, box) {
              final cellW = box.maxWidth / 7;
              // Square cells, capped at 64 so wide panels stay compact.
              final cellH = cellW > 64 ? 64.0 : cellW;
              return Column(
                children: [
                  Row(
                    children: [
                      for (final label in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                        SizedBox(
                          width: cellW,
                          child: Center(
                            child: Text(label,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    children: [
                      for (var i = 0; i < leadingBlanks; i++) SizedBox(width: cellW, height: cellH),
                      for (var d = 1; d <= daysInMonth; d++)
                        _cell(DateTime(month.year, month.month, d), cellW, cellH,
                            isToday: _sameDay(DateTime(month.year, month.month, d), now)),
                    ],
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _legend() {
    Widget swatch(Color c, String label, {bool dot = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dot ? 8 : 12,
              height: dot ? 8 : 12,
              decoration: BoxDecoration(
                color: c,
                shape: dot ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: dot ? null : BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final t in const ['biodegradable', 'recyclable', 'residual'])
          swatch(kWasteTypeColors[t]!.$1, _wasteLabels[t]!),
        swatch(_eventDot, 'Event', dot: true),
        swatch(_announcementDot, 'Announcement', dot: true),
      ],
    );
  }

  Widget _cell(DateTime day, double w, double h, {required bool isToday}) {
    final waste = _wasteOn(day);
    final evs = _eventsOn(day);
    final ans = _announcementsOn(day);
    final colors = waste.isEmpty ? null : kWasteTypeColors[(waste.first['waste_type'] ?? '').toString()];
    final hasAnything = waste.isNotEmpty || evs.isNotEmpty || ans.isNotEmpty;
    return SizedBox(
      width: w,
      height: h,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: colors?.$1 ?? Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showDay(day, waste, evs, ans),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: isToday ? Border.all(color: AppColors.textPrimary, width: 1.5) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${day.day}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: hasAnything || isToday ? FontWeight.w600 : FontWeight.w400,
                          color: colors?.$2 ?? AppColors.textMuted)),
                  if (evs.isNotEmpty || ans.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (evs.isNotEmpty) _dot(_eventDot),
                        if (evs.isNotEmpty && ans.isNotEmpty) const SizedBox(width: 3),
                        if (ans.isNotEmpty) _dot(_announcementDot),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  String _time(dynamic t) {
    final parts = (t ?? '').toString().split(':');
    if (parts.length < 2) return '';
    final h = int.tryParse(parts[0]) ?? 0;
    return '${h % 12 == 0 ? 12 : h % 12}:${parts[1]} ${h >= 12 ? 'PM' : 'AM'}';
  }

  void _showDay(DateTime day, List<Map<String, dynamic>> waste, List<Map<String, dynamic>> evs,
      List<Map<String, dynamic>> ans) {
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(t,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.textMuted)),
        );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_monthNames[day.month - 1]} ${day.day}, ${day.year}'),
        content: SizedBox(
          width: dialogContentWidth(context, 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (waste.isEmpty && evs.isEmpty && ans.isEmpty)
                  const Text('Nothing on this day.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                if (waste.isNotEmpty) ...[
                  heading('GARBAGE COLLECTION'),
                  for (final w in waste)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: (kWasteTypeColors[w['waste_type']] ?? kWasteTypeColors['rest_day']!).$1,
                        child: Icon(Icons.delete_outline,
                            size: 14,
                            color: (kWasteTypeColors[w['waste_type']] ?? kWasteTypeColors['rest_day']!).$2),
                      ),
                      title: Text(_wasteLabels[w['waste_type']] ?? (w['waste_type'] ?? '').toString()),
                      subtitle: Text([
                        if (_time(w['collection_time']).isNotEmpty) _time(w['collection_time']),
                        if ((w['phase'] ?? '').toString().isNotEmpty) 'Phase ${w['phase']}',
                      ].join(' · ')),
                    ),
                ],
                if (evs.isNotEmpty) ...[
                  heading('EVENTS'),
                  for (final e in evs)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                          radius: 14,
                          backgroundColor: Color(0xFFFDEBDD),
                          child: Icon(Icons.event, size: 14, color: _eventDot)),
                      title: Text((e['title'] ?? '').toString()),
                      subtitle: Text((e['venue'] ?? '').toString()),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => showEventDetails(context, e),
                    ),
                ],
                if (ans.isNotEmpty) ...[
                  heading('ANNOUNCEMENTS'),
                  for (final a in ans)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                          radius: 14,
                          backgroundColor: Color(0xFFEDE4FD),
                          child: Icon(Icons.campaign_outlined, size: 14, color: _announcementDot)),
                      title: Text((a['title'] ?? '').toString()),
                      subtitle: Text((a['category'] ?? 'general').toString()),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _showAnnouncement(a),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  void _showAnnouncement(Map<String, dynamic> a) =>
      showAnnouncementDetails(context, a);
}
