import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../core/safe_state.dart';

/// One search result row.
class _Hit {
  final String group;
  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
  const _Hit(this.group, this.title, this.subtitle, this.route, this.icon);
}

/// App-wide search for the officer portal.
///
/// Runs one query per module and groups the results. A table the role cannot
/// read adds nothing, so results match the officer's permissions. Picking a
/// hit opens that module's screen.
class GlobalSearch {
  /// Opens the search dialog.
  static Future<void> open(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (context) => const _GlobalSearchDialog(),
    );
  }
}

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog();

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> with SafeSetState<_GlobalSearchDialog> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<_Hit> _hits = const [];
  bool _searching = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(raw));
  }

  /// Strips characters that would break the `or=` filter or act as wildcards.
  String _sanitize(String q) =>
      q.replaceAll(RegExp(r'[,()%_*\\]'), ' ').trim();

  /// Searches one table; returns nothing if it cannot be read.
  Future<List<Map<String, dynamic>>> _q(
      String table, String select, String orFilter) async {
    try {
      final r = await SupabaseService.instance.client
          .from(table)
          .select(select)
          .or(orFilter)
          .limit(5);
      return List<Map<String, dynamic>>.from(r as List);
    } catch (_) {
      // Unreadable table or failed query: skip it, keep the rest.
      return const [];
    }
  }

  Future<void> _run(String raw) async {
    final q = _sanitize(raw);
    if (q.length < 2) {
      if (mounted) setState(() => _hits = const []);
      return;
    }
    setState(() {
      _searching = true;
      _lastQuery = q;
    });

    final like = '%$q%';
    final results = await Future.wait([
      _q('users', 'id, first_name, last_name, email, roles(display_name)',
          'first_name.ilike.$like,last_name.ilike.$like,email.ilike.$like'),
      _q('complaints', 'complaint_number, subject, status',
          'complaint_number.ilike.$like,subject.ilike.$like'),
      _q('bills', 'bill_number, description, status',
          'bill_number.ilike.$like,description.ilike.$like'),
      _q('payments', 'or_number, reference_number, status',
          'or_number.ilike.$like,reference_number.ilike.$like'),
      _q('permits', 'permit_number, title, status',
          'permit_number.ilike.$like,title.ilike.$like'),
      _q('violations', 'violation_number, status',
          'violation_number.ilike.$like'),
      _q('announcements', 'title, category', 'title.ilike.$like'),
      _q('events', 'title, venue', 'title.ilike.$like,venue.ilike.$like'),
      _q('documents', 'name, category', 'name.ilike.$like'),
      _q('security_incidents', 'incident_number, title, status',
          'incident_number.ilike.$like,title.ilike.$like'),
      _q('lots', 'lot_number, street_address',
          'lot_number.ilike.$like,street_address.ilike.$like'),
      _q('vehicles', 'plate_number, make, model', 'plate_number.ilike.$like'),
      _q('visitor_logs', 'visitor_name, purpose', 'visitor_name.ilike.$like'),
      _q('gate_passes', 'pass_number, visitor_name',
          'pass_number.ilike.$like,visitor_name.ilike.$like'),
    ]);

    // A newer keystroke already superseded this run.
    if (!mounted || _lastQuery != q) return;

    String s(dynamic v) => (v ?? '').toString();
    final hits = <_Hit>[
      for (final u in results[0])
        _Hit(
            'People',
            [s(u['first_name']), s(u['last_name'])].where((x) => x.isNotEmpty).join(' '),
            '${s(u['email'])}${(u['roles'] as Map?)?['display_name'] != null ? ' · ${(u['roles'] as Map)['display_name']}' : ''}',
            '/admin/people/${u['id']}',
            Icons.person_outline),
      for (final c in results[1])
        _Hit('Complaints', s(c['complaint_number']),
            '${s(c['subject'])} · ${s(c['status'])}', '/admin/community-concern', Icons.forum_outlined),
      for (final b in results[2])
        _Hit('Bills', s(b['bill_number']), '${s(b['description'])} · ${s(b['status'])}',
            '/admin/finance', Icons.receipt_long_outlined),
      for (final p in results[3])
        _Hit('Payments', s(p['or_number']), 'Ref ${s(p['reference_number'])} · ${s(p['status'])}',
            '/admin/finance', Icons.payments_outlined),
      for (final p in results[4])
        _Hit('Permits', s(p['permit_number']), '${s(p['title'])} · ${s(p['status'])}',
            '/admin/permits', Icons.description_outlined),
      for (final v in results[5])
        _Hit('Violations', s(v['violation_number']), s(v['status']),
            '/admin/community-concern', Icons.gavel_outlined),
      for (final a in results[6])
        _Hit('Announcements', s(a['title']), s(a['category']), '/admin/announcements',
            Icons.campaign_outlined),
      for (final e in results[7])
        _Hit('Events', s(e['title']), s(e['venue']), '/admin/announcements', Icons.event_outlined),
      for (final d in results[8])
        _Hit('Documents', s(d['name']), s(d['category']), '/admin/documents',
            Icons.folder_outlined),
      for (final i in results[9])
        _Hit('Security', s(i['incident_number']), '${s(i['title'])} · ${s(i['status'])}',
            '/admin/security', Icons.shield_outlined),
      for (final l in results[10])
        _Hit('Lots', 'Lot ${s(l['lot_number'])}', s(l['street_address']), '/admin/community',
            Icons.map_outlined),
      for (final v in results[11])
        _Hit('Vehicles', s(v['plate_number']), '${s(v['make'])} ${s(v['model'])}'.trim(),
            '/admin/vehicles', Icons.directions_car_outlined),
      for (final v in results[12])
        _Hit('Visitors', s(v['visitor_name']), s(v['purpose']), '/admin/visitors',
            Icons.badge_outlined),
      for (final g in results[13])
        _Hit('Gate Passes', s(g['pass_number']), s(g['visitor_name']), '/admin/gate_passes',
            Icons.qr_code_outlined),
    ];

    setState(() {
      _hits = hits;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Group hits by module, preserving insertion order.
    final grouped = <String, List<_Hit>>{};
    for (final h in _hits) {
      (grouped[h.group] ??= []).add(h);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Material(
          color: Colors.white,
          elevation: 10,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 620,
            constraints: const BoxConstraints(maxHeight: 520),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    hintText: 'Search residents, bills, complaints, permits, documents…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => Navigator.pop(context),
                          ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(child: _results(grouped)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _results(Map<String, List<_Hit>> grouped) {
    if (_ctrl.text.trim().length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('Type at least 2 characters to search across every module.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      );
    }
    if (_hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
            _searching ? 'Searching…' : 'No matches for "${_ctrl.text.trim()}".',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
              child: Text(entry.key.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
            ),
            for (final h in entry.value)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.pop(context);
                  context.go(h.route);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  child: Row(
                    children: [
                      Icon(h.icon, size: 17, color: AppColors.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.title.isEmpty ? '(untitled)' : h.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary)),
                            if (h.subtitle.trim().isNotEmpty &&
                                h.subtitle.trim() != '·')
                              Text(h.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
