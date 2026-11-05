import 'dart:async';

import 'package:flutter/material.dart';
import '../core/record_focus.dart';
import 'package:go_router/go_router.dart';
// RealtimeChannel, PostgresChangeEvent and PostgresChangeFilter live here;
// supabase_service does not re-export them.
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../core/safe_state.dart';

/// Bell icon + unread badge, shared by AdminShell and MemberShell top
/// bars. Tapping it opens a small panel listing recent notifications and
/// lets the resident/officer mark them read.
class NotificationsBell extends StatefulWidget {
  final Color iconColor;
  const NotificationsBell({super.key, required this.iconColor});

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell> with SafeSetState<NotificationsBell> {
  List<Map<String, dynamic>> _items = const [];
  bool _loaded = false;
  Timer? _poll;
  RealtimeChannel? _channel;

  /// Slow backup refresh in case the realtime connection drops silently.
  static const _pollInterval = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(_pollInterval, (_) => _load());
    _subscribe();
  }

  /// Reloads the list when a new notification arrives for this user.
  /// The user_id filter only saves bandwidth; row-level security is what
  /// keeps other users' rows private.
  Future<void> _subscribe() async {
    final myId = await SupabaseService.instance.getMyUserId();
    if (myId == null || !mounted) return;
    _channel = SupabaseService.instance.client
        .channel('notifications:$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: myId,
          ),
          // Refetch instead of appending: the list is capped at 20 and ordered.
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _poll?.cancel();
    // Must remove the channel or each rebuild leaks a subscription.
    final ch = _channel;
    if (ch != null) SupabaseService.instance.client.removeChannel(ch);
    super.dispose();
  }

