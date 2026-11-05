import 'package:flutter/material.dart';
import '../widgets/community_calendar.dart';
import '../core/form_helpers.dart';
import '../services/supabase_service.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

// Indexed by `waste_schedules.day_of_week`, where 0 = Sunday. Keep it Sunday-first or labels shift a day.
const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// Monday-first display order over the Sunday-first stored days.
const _weekOrder = [1, 2, 3, 4, 5, 6, 0];

/// Display name for each waste type.
const _wasteTypeLabels = {
  'biodegradable': 'Biodegradable',
  'recyclable': 'Recyclable',
  'residual': 'Residual',
  'rest_day': 'Rest Day',
};
/// Badge (background, text) colours for each waste type.
const _wasteTypeColors = {
  'biodegradable': (Color(0xFFE3F1E9), Color(0xFF1A6B43)),
  'recyclable': (Color(0xFFE2F0F7), Color(0xFF0C5C84)),
  'residual': (Color(0xFFFBEFD6), Color(0xFF8A6300)),
  'rest_day': (Color(0xFFECEFED), Color(0xFF63746A)),
};

/// Resident view of the waste collection schedule: next collection, weekly
/// cards and a month calendar. Read-only.
class MemberWasteScheduleScreen extends StatefulWidget {
  const MemberWasteScheduleScreen({super.key});

  @override
  State<MemberWasteScheduleScreen> createState() => _MemberWasteScheduleScreenState();
}

class _MemberWasteScheduleScreenState extends State<MemberWasteScheduleScreen> with SafeSetState<MemberWasteScheduleScreen> {
  List<Map<String, dynamic>> _allDays = [];
  bool _loading = true;
  String? _error;

  /// The resident's phase (lot -> block -> phase). Null if no address or no phase set.
  String? _myPhase;

  /// When true, shows other phases too.
  bool _showAllPhases = false;

  /// Schedule rows for this resident. A blank phase covers everyone; only
  /// rows for a different phase are hidden.
  List<Map<String, dynamic>> get _days {
    if (_showAllPhases || _myPhase == null) return _allDays;
    return _allDays.where((d) {
      final p = (d['phase'] ?? '').toString().trim();
      return p.isEmpty || p == _myPhase;
    }).toList();
  }

  int get _hiddenCount => _allDays.length - _days.length;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads the schedule and works out the resident's phase.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        SupabaseService.instance.client
            .from('waste_schedules')
            .select('*')
            .order('day_of_week'),
        SupabaseService.instance.getMyProfile(),
      ]);
      final profile = results[1] as Map<String, dynamic>?;

      // Phase comes from the lot's block; skipped if there is no address.
      String? phase;
      final lotId = profile?['lot_id'];
      if (lotId != null) {
        final lot = await SupabaseService.instance.client
            .from('lots')
            .select('blocks(phase)')
            .eq('id', lotId)
            .maybeSingle();
        final raw = ((lot?['blocks'] as Map<String, dynamic>?)?['phase'] ?? '')
            .toString()
            .trim();
        if (raw.isNotEmpty) phase = raw;
      }

      if (!mounted) return;
      setState(() {
        _allDays = List<Map<String, dynamic>>.from(results[0] as List);
        _myPhase = phase;
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

  /// Rows for one weekday, sorted by time. A day may carry several
  /// collection types (e.g. biodegradable and recyclable together).
  List<Map<String, dynamic>> _rowsFor(int dow) {
    final rows = _days.where((d) => d['day_of_week'] == dow).toList();
    rows.sort((a, b) => (a['collection_time'] ?? '').toString().compareTo((b['collection_time'] ?? '').toString()));
    return rows;
  }

  /// The next non-rest-day collection and how many days away it is, or null.
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

  /// "Today", "Tomorrow" or a weekday, plus the time if known.
  String _friendlyWhen(int daysAhead, String? time) {
    final label = daysAhead == 0
        ? 'Today'
        : (daysAhead == 1 ? 'Tomorrow' : _dayNames[(DateTime.now().weekday + daysAhead) % 7]);
    final t = time == null ? '' : ', ${_formatTime(time)}';
    return '$label$t';
  }

  /// Turns "14:30" into "2:30 PM".
  String _formatTime(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return time;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $period';
  }

  /// Shows which phase is displayed, with a button to show all phases.
  Widget _phaseNotice() {
    if (_myPhase == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: ResidentColors.iconGreenBg,
            borderRadius: BorderRadius.circular(20),
          ),
          // Not const: sidebarActiveText is a runtime getter.
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.place_outlined,
                size: 13, color: ResidentColors.sidebarActiveText),
            const SizedBox(width: 5),
            Text('Your area · Phase $_myPhase',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: ResidentColors.sidebarActiveText)),
          ]),
        ),
        if (_showAllPhases || _hiddenCount > 0) ...[
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => setState(() => _showAllPhases = !_showAllPhases),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(
                _showAllPhases
                    ? 'Show only mine'
                    : 'Show all phases ($_hiddenCount more)',
                style: const TextStyle(fontSize: 11.5)),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'Waste Schedule',
      activeItem: 'Waste Schedule',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _nextCollectionCard(),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Weekly Collection Schedule',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: ResidentColors.textPrimary)),
                          ),
                          _phaseNotice(),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final perRow = (constraints.maxWidth / 160).floor().clamp(2, 7);
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              // Monday first, not the stored order.
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
                      CommunityCalendar(officer: false, wasteDays: _days, title: 'Collection Calendar'),
                    ],
                  ),
                ),
    );
  }

  /// Card showing when the next collection is and its waste types.
  Widget _nextCollectionCard() {
    final next = _nextCollection;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ResidentColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: ResidentColors.iconGreenBg, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Icon(Icons.delete_outline, color: ResidentColors.sidebarActiveText, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Next Collection', style: TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
                Text(
                  next == null ? 'No collection scheduled' : _friendlyWhen(next.daysAhead, next.rows.first['collection_time'] as String?),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary),
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
        border: Border.all(color: ResidentColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_dayNames[dow],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
          const Divider(height: 20),
          for (final d in rows)
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
                            style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
                      ),
                  ],
                ),
              );
            }),
          // Phases covered; none listed means the whole subdivision.
          if (phases.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 12, color: ResidentColors.textSecondary),
                const SizedBox(width: 3),
                Expanded(
                  child: Text('Phase ${phases.join(', ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: ResidentColors.textSecondary)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
