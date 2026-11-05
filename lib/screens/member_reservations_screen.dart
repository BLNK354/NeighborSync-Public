import 'package:flutter/material.dart';
import '../core/facility_rates.dart';
import '../core/form_helpers.dart';
import '../services/supabase_service.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/safe_state.dart';

/// Resident facility booking: pick a facility, request a slot, and see or
/// cancel your own reservations.
///
/// Other residents' bookings show only their time range, never who or why;
/// keep the query to those columns. The database blocks overlapping bookings
/// (reservations_no_double_booking), so checks here only give clear messages.
class MemberReservationsScreen extends StatefulWidget {
  const MemberReservationsScreen({super.key});

  @override
  State<MemberReservationsScreen> createState() => _MemberReservationsScreenState();
}

class _MemberReservationsScreenState extends State<MemberReservationsScreen> with SafeSetState<MemberReservationsScreen> {
  List<Map<String, dynamic>> _facilities = [];
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _busy = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
      final myId = await SupabaseService.instance.getMyUserId();
      final c = SupabaseService.instance.client;
      final results = await Future.wait<dynamic>([
        c.from('facilities').select('*').eq('is_active', true).order('name'),
        c
            .from('reservations')
            .select('*, facility:facility_id(name, fee)')
            .eq('user_id', myId as Object)
            .order('starts_at', ascending: false)
            .limit(50),
        // Availability only: no user_id or purpose, so nobody sees who booked.
        c
            .from('reservations')
            .select('facility_id, starts_at, ends_at')
            .inFilter('status', const ['pending', 'approved'])
            .gte('starts_at', DateTime.now().toUtc().toIso8601String())
            .limit(500),
      ]);
      if (!mounted) return;
      setState(() {
        _facilities = List<Map<String, dynamic>>.from(results[0] as List);
        _mine = List<Map<String, dynamic>>.from(results[1] as List);
        _busy = List<Map<String, dynamic>>.from(results[2] as List);
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

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFA82F2F) : null,
    ));
  }

  /// Bookings already held for [facilityId] on [day], sorted by start time.
  List<Map<String, dynamic>> _busyOn(Object? facilityId, DateTime day) {
    final list = _busy.where((r) {
      if (r['facility_id'] != facilityId) return false;
      final s = DateTime.tryParse((r['starts_at'] ?? '').toString())?.toLocal();
      return s != null && s.year == day.year && s.month == day.month && s.day == day.day;
    }).toList()
      ..sort((a, b) => (a['starts_at'] ?? '').toString().compareTo((b['starts_at'] ?? '').toString()));
    return list;
  }

  /// "09:05 AM" style time.
  String _hhmm(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $ampm';
  }

  /// "Jan 5 · 09:00 AM – 12:00 PM" for a reservation row.
  String _rangeLabel(Map<String, dynamic> r) {
    final s = DateTime.tryParse((r['starts_at'] ?? '').toString())?.toLocal();
    final e = DateTime.tryParse((r['ends_at'] ?? '').toString())?.toLocal();
    if (s == null || e == null) return '—';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[s.month - 1]} ${s.day} · ${_hhmm(s)} – ${_hhmm(e)}';
  }

  /// Booking dialog for [facility], then sends the request for review.
  Future<void> _book(Map<String, dynamic> facility) async {
    final purposeCtrl = TextEditingController();
    final guestsCtrl = TextEditingController();
    final kidsCtrl = TextEditingController();
    final perHead = facilityIsPerHead(facility);
    final myId = await SupabaseService.instance.getMyUserId();
    if (!mounted) return;
    var day = DateTime.now().add(const Duration(days: 1));
    var start = const TimeOfDay(hour: 9, minute: 0);
    var end = const TimeOfDay(hour: 12, minute: 0);
    String occasion = 'Birthday';

    final minNotice = (facility['min_notice_hours'] as num?)?.toInt() ?? 24;
    final maxAdvance = (facility['max_advance_days'] as num?)?.toInt() ?? 90;

    String? formError;
    // Returns an error message, or null if valid. Checked inside the dialog
    // so the form stays open.
    String? problem() {
      if (occasion == 'Other' && purposeCtrl.text.trim().isEmpty) {
        return 'Please say what the booking is for.';
      }
      final s0 = DateTime(day.year, day.month, day.day, start.hour, start.minute);
      final e0 = DateTime(day.year, day.month, day.day, end.hour, end.minute);
      if (!e0.isAfter(s0)) return 'The end time has to be after the start time.';
      final g = guestCountError(guestsCtrl.text);
      if (g != null) return g;
      final cap = (facility['capacity'] as num?)?.toInt();
      final n = int.tryParse(guestsCtrl.text.trim());
      if (cap != null && n != null && n > cap) {
        return 'That is over the $cap-person capacity for ${facility['name']}.';
      }
      final k = int.tryParse(kidsCtrl.text.trim()) ?? 0;
      if (perHead && n != null && k > n) {
        return 'Kids are counted inside the number of people, so they cannot be more.';
      }
      return null;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final taken = _busyOn(facility['id'], day);
          return AlertDialog(
            title: Text('Reserve ${facility['name']}'),
            content: SizedBox(
              width: dialogContentWidth(context, 400),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in facilityRateLines(facility))
                      Text(line,
                          style: const TextStyle(
                              fontSize: 12, color: ResidentColors.textSecondary)),
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
                    // Only for "Other"; a preset occasion becomes the purpose.
                    if (occasion == 'Other') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: purposeCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                            labelText: 'What is it for?',
                            border: OutlineInputBorder()),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text('${day.year}-${day.month.toString().padLeft(2, '0')}-'
                          '${day.day.toString().padLeft(2, '0')}'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: day,
                          // Limits follow the facility's notice and advance rules.
                          firstDate: DateTime.now().add(Duration(hours: minNotice)),
                          lastDate: DateTime.now().add(Duration(days: maxAdvance)),
                        );
                        if (picked != null) setLocal(() => day = picked);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(context: context, initialTime: start);
                            if (t != null) setLocal(() => start = t);
                          },
                          child: Text('From ${start.format(context)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(context: context, initialTime: end);
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
                        helperText: facility['capacity'] == null
                            ? null
                            : 'Capacity: ${facility['capacity']}',
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
                      userId: (myId as num?)?.toInt(),
                      starts: DateTime(day.year, day.month, day.day, start.hour, start.minute),
                      ends: DateTime(day.year, day.month, day.day, end.hour, end.minute),
                      people: int.tryParse(guestsCtrl.text.trim()) ?? 0,
                      kids: perHead ? (int.tryParse(kidsCtrl.text.trim()) ?? 0) : 0,
                      textColor: ResidentColors.textPrimary,
                    ),
                    const SizedBox(height: 14),
                    // Times already taken on the chosen day.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ResidentColors.contentBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Already booked on this day',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: ResidentColors.textSecondary)),
                          const SizedBox(height: 6),
                          if (taken.isEmpty)
                            const Text('Nothing yet — the day is free.',
                                style: TextStyle(
                                    fontSize: 11.5, color: ResidentColors.textSecondary))
                          else
                            for (final t in taken)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text('· ${_rangeLabel(t)}',
                                    style: const TextStyle(
                                        fontSize: 11.5, color: ResidentColors.textPrimary)),
                              ),
                        ],
                      ),
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 12),
                      Text(formError!,
                          style: const TextStyle(
                              color: Color(0xFFA82F2F),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                  onPressed: () {
                    final p = problem();
                    if (p != null) {
                      setLocal(() => formError = p);
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('Request')),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;

    final startsAt = DateTime(day.year, day.month, day.day, start.hour, start.minute);
    final endsAt = DateTime(day.year, day.month, day.day, end.hour, end.minute);
    final guests = int.tryParse(guestsCtrl.text.trim());
    final kids = perHead ? (int.tryParse(kidsCtrl.text.trim()) ?? 0) : 0;

    setState(() => _saving = true);
    try {
      await SupabaseService.instance.client.from('reservations').insert({
        'facility_id': facility['id'],
        'user_id': myId,
        // A preset occasion doubles as the purpose.
        'purpose': occasion == 'Other' ? purposeCtrl.text.trim() : occasion,
        'occasion': occasion,
        'guest_count': guests,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        // The fee is not sent; the database sets it (price_reservation).
        'child_count': kids,
      });
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Request sent. You will be notified once it is reviewed.');
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Turn the double-booking constraint error into a readable message.
      final raw = e.toString();
      _snack(
        raw.contains('reservations_no_double_booking')
            ? 'That slot was just taken. Please pick another time.'
            : 'Could not send the request. ${friendlyError(e)}',
        error: true,
      );
      _load();
    }
  }

  /// Asks to confirm, then marks the reservation cancelled.
  Future<void> _cancel(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this reservation?'),
        content: Text('${(r['facility'] as Map<String, dynamic>?)?['name'] ?? 'Facility'}\n'
            '${_rangeLabel(r)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA82F2F)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.instance.client
          .from('reservations')
          .update({'status': 'cancelled'}).eq('id', r['id']);
      if (!mounted) return;
      _snack('Reservation cancelled.');
      _load();
    } catch (e) {
      _snack('Could not cancel. ${friendlyError(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'Reservations',
      activeItem: 'Reservations',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reserve a facility',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: ResidentColors.textPrimary)),
                      const SizedBox(height: 2),
                      const Text(
                        'Requests are reviewed by the HOA office. You will be '
                        'notified once yours is approved.',
                        style: TextStyle(fontSize: 12, color: ResidentColors.textSecondary),
                      ),
                      const SizedBox(height: 18),
                      _facilityGrid(),
                      const SizedBox(height: 28),
                      const Text('My reservations',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: ResidentColors.textPrimary)),
                      const SizedBox(height: 12),
                      if (_mine.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: ResidentColors.cardShadow),
                          child: const Text('No reservations yet.',
                              style: TextStyle(
                                  fontSize: 12.5, color: ResidentColors.textSecondary)),
                        )
                      else
                        for (final r in _mine) _myRow(r),
                    ],
                  ),
                ),
    );
  }

  /// Grid of facility cards.
  Widget _facilityGrid() {
    // Keep this early return: clamp(1, 0) throws when there are no facilities.
    if (_facilities.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8E4)),
        ),
        child: const Text(
          'No facilities are open for booking yet. The HOA office adds them; '
          'please check back later or contact the office.',
          style: TextStyle(fontSize: 13, color: Color(0xFF5F6F66)),
        ),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      const gap = 16.0;
      var cols = ((box.maxWidth + gap) / (260 + gap)).floor().clamp(1, _facilities.length);
      if (cols < 1) cols = 1;
      while (cols > 2 && _facilities.length % cols == 1) {
        cols--;
      }
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final f in _facilities) SizedBox(width: w, child: _facilityCard(f))],
      );
    });
  }

  /// One facility with its price, capacity and a Reserve button.
  Widget _facilityCard(Map<String, dynamic> f) {
    final price = facilityPriceShort(f);
    final fee = price == 'Free' ? 0 : 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: ResidentColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((f['name'] ?? '').toString(),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
          const SizedBox(height: 4),
          Text((f['description'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              if (f['capacity'] != null) ...[
                const Icon(Icons.people_outline, size: 13, color: ResidentColors.textSecondary),
                const SizedBox(width: 3),
                Text('${f['capacity']}',
                    style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
                const SizedBox(width: 12),
              ],
              Text(price,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: fee > 0 ? ResidentColors.textPrimary : const Color(0xFF1A6B43))),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : () => _book(f),
              child: const Text('Reserve'),
            ),
          ),
        ],
      ),
    );
  }

  /// One of the resident's reservations, with a cancel button while open.
  Widget _myRow(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString();
    final canCancel = status == 'pending' || status == 'approved';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: ResidentColors.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${(r['facility'] as Map<String, dynamic>?)?['name'] ?? 'Facility'} · '
                  '${r['purpose'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600,
                      color: ResidentColors.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(_rangeLabel(r),
                    style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
                // Show the reviewer's reason for a rejection.
                if (status == 'rejected' && (r['review_note'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text((r['review_note']).toString(),
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFA82F2F))),
                ],
              ],
            ),
          ),
          StatusBadge(status),
          if (canCancel)
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close, size: 18, color: ResidentColors.textSecondary),
              onPressed: () => _cancel(r),
            ),
        ],
      ),
    );
  }
}
