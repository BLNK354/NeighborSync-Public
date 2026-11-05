import 'package:flutter/material.dart';
import 'image_lightbox.dart';

import '../core/dialog_sizing.dart';
import '../core/text_utils.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';

/// The event's status worked out from its start and end times (upcoming,
/// ongoing, completed). A stored 'cancelled' always wins.
String derivedEventStatus(Map<String, dynamic> row) {
  if ((row['status'] ?? '') == 'cancelled') return 'cancelled';
  final start = DateTime.tryParse((row['start_datetime'] ?? '').toString());
  final end = DateTime.tryParse((row['end_datetime'] ?? '').toString());
  final now = DateTime.now();
  if (start == null) return 'upcoming';
  if (now.isBefore(start)) return 'upcoming';
  if (end != null && now.isAfter(end)) return 'completed';
  return 'ongoing';
}

const _months = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats a date and time like "Jan 5, 2026 · 3:30 PM" in local time.
String _when(DateTime? dt) {
  if (dt == null) return '';
  final l = dt.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final ampm = l.hour >= 12 ? 'PM' : 'AM';
  return '${_months[l.month]} ${l.day}, ${l.year} · $h:${l.minute.toString().padLeft(2, '0')} $ampm';
}

/// Details pop-up for an announcement: photo, badges, dates, then the full text.
Future<void> showAnnouncementDetails(BuildContext context, Map<String, dynamic> a) {
  final from = DateTime.tryParse((a['publish_at'] ?? a['created_at'] ?? '').toString());
  final until = DateTime.tryParse((a['expire_at'] ?? '').toString());
  final cat = (a['category'] ?? 'general').toString().trim();
  final priority = (a['priority'] ?? '').toString().trim();
  final audience = (a['target_audience'] ?? '').toString().trim();
  final author = (a['author_name'] ?? '').toString().trim();
  final content = (a['content'] ?? '').toString().trim();
  // Only show the phase row when the post carries a phase key.
  final hasPhaseKey = a.containsKey('phase');
  final phase = (a['phase'] ?? '').toString().trim();
  final now = DateTime.now();
  final state = until != null && until.isBefore(now)
      ? 'Expired'
      : from != null && from.isAfter(now)
          ? 'Scheduled'
          : 'Active';

  Widget row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4))),
          ],
        ),
      );

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text((a['title'] ?? 'Announcement').toString()),
      content: SizedBox(
        width: dialogContentWidth(ctx, 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PostPhotoBanner(a['image_url']?.toString()),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (cat.isNotEmpty) StatusBadge(titleCase(cat)),
                if (priority.isNotEmpty && priority != 'normal')
                  StatusBadge('${titleCase(priority)} priority'),
                StatusBadge(state),
              ]),
              const SizedBox(height: 14),
              if (from != null)
                row(Icons.schedule,
                    until == null
                        ? 'Shown from ${_when(from)}\nNo end date set'
                        : 'Shown from ${_when(from)}\nuntil ${_when(until)}'),
              if (audience.isNotEmpty)
                row(Icons.groups_outlined,
                    audience == 'all' ? 'For everyone' : 'For ${titleCase(audience)}'),
              if (hasPhaseKey)
                row(Icons.map_outlined,
                    phase.isEmpty ? 'All phases' : 'Phase ${phase.replaceAll(RegExp(r'[A-Za-z]'), '')}'),
              if (author.isNotEmpty) row(Icons.person_outline, 'Posted by $author'),
              if (content.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(content,
                    style: const TextStyle(fontSize: 13.5, height: 1.55, color: AppColors.textPrimary)),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ),
  );
}

/// Details pop-up for an event: when, where, and what it is about.
Future<void> showEventDetails(BuildContext context, Map<String, dynamic> e) {
  final start = DateTime.tryParse((e['start_datetime'] ?? '').toString());
  final end = DateTime.tryParse((e['end_datetime'] ?? '').toString());
  final venue = (e['venue'] ?? '').toString().trim();
  final desc = (e['description'] ?? '').toString().trim();
  final cat = (e['category'] ?? '').toString().trim();
  final max = e['max_attendees'];

  Widget row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4))),
          ],
        ),
      );

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text((e['title'] ?? 'Event').toString()),
      content: SizedBox(
        width: dialogContentWidth(ctx, 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PostPhotoBanner(e['image_url']?.toString()),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (cat.isNotEmpty) StatusBadge(titleCase(cat)),
                StatusBadge(derivedEventStatus(e)),
              ]),
              const SizedBox(height: 14),
              if (start != null)
                row(Icons.schedule,
                    end == null ? _when(start) : '${_when(start)}\nuntil ${_when(end)}'),
              row(Icons.place_outlined, venue.isEmpty ? 'Venue to be announced' : venue),
              if (max != null) row(Icons.groups_outlined, 'Up to $max attendees'),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(desc,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ),
  );
}
