import 'package:flutter/material.dart';
import '../widgets/community_calendar.dart';
import '../core/form_helpers.dart';
import '../core/permissions.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_shell.dart';
import '../widgets/phase_scope.dart';
import '../widgets/responsive_bits.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Officer waste collection schedule: weekly days, plus a "Next Collection"
/// card worked out from today. Edit Schedule shows only with update permission.
class AdminWasteScheduleScreen extends StatefulWidget {
  const AdminWasteScheduleScreen({super.key});

  @override
  State<AdminWasteScheduleScreen> createState() => _AdminWasteScheduleScreenState();
}

// Indexed by `waste_schedules.day_of_week`, where 0 = Sunday.
const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// Monday-first display order of the 0 = Sunday day indexes.
const _weekOrder = [1, 2, 3, 4, 5, 6, 0];
const _wasteTypeLabels = {
  'biodegradable': 'Biodegradable',
  'recyclable': 'Recyclable',
  'residual': 'Residual',
  'rest_day': 'Rest Day',
};
const _wasteTypeColors = {
  'biodegradable': (Color(0xFFE3F1E9), Color(0xFF1A6B43)),
  'recyclable': (Color(0xFFE2F0F7), Color(0xFF0C5C84)),
  'residual': (Color(0xFFFBEFD6), Color(0xFF8A6300)),
  'rest_day': (Color(0xFFECEFED), Color(0xFF63746A)),
};

