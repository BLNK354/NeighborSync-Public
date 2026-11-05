import 'package:flutter/material.dart';
import '../core/facility_rates.dart';
import '../core/record_focus.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/permissions.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_shell.dart';
import '../widgets/searchable_picker.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/status_badge.dart';
import '../widgets/table_sorting.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/safe_state.dart';

/// Officer screen for facility reservations: review, approve, reject, and
/// book on a resident's behalf. Approving is a plain update; the database
/// blocks overlapping approved bookings.
class AdminReservationsScreen extends StatefulWidget {
  const AdminReservationsScreen({super.key});

  @override
  State<AdminReservationsScreen> createState() => _AdminReservationsScreenState();
}

class _AdminReservationsScreenState extends State<AdminReservationsScreen>
    with SafeSetState<AdminReservationsScreen>, TableSortState, RecordFocusTarget {
  // Current page, starting at 1.
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  // Starts on All; the Awaiting Review card narrows it to pending.
  String _statusFilter = 'all';

  /// Filters to that status; tapping the same card again clears it.
  void _tapStatus(String status) => setState(() {
        _statusFilter = _statusFilter == status ? 'all' : status;
        _page = 1;
      });
  bool _canReview = false;

  /// Whether the officer may book on a resident's behalf (reservations:create).
  bool _canCreate = false;
  List<Map<String, dynamic>> _facilities = [];
  List<Map<String, dynamic>> _residents = [];

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
        SupabaseService.instance.client
            .from('reservations')
            .select('*, facility:facility_id(name, capacity, fee), '
                'resident:user_id(first_name, last_name)')
            .order('starts_at', ascending: true)
            .limit(300),
        SupabaseService.instance.getMyPermissions(),
        SupabaseService.instance.client
            .from('facilities')
            .select('*')
            .eq('is_active', true)
            .order('name'),
        SupabaseService.instance.client
            .from('users')
            .select('id, first_name, last_name, roles(name)')
            .eq('status', 'active')
            .order('first_name')
            .limit(1000),
      ]);
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(results[0] as List);
      // Other phases' residents come back without a name; fill them in
      // from the staff-only lookup.
      final missing = [
        for (final r in rows)
          if (r['resident'] == null && r['user_id'] != null) r['id']
      ];
      if (missing.isNotEmpty) {
        try {
          final names = await SupabaseService.instance.client
              .rpc('reservation_booker_names', params: {'p_ids': missing});
          final byId = {
            for (final n in (names as List)) n['reservation_id']: n['booker_name']
          };
          for (final r in rows) {
            final n = byId[r['id']];
            if (r['resident'] == null && n != null && n.toString().isNotEmpty) {
              r['resident'] = {'first_name': n, 'last_name': ''};
            }
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        final perms = results[1] as Map<String, Set<String>>;
        _canReview = canPerform(perms, 'reservations', 'update');
        _canCreate = canPerform(perms, 'reservations', 'create');
        _facilities = List<Map<String, dynamic>>.from(results[2] as List);
        // Only residents and tenants can hold a booking, not officers.
        _residents = List<Map<String, dynamic>>.from(results[3] as List)
            .where((u) => const {'member_resident', 'tenant'}
                .contains(((u['roles'] as Map<String, dynamic>?)?['name'] ?? '').toString()))
            .toList();
        _loading = false;
      });
      // When opened from a notification, show and highlight that booking.
      takeRecordFocus('reservations',
          clearFilters: () { _statusFilter = 'all'; },
          ordered: () => _visible,
          setPage: (p) => _page = p);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return '—';
    final n = [p['first_name'], p['last_name']]
        .where((s) => s != null && s.toString().isNotEmpty)
        .join(' ');
    return n.isEmpty ? '—' : n;
  }

  String _facilityName(Map<String, dynamic> r) =>
      ((r['facility'] as Map<String, dynamic>?)?['name'] ?? '—').toString();

  DateTime? _startsAt(Map<String, dynamic> r) =>
      DateTime.tryParse((r['starts_at'] ?? '').toString())?.toLocal();

  String _when(Map<String, dynamic> r) {
    final s = _startsAt(r);
    final e = DateTime.tryParse((r['ends_at'] ?? '').toString())?.toLocal();
    if (s == null || e == null) return '—';
    String hhmm(DateTime t) {
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
          '${t.hour >= 12 ? 'PM' : 'AM'}';
    }
    return '${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}'
        ' · ${hhmm(s)}–${hhmm(e)}';
  }

  int get _pendingCount => _rows.where((r) => r['status'] == 'pending').length;
  int get _upcomingCount => _rows.where((r) {
        final s = _startsAt(r);
        return r['status'] == 'approved' && s != null && s.isAfter(DateTime.now());
      }).length;
  int get _thisMonthCount {
    final now = DateTime.now();
    return _rows.where((r) {
      final s = _startsAt(r);
      return s != null && s.year == now.year && s.month == now.month;
    }).length;
  }

  List<Map<String, dynamic>> get _visible {
    final now = DateTime.now();
    final list = switch (_statusFilter) {
      'all' => List<Map<String, dynamic>>.from(_rows),
      // Same rules as the Upcoming and This Month card counts.
      'upcoming' => _rows.where((r) {
          final s = _startsAt(r);
          return r['status'] == 'approved' && s != null && s.isAfter(now);
        }).toList(),
      'this_month' => _rows.where((r) {
          final s = _startsAt(r);
          return s != null && s.year == now.year && s.month == now.month;
        }).toList(),
      _ => _rows.where((r) => r['status'] == _statusFilter).toList(),
    };
    return sortRows(list);
  }

  /// 0 Facility · 1 Resident · 2 When · 3 Occasion · 4 Guests · 5 Status
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> r, int col) {
    switch (col) {
      case 0:
        return text(_facilityName(r));
      case 1:
        return text(_name(r['resident'] as Map<String, dynamic>?));
      case 2:
        return date(r['starts_at']);
      case 3:
        return text(r['occasion']);
      case 4:
        return number(r['guest_count']);
      case 5:
        return rankedKey(r['status'], kStatusRank);
      default:
        return '';
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFA82F2F) : null,
    ));
  }

  /// Saves the review result (approved or rejected) with reviewer, time and note.
  Future<void> _setStatus(Map<String, dynamic> r, String status, {String? note}) async {
    setState(() => _busy = true);
    try {
      final me = await SupabaseService.instance.getMyUserId();
      await SupabaseService.instance.client.from('reservations').update({
        'status': status,
        'reviewed_by': me,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        if (note != null) 'review_note': note,
      }).eq('id', r['id']);
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(status == 'approved' ? 'Reservation approved.' : 'Reservation rejected.');
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // Approval can fail if the slot was approved for someone else meanwhile.
      final raw = e.toString();
      _snack(
        raw.contains('reservations_no_double_booking')
            ? 'That slot is already taken by another approved booking.'
            : 'Could not update. ${friendlyError(e)}',
        error: true,
      );
      _load();
    }
  }

  Future<void> _approve(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve this reservation?'),
        content: SizedBox(
          width: dialogContentWidth(context, 380),
          child: Text(
            '${_facilityName(r)}\n${_when(r)}\n'
            '${_name(r['resident'] as Map<String, dynamic>?)} · ${r['purpose'] ?? ''}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
        ],
      ),
    );
    if (ok == true) await _setStatus(r, 'approved');
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject this reservation?'),
        content: SizedBox(
          width: dialogContentWidth(context, 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The resident sees this reason.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                maxLength: kMaxTextLength,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Reason', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA82F2F)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (noteCtrl.text.trim().isEmpty) {
      _snack('Please give a reason so the resident knows why.', error: true);
      return;
    }
    await _setStatus(r, 'rejected', note: noteCtrl.text.trim());
  }

  /// Books a facility for a resident, saved as already approved. There is no
  /// availability check here: the database rejects a taken slot.
  Future<void> _bookForResident() async {
    if (_facilities.isEmpty) {
      _snack('No active facilities to book.', error: true);
      return;
    }
    if (_residents.isEmpty) {
      _snack('No active residents to book for.', error: true);
      return;
    }

    Map<String, dynamic> facility = _facilities.first;
    int? residentId;
    String occasion = 'Meeting';
    var day = DateTime.now().add(const Duration(days: 1));
    var start = const TimeOfDay(hour: 9, minute: 0);
    var end = const TimeOfDay(hour: 12, minute: 0);
    final purposeCtrl = TextEditingController();
    final guestsCtrl = TextEditingController();
    final kidsCtrl = TextEditingController();
    String? formError;

    Map<String, dynamic>? residentRow() {
      for (final u in _residents) {
        if ((u['id'] as num).toInt() == residentId) return u;
      }
      return null;
    }

    // Returns the first form problem, or null; checked inside the dialog
    // so the officer keeps what they typed.
    String? problem() {
      if (residentId == null) return 'Pick which resident the booking is for.';
      if (purposeCtrl.text.trim().isEmpty) return 'Say what the booking is for.';
      final s = DateTime(day.year, day.month, day.day, start.hour, start.minute);
      final e = DateTime(day.year, day.month, day.day, end.hour, end.minute);
      if (!e.isAfter(s)) return 'The end time has to be after the start time.';
      final g = guestCountError(guestsCtrl.text);
      if (g != null) return g;
      final n = int.tryParse(guestsCtrl.text.trim());
      final c = (facility['capacity'] as num?)?.toInt();
      if (n != null && c != null && n > c) {
        return '$n guests is over the ${facility['name']} capacity of $c.';
      }
      final k = int.tryParse(kidsCtrl.text.trim()) ?? 0;
      if (facilityIsPerHead(facility) && n != null && k > n) {
        return 'Kids are counted inside the number of people, so they cannot be more.';
      }
      return null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final cap = (facility['capacity'] as num?)?.toInt();
          final perHead = facilityIsPerHead(facility);
          return AlertDialog(
            title: const Text('Book for a resident'),
            content: SizedBox(
              width: dialogContentWidth(context, 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Searchable because the resident list can be long.
                    PickerField(
                      label: 'Resident',
                      value: residentId == null ? null : _name(residentRow()),
                      placeholder: 'Tap to search & select',
                      onTap: () async {
                        final picked = await showSearchablePicker<Map<String, dynamic>>(
                          context: context,
                          title: 'Select Resident',
                          items: _residents,
                          labelOf: _name,
                          selected: residentRow(),
                        );
                        if (picked != null) {
                          setLocal(() {
                            residentId = (picked['id'] as num).toInt();
                            formError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: (facility['id'] as num).toInt(),
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Facility', border: OutlineInputBorder()),
                      items: [
                        for (final f in _facilities)
                          DropdownMenuItem(
                            value: (f['id'] as num).toInt(),
                            child: Text((f['name'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => facility =
                          _facilities.firstWhere((f) => (f['id'] as num).toInt() == v)),
                    ),
                    const SizedBox(height: 8),
                    for (final line in facilityRateLines(facility))
                      Text(line,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: purposeCtrl,
                      decoration: const InputDecoration(
                          labelText: 'What is it for?', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: occasion,
                      decoration: const InputDecoration(
                          labelText: 'Occasion', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'Birthday', child: Text('Birthday')),
                        DropdownMenuItem(value: 'Wedding', child: Text('Wedding')),
                        DropdownMenuItem(value: 'Meeting', child: Text('Meeting')),
                        DropdownMenuItem(value: 'Reunion', child: Text('Reunion')),
                        DropdownMenuItem(value: 'Sports', child: Text('Sports / Practice')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (v) => setLocal(() => occasion = v ?? occasion),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text('${day.year}-${day.month.toString().padLeft(2, '0')}-'
                          '${day.day.toString().padLeft(2, '0')}'),
                      onPressed: () async {
                        // No minimum notice, so walk-ins can book today.
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: day,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setLocal(() => day = picked);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t =
                                await showTimePicker(context: context, initialTime: start);
                            if (t != null) setLocal(() => start = t);
                          },
                          child: Text('From ${start.format(context)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t =
                                await showTimePicker(context: context, initialTime: end);
                            if (t != null) setLocal(() => end = t);
                          },
                          child: Text('To ${end.format(context)}'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: guestsCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: guestCountInputFormatters,
                      onChanged: (_) => setLocal(() {}),
                      decoration: InputDecoration(
                        labelText: perHead ? 'Number of people (adults + kids)' : 'Expected guests',
                        helperText: cap == null ? null : 'Capacity: $cap',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (perHead) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: kidsCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: guestCountInputFormatters,
                        onChanged: (_) => setLocal(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Of those, kids (4 ft and below)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ReservationQuote(
                      facilityId: facility['id'],
                      userId: residentId,
                      starts: DateTime(day.year, day.month, day.day, start.hour, start.minute),
                      ends: DateTime(day.year, day.month, day.day, end.hour, end.minute),
                      people: int.tryParse(guestsCtrl.text.trim()) ?? 0,
                      kids: perHead ? (int.tryParse(kidsCtrl.text.trim()) ?? 0) : 0,
                      textColor: AppColors.textPrimary,
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 12),
                      Text(formError!,
                          style: const TextStyle(
                              color: AppColors.badgeRedText,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () {
                    final p = problem();
                    if (p != null) {
                      setLocal(() => formError = p);
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('Book')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;

    final startsAt = DateTime(day.year, day.month, day.day, start.hour, start.minute);
    final endsAt = DateTime(day.year, day.month, day.day, end.hour, end.minute);
    final guests = int.tryParse(guestsCtrl.text.trim());

    setState(() => _busy = true);
    try {
      final me = await SupabaseService.instance.getMyUserId();
      await SupabaseService.instance.client.from('reservations').insert({
        'facility_id': facility['id'],
        'user_id': residentId,
        'purpose': purposeCtrl.text.trim(),
        'occasion': occasion,
        'guest_count': guests,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        // The database sets the price (price_reservation).
        'child_count': facilityIsPerHead(facility)
            ? (int.tryParse(kidsCtrl.text.trim()) ?? 0)
            : 0,
        'status': 'approved',
        'reviewed_by': me,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'notes': 'Booked at the office.',
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Switch the filter so the new booking is visible.
        _statusFilter = 'approved';
      });
      _snack('Reservation booked and approved.');
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final raw = e.toString();
      _snack(
        raw.contains('reservations_no_double_booking')
            ? '${facility['name']} is already booked for part of that time.'
            : 'Could not book. ${friendlyError(e)}',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Reservations',
      activeItem: 'Reservations',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                              _statusFilter == 'all'
                                  ? 'All reservations'
                                  : _statusFilter == 'this_month'
                                      ? 'Reservations this month'
                                      : '${titleCase(_statusFilter)} reservations',
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textMuted)),
                          const Spacer(),
                          PopupMenuButton<String>(
                            onSelected: (v) => setState(() { _statusFilter = v; _page = 1; }),
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'pending', child: Text('Pending')),
                              PopupMenuItem(value: 'approved', child: Text('Approved')),
                              PopupMenuItem(value: 'rejected', child: Text('Rejected')),
                              PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
                              PopupMenuItem(value: 'all', child: Text('All')),
                            ],
                            child: OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.filter_list, size: 16),
                              label: Text(_statusFilter == 'this_month' ? 'This month' : titleCase(_statusFilter)),
                            ),
                          ),
                          if (_canCreate) ...[
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: _busy ? null : _bookForResident,
                              child: const Text('Book for a Resident'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),
                      responsiveStatCards((w) => [
                            DashboardStatCard(
                                icon: Icons.pending_actions_outlined,
                                iconBg: const Color(0xFFFBEFD6),
                                label: 'Awaiting Review',
                                value: '$_pendingCount',
                                width: w,
                                selected: _statusFilter == 'pending',
                                onTap: () => _tapStatus('pending')),
                            DashboardStatCard(
                                icon: Icons.event_available_outlined,
                                iconBg: const Color(0xFFE3F1E9),
                                label: 'Upcoming',
                                value: '$_upcomingCount',
                                width: w,
                                selected: _statusFilter == 'upcoming',
                                onTap: () => _tapStatus('upcoming')),
                            DashboardStatCard(
                                icon: Icons.calendar_month_outlined,
                                iconBg: const Color(0xFFE2F0F7),
                                label: 'This Month',
                                value: '$_thisMonthCount',
                                width: w,
                                selected: _statusFilter == 'this_month',
                                onTap: () => _tapStatus('this_month')),
                          ]),
                      const SizedBox(height: 20),
                      Expanded(
                        // Cards below 700px, since the table cannot wrap on a phone.
                        child: LayoutBuilder(
                          builder: (context, c) =>
                              c.maxWidth < 700 ? _cards() : _table(),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// Phone layout: one card per reservation with approve and reject buttons.
  Widget _cards() {
    final all = _visible;
    if (all.isEmpty) return _emptyState();
    // Paged, with the notification target first and the pager last.
    final rows = pageSlice(pinFocused(all), _page);
    final hasPager = pageCountFor(all.length) > 1;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: rows.length + (hasPager ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i >= rows.length) {
          return pagerFor(all.length, _page, (p) => setState(() => _page = p));
        }
        final r = rows[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isFocusedRow(r) ? kFocusRowColor : Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_facilityName(r),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                  StatusBadge((r['status'] ?? '').toString()),
                ],
              ),
              const SizedBox(height: 4),
              Text(_when(r),
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(
                  '${_name(r['resident'] as Map<String, dynamic>?)}'
                  '${(r['occasion'] ?? '').toString().isEmpty ? '' : ' · ${r['occasion']}'}'
                  '${r['guest_count'] == null ? '' : ' · ${r['guest_count']} guests'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
              if (_canReview && r['status'] == 'pending') ...[
                const Divider(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _reject(r),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFA82F2F)),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : () => _approve(r),
                        child: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _statusFilter == 'pending'
                  ? 'Nothing waiting for review.'
                  : 'No ${_statusFilter == 'all' ? '' : '${_statusFilter.replaceAll('_', ' ')} '}reservations.',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            // Hint so an empty Pending view does not look broken.
            if (_statusFilter == 'pending' && _rows.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('${_rows.length} reservation${_rows.length == 1 ? '' : 's'} '
                  'under other statuses — switch the filter to All.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ],
        ),
      );
  }

  /// Desktop layout: sortable table of reservations.
  Widget _table() {
    final rows = _visible;
    if (rows.isEmpty) return _emptyState();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: fullWidthTable(
            footer: pagerFor(rows.length, _page, (p) => setState(() => _page = p)),
            
        DataTable(
          showCheckboxColumn: false,
          headingRowHeight: 40,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 60,
          columnSpacing: 28,
          sortColumnIndex: sortColumn,
          sortAscending: sortAsc,
          headingTextStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
          dataTextStyle: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
          columns: [
            DataColumn(label: const Text('FACILITY'), onSort: onSort),
            DataColumn(label: const Text('RESIDENT'), onSort: onSort),
            DataColumn(label: const Text('WHEN'), onSort: onSort),
            DataColumn(label: const Text('OCCASION'), onSort: onSort),
            DataColumn(label: const Text('GUESTS'), onSort: onSort),
            DataColumn(label: const Text('STATUS'), onSort: onSort),
            if (_canReview) const DataColumn(label: Text('ACTIONS')),
          ],
          rows: [
            for (final r in pageSlice(pinFocused(rows), _page))
              DataRow(color: focusRowColor(r), cells: [
                DataCell(Text(_facilityName(r))),
                DataCell(Text(_name(r['resident'] as Map<String, dynamic>?))),
                DataCell(Text(_when(r))),
                DataCell(Text((r['occasion'] ?? '—').toString())),
                DataCell(Text((r['guest_count'] ?? '—').toString())),
                DataCell(StatusBadge((r['status'] ?? '').toString())),
                if (_canReview)
                  DataCell(
                    r['status'] == 'pending'
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: _busy ? null : () => _reject(r),
                                style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFFA82F2F)),
                                child: const Text('Reject'),
                              ),
                              TextButton(
                                onPressed: _busy ? null : () => _approve(r),
                                child: const Text('Approve'),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
              ]),
          ],
        ),
      ),
    );
  }
}