  /// Fetches the 20 newest notifications for the signed-in user.
  Future<void> _load() async {
    final myId = await SupabaseService.instance.getMyUserId();
    if (myId == null) return;
    try {
      final rows = await SupabaseService.instance.client
          .from('notifications')
          .select('id, type, title, body, data, is_read, created_at')
          .eq('user_id', myId)
          .order('created_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  int get _unreadCount => _items.where((n) => n['is_read'] != true).length;

  /// Tells [RecordFocus] which record a notification is about, so the list
  /// it opens can highlight that row.
  static void _focusRecordFor(Map<String, dynamic> n) {
    final data = n['data'];
    if (data is! Map) return;
    Object? id;
    String? table;
    switch ((n['type'] ?? '').toString()) {
      case 'new_gate_pass':
        table = 'gate_passes';
        id = data['gate_pass_id'];
      case 'new_complaint':
        table = 'complaints';
        id = data['complaint_id'];
      case 'new_permit':
        table = 'permits';
        id = data['permit_id'];
      case 'new_move_request':
        table = 'move_requests';
        id = data['move_request_id'];
      case 'new_reservation':
        table = 'reservations';
        id = data['reservation_id'];
    }
    if (table != null && id != null) RecordFocus.request(table, id);
  }

  /// The screen to open when a notification is tapped, or null for
  /// informational types with nothing to open.
  static String? _routeFor(Map<String, dynamic> n) {
    switch ((n['type'] ?? '').toString()) {
      case 'new_registration':
        // Opens the Pending Approvals tab; there is no per-person link.
        return '/admin/approvals';
      case 'account_approved':
        return '/dashboard';
      // Complaints is a tab in Community Concern; '/admin/complaints' does not exist.
      case 'new_complaint':
        return '/admin/community-concern';
      // Opens "Assigned to Me", not the full queue.
      case 'complaint_assigned':
        return '/admin/assigned';
      case 'new_gate_pass':
        return '/admin/gate_passes';
      case 'new_permit':
        return '/admin/permits';
      // The route uses a hyphen, not an underscore.
      case 'new_move_request':
        return '/admin/move-requests';
      case 'new_reservation':
        return '/admin/reservations';
      // Payments is a tab inside Finance, not its own route.
      case 'new_payment_proof':
        return '/admin/finance?tab=payments';
      case 'reservation_approved':
        return '/me/reservations';
      // Sent to the applicant when a permit is reviewed.
      case 'permit_approved':
      case 'permit_rejected':
        return '/me/permits';
      default:
        return null;
    }
  }

  /// Icon for each notification type; defaults to a generic bell.
  static IconData _iconFor(String? type) {
    switch ((type ?? '').toLowerCase()) {
      case 'approval':
      case 'registration':
      case 'user':
        return Icons.how_to_reg_outlined;
      case 'billing':
      case 'bill':
      case 'payment':
        return Icons.receipt_long_outlined;
      case 'complaint':
      case 'case':
        return Icons.forum_outlined;
      case 'permit':
      case 'new_permit':
      case 'permit_approved':
      case 'permit_rejected':
        return Icons.description_outlined;
      case 'security':
      case 'incident':
        return Icons.shield_outlined;
      case 'announcement':
      case 'event':
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  /// "now / 5m / 3h / 2d", then an absolute date past a week. Converted to
  /// local time first -- created_at comes back as UTC.
  static String _relativeTime(dynamic iso) {
    final t = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  /// Marks one notification read on screen and in the database.
  Future<void> _markRead(Map<String, dynamic> n) async {
    if (n['is_read'] == true) return;
    setState(() => n['is_read'] = true);
    try {
      await SupabaseService.instance.client
          .from('notifications')
          .update({'is_read': true, 'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', n['id']);
    } catch (_) {
      // Best effort; the next refresh re-syncs.
    }
  }

  /// Marks every unread notification read.
  Future<void> _markAllRead() async {
    final unread = _items.where((n) => n['is_read'] != true).toList();
    if (unread.isEmpty) return;
    for (final n in unread) {
      n['is_read'] = true;
    }
    setState(() {});
    try {
      final myId = await SupabaseService.instance.getMyUserId();
      if (myId == null) return;
      await SupabaseService.instance.client
          .from('notifications')
          .update({'is_read': true, 'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', myId)
          .eq('is_read', false);
    } catch (_) {}
  }

  /// Opens the notifications popup.
  void _openPanel() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.05),
      // StatefulBuilder: the dialog is a separate subtree, so the bell's
      // setState does not rebuild it.
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setPanel) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 80, right: 32),
          child: Material(
            color: Colors.white,
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 340,
              constraints: const BoxConstraints(maxHeight: 420),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Notifications',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await _markAllRead();
                          setPanel(() {});
                        },
                        child: const Text('Mark all read',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ),
                  const Divider(height: 16, color: AppColors.border),
                  Flexible(
                    child: _items.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text('No notifications yet.',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary)),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final n = _items[i];
                              final unread = n['is_read'] != true;
                              final route = _routeFor(n);
                              return InkWell(
                                onTap: () {
                                  _markRead(n);
                                  setPanel(() {});
                                  if (route != null) {
                                    // Close the popup first or it stays stranded under the new page.
                                    Navigator.of(dialogContext).pop();
                                    _focusRecordFor(n);
                                    this.context.push(route);
                                  }
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: unread
                                        ? const Color(0xFFF1F7F3)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: AppColors.badgeGreenBg,
                                          borderRadius: BorderRadius.circular(9),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(_iconFor(n['type']?.toString()),
                                            size: 15,
                                            color: AppColors.sidebarActiveText),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                      (n['title'] ?? '').toString(),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                          fontSize: 12.5,
                                                          fontWeight: unread
                                                              ? FontWeight.w600
                                                              : FontWeight.w400,
                                                          color: AppColors
                                                              .textPrimary)),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(_relativeTime(n['created_at']),
                                                    style: const TextStyle(
                                                        fontSize: 10.5,
                                                        color:
                                                            AppColors.textMuted)),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text((n['body'] ?? '').toString(),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 11.5,
                                                    height: 1.35,
                                                    color: AppColors
                                                        .textSecondary)),
                                          ],
                                        ),
                                      ),
                                      if (unread) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          margin: const EdgeInsets.only(top: 6),
                                          width: 7,
                                          height: 7,
                                          // Not const: sidebarActiveText is not a compile-time colour.
                                          decoration: BoxDecoration(
                                            color: AppColors.sidebarActiveText,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                      if (route != null) ...[
                                        const SizedBox(width: 2),
                                        const Padding(
                                          padding: EdgeInsets.only(top: 6),
                                          child: Icon(Icons.chevron_right,
                                              size: 16, color: AppColors.textMuted),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _loaded ? _openPanel : null,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.notifications_outlined, size: 20, color: widget.iconColor),
            if (_unreadCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFA82F2F),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _unreadCount > 9 ? '9+' : '$_unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