class _AdminWasteScheduleScreenState extends State<AdminWasteScheduleScreen> with SafeSetState<AdminWasteScheduleScreen> {
  List<Map<String, dynamic>> _days = [];
  bool _loading = true;
  String? _error;
  bool _canManage = false;
  /// Phase new days are saved under (officer's phase, or the one a super
  /// admin is viewing); null = whole subdivision. The database function
  /// `stamp_waste_schedule_phase()` actually sets it.
  String? _editPhase;

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
      final results = await Future.wait<dynamic>([
        SupabaseService.instance.client.from('waste_schedules').select('*').order('day_of_week'),
        SupabaseService.instance.getMyPermissions(),
        SupabaseService.instance.getRoleAndStatus(),
        _myPhaseRow(),
      ]);
      if (!mounted) return;
      final perms = results[1] as Map<String, Set<String>>;
      final role = (results[2] as ({String role, String status})?)?.role;
      final me = results[3] as Map<String, dynamic>?;
      final key = role == 'super_admin' ? 'viewing_phase' : 'phase';
      final code = me == null ? null : me[key]?.toString().trim();
      setState(() {
        _days = List<Map<String, dynamic>>.from(results[0] as List);
        _canManage = canPerform(perms, 'waste_schedules', 'update');
        _editPhase = (code == null || code.isEmpty) ? null : code;
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

  Future<Map<String, dynamic>?> _myPhaseRow() async {
    final uid = SupabaseService.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    return SupabaseService.instance.client
        .from('users')
        .select('phase, viewing_phase')
        .eq('supabase_uid', uid)
        .maybeSingle();
  }

  /// Rows for one weekday, sorted by time. A day can have several types;
  /// a rest day is one row.
  List<Map<String, dynamic>> _rowsFor(int dow) {
    final rows = _days.where((d) => d['day_of_week'] == dow).toList();
    rows.sort((a, b) => (a['collection_time'] ?? '').toString().compareTo((b['collection_time'] ?? '').toString()));
    return rows;
  }

  /// The next day (within 7) that has a collection, and how far ahead it is.
  ({List<Map<String, dynamic>> rows, int daysAhead})? get _nextCollection {
    if (_days.isEmpty) return null;
    // DateTime.weekday is 1=Mon..7=Sun; day_of_week is 0=Sun..6=Sat.
    final todayIdx = DateTime.now().weekday % 7;
    for (var offset = 0; offset < 7; offset++) {
      final rows = _rowsFor((todayIdx + offset) % 7).where((d) => d['waste_type'] != 'rest_day').toList();
      if (rows.isNotEmpty) return (rows: rows, daysAhead: offset);
    }
    return null;
  }

  /// "Today, 7:00 AM", "Tomorrow", or a weekday name.
  String _friendlyWhen(int daysAhead, String? time) {
    final label = daysAhead == 0 ? 'Today' : (daysAhead == 1 ? 'Tomorrow' : _dayNames[(DateTime.now().weekday + daysAhead) % 7]);
    final t = time == null ? '' : ', ${_formatTime(time)}';
    return '$label$t';
  }

  /// "07:00:00" -> "7:00 AM".
  String _formatTime(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return time;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $period';
  }

  /// The collection types, in the order offered.
  static const _collectTypes = ['biodegradable', 'recyclable', 'residual'];

  /// "07:00:00" -> TimeOfDay(7, 0); null when it cannot be read.
  static TimeOfDay? _toTimeOfDay(String? t) {
    if (t == null) return null;
    final p = t.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    if (h == null || m == null || h > 23 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  /// TimeOfDay -> "HH:MM:00" for saving.
  static String _fromTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  /// Rows stored under the phase being edited. Whole-subdivision rows
  /// (phase null) are visible but not editable by a phase officer.
  List<Map<String, dynamic>> get _ownRows => _days
      .where((d) => (d['phase'] ?? '').toString() == (_editPhase ?? ''))
      .toList();

  /// Dialog to set each weekday's collection types and times.
  Future<void> _editSchedule() async {
    // Per weekday: picked types and their times. None picked = rest day.
    final drafts = <int, Map<String, String>>{
      for (final dow in _weekOrder) dow: <String, String>{},
    };
    for (final r in _ownRows) {
      final dow = (r['day_of_week'] as num).toInt();
      final type = (r['waste_type'] ?? '').toString();
      if (!_collectTypes.contains(type)) continue;
      drafts[dow]![type] = (r['collection_time'] as String?) ?? '07:00:00';
    }
    bool saving = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickTime(int dow, String type) async {
            final current =
                _toTimeOfDay(drafts[dow]![type]) ?? const TimeOfDay(hour: 7, minute: 0);
            final picked = await showTimePicker(
              context: context,
              initialTime: current,
              initialEntryMode: TimePickerEntryMode.dial,
              helpText: '${_dayNames[dow]} · ${_wasteTypeLabels[type]}',
              // Always 12-hour with AM/PM.
              builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
                child: child!,
              ),
            );
            if (picked == null) return;
            setDialogState(() => drafts[dow]![type] = _fromTimeOfDay(picked));
          }

          Future<void> submit() async {
            setDialogState(() {
              saving = true;
              error = null;
            });
            try {
              final client = SupabaseService.instance.client;
              final me = SupabaseService.cachedUserRowId;
              final deletes = <int>[];
              final updates = <({int id, String? time})>[];
              final inserts = <Map<String, dynamic>>[];
              for (final dow in _weekOrder) {
                final picked = drafts[dow]!;
                // Nothing picked = one rest-day row, no time.
                final wanted = picked.isEmpty
                    ? <String, String?>{'rest_day': null}
                    : <String, String?>{...picked};
                final existing = _ownRows.where((r) => r['day_of_week'] == dow);
                final have = <String>{};
                for (final r in existing) {
                  final type = (r['waste_type'] ?? '').toString();
                  final id = (r['id'] as num).toInt();
                  if (!wanted.containsKey(type) || have.contains(type)) {
                    deletes.add(id);
                  } else {
                    have.add(type);
                    if (r['collection_time'] != wanted[type]) {
                      updates.add((id: id, time: wanted[type]));
                    }
                  }
                }
                for (final e in wanted.entries) {
                  if (have.contains(e.key)) continue;
                  inserts.add({
                    'day_of_week': dow,
                    'waste_type': e.key,
                    'collection_time': e.value,
                    'updated_by': me,
                  });
                }
              }
              // Delete first: a day cannot hold a rest-day row and a
              // collection row together (trg_10_waste_rest_day_alone).
              if (deletes.isNotEmpty) {
                await client.from('waste_schedules').delete().inFilter('id', deletes);
              }
              for (final u in updates) {
                await client
                    .from('waste_schedules')
                    .update({'collection_time': u.time, 'updated_by': me}).eq('id', u.id);
              }
              if (inserts.isNotEmpty) {
                // `phase` is left out on purpose; the database sets it.
                await client.from('waste_schedules').insert(inserts);
              }
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (mounted) _load();
            } catch (e) {
              if (mounted) _load();
              setDialogState(() {
                saving = false;
                error = 'Could not save. ${friendlyError(e)}';
              });
            }
          }

          final phase = _editPhase ?? '';

          Widget dayBlock(int dow) {
            final picked = drafts[dow]!;
            final isRest = picked.isEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(_dayNames[dow],
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isRest ? AppColors.textMuted : AppColors.textPrimary)),
                    const SizedBox(width: 8),
                    if (isRest)
                      const Text('Rest day · no collection',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final type in _collectTypes)
                        FilterChip(
                          label: Text(_wasteTypeLabels[type]!),
                          selected: picked.containsKey(type),
                          selectedColor: _wasteTypeColors[type]!.$1,
                          checkmarkColor: _wasteTypeColors[type]!.$2,
                          onSelected: saving
                              ? null
                              : (on) => setDialogState(() {
                                    if (on) {
                                      // Reuse the day's time, else 7:00 AM.
                                      picked[type] = picked.values.isNotEmpty
                                          ? picked.values.first
                                          : '07:00:00';
                                    } else {
                                      picked.remove(type);
                                    }
                                  }),
                        ),
                    ],
                  ),
                  for (final type in _collectTypes)
                    if (picked.containsKey(type))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: _wasteTypeColors[type]!.$2, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_wasteTypeLabels[type]!,
                                style: const TextStyle(
                                    fontSize: 12.5, color: AppColors.textSecondary)),
                          ),
                          OutlinedButton.icon(
                            onPressed: saving ? null : () => pickTime(dow, type),
                            icon: const Icon(Icons.schedule, size: 16),
                            label: Text(_formatTime(picked[type]!)),
                          ),
                        ]),
                      ),
                ],
              ),
            );
          }

          return AlertDialog(
            title: const Text('Edit Weekly Schedule'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        phase.isEmpty
                            ? 'Applies to the whole subdivision'
                            : 'Phase ${phaseNumberOf(phase)} · applies to every household in this phase',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Tick what is collected each day (one, two or all three) and tap '
                        'the time to set it. A day with nothing ticked is a rest day.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                      ),
                    ),
                    for (final dow in _weekOrder) dayBlock(dow),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: saving ? null : submit,
                  child: Text(saving ? 'Saving...' : 'Save Schedule')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Waste Collection Schedule',
      activeItem: 'Waste Schedule',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _nextCollectionCard(),
                      const SizedBox(height: 24),
                      TitleActionRow(
                        title: const Text('Weekly Schedule',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        actions: [
                          if (_canManage)
                            FilledButton(onPressed: _editSchedule, child: const Text('Edit Schedule')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_days.isEmpty)
                        Text(
                          _canManage
                              ? 'No collection days set yet. Press Edit Schedule to set the week.'
                              : 'No collection days have been set yet.',
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        )
                      else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final perRow = (constraints.maxWidth / 160).floor().clamp(2, 7);
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              // Monday to Sunday.
                              for (final dow in _weekOrder)
                                if (_rowsFor(dow).isNotEmpty)
                                  SizedBox(
                                    width: (constraints.maxWidth - 12 * (perRow - 1)) / perRow,
                                    child: _dayCard(dow, _rowsFor(dow)),
                                  ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      CommunityCalendar(officer: true, wasteDays: _days, title: 'Collection Calendar'),
                    ],
                  ),
                ),
    );
  }

  /// Card showing when the next collection is and its types.
  Widget _nextCollectionCard() {
    final next = _nextCollection;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.badgeGreenBg, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Icon(Icons.delete_outline, color: AppColors.sidebarActiveText, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Next Collection', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                Text(
                  next == null
                      ? 'No collection scheduled'
                      : _friendlyWhen(next.daysAhead, next.rows.first['collection_time'] as String?),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          if (next != null)
            Flexible(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  for (final r in next.rows) StatusBadge(_wasteTypeLabels[r['waste_type']] ?? r['waste_type']),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Card for one weekday listing its collection types and times.
  Widget _dayCard(int dow, List<Map<String, dynamic>> rows) {
    final phases = {
      for (final d in rows)
        if ((d['phase'] ?? '').toString().trim().isNotEmpty) d['phase'].toString()
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_dayNames[dow],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const Divider(height: 20),
          for (final d in rows) ...[
            Builder(builder: (context) {
              final type = (d['waste_type'] ?? 'rest_day').toString();
              final colors = _wasteTypeColors[type] ?? _wasteTypeColors['rest_day']!;
              final time = d['collection_time'] as String?;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: colors.$1, borderRadius: BorderRadius.circular(20)),
                      child: Text(_wasteTypeLabels[type] ?? type,
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: colors.$2)),
                    ),
                    if (time != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, left: 2),
                        child: Text(_formatTime(time),
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      ),
                  ],
                ),
              );
            }),
          ],
          // No phase label means the whole subdivision.
          if (phases.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Expanded(
                  child: Text('Phase ${phases.map(phaseNumberOf).toSet().join(', ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
