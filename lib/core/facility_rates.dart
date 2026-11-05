import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import 'text_utils.dart';

/// Facility pricing text and the booking price quote.
///
/// The database sets the real fee (`price_reservation()`); the app only
/// describes rates and asks for a quote, so the quote matches the bill.
///
/// Rate types:
///   flat      one rental per booking, optional extension per hour past
///             `included_hours`
///   per_hour  rate x hours
///   per_head  rate per adult + child rate per kid
///
/// Homeowner rate = has a lot, not a tenant, no overdue bills. Everyone else
/// pays the non-homeowner rate.

/// True if the facility charges per person.
bool facilityIsPerHead(Map<String, dynamic> f) => f['rate_type'] == 'per_head';

bool _priced(Map<String, dynamic> f) =>
    f['member_rate'] != null || f['guest_rate'] != null;

String _unit(Map<String, dynamic> f) => switch (f['rate_type']) {
      'per_hour' => '/hr',
      'per_head' => '/adult',
      _ => '',
    };

String _peso0(Object? v) {
  final s = formatPeso(v);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

/// One short line for a facility card, e.g. "From ₱200/hr".
String facilityPriceShort(Map<String, dynamic> f) {
  if (!_priced(f)) {
    final fee = num.tryParse(f['fee']?.toString() ?? '0') ?? 0;
    return fee > 0 ? _peso0(fee) : 'Free';
  }
  final rates = [f['member_rate'], f['member_rate_weekend'], f['guest_rate'], f['guest_rate_weekend']]
      .map((v) => num.tryParse(v?.toString() ?? ''))
      .whereType<num>()
      .toList();
  if (rates.isEmpty) return 'Free';
  rates.sort();
  return 'From ${_peso0(rates.first)}${_unit(f)}';
}

/// The full rate card, one line per item.
List<String> facilityRateLines(Map<String, dynamic> f) {
  if (!_priced(f)) {
    final fee = num.tryParse(f['fee']?.toString() ?? '0') ?? 0;
    return [fee > 0 ? 'Booking fee ${_peso0(fee)}' : 'Free to book'];
  }
  final u = _unit(f);
  String rate(String base, String weekend) {
    final a = f[base];
    final b = f[weekend];
    if (a == null) return '—';
    if (b == null || b.toString() == a.toString()) return '${_peso0(a)}$u';
    return '${_peso0(a)}$u weekdays · ${_peso0(b)}$u weekends';
  }

  final lines = <String>[
    'Homeowner (good standing): ${rate('member_rate', 'member_rate_weekend')}'
        '${facilityIsPerHead(f) && f['member_child_rate'] != null ? ' · kids ${_peso0(f['member_child_rate'])}' : ''}',
    'Non-homeowner: ${rate('guest_rate', 'guest_rate_weekend')}'
        '${facilityIsPerHead(f) && f['guest_child_rate'] != null ? ' · kids ${_peso0(f['guest_child_rate'])}' : ''}',
  ];
  final hrs = f['included_hours'];
  if (hrs != null && (f['member_extension_rate'] != null || f['guest_extension_rate'] != null)) {
    lines.add('Over ${num.tryParse(hrs.toString())?.toStringAsFixed(0) ?? hrs} hours: '
        '${_peso0(f['member_extension_rate'])}/hr homeowner · '
        '${_peso0(f['guest_extension_rate'])}/hr non-homeowner');
  }
  final bond = num.tryParse(f['cash_bond']?.toString() ?? '0') ?? 0;
  if (bond > 0) lines.add('Cash bond ${_peso0(bond)} (refundable)');
  return lines;
}

/// Shows the database's price for a booking being filled in; refetches when
/// any input changes.
class ReservationQuote extends StatefulWidget {
  final Object? facilityId;
  final int? userId;
  final DateTime starts;
  final DateTime ends;
  final int people;
  final int kids;
  final Color textColor;

  const ReservationQuote({
    super.key,
    required this.facilityId,
    required this.userId,
    required this.starts,
    required this.ends,
    required this.people,
    required this.kids,
    required this.textColor,
  });

  @override
  State<ReservationQuote> createState() => _ReservationQuoteState();
}

class _ReservationQuoteState extends State<ReservationQuote> {
  Map<String, dynamic>? _quote;
  bool _loading = false;
  String? _error;
  int _seq = 0;

  String get _key =>
      '${widget.facilityId}|${widget.userId}|${widget.starts}|${widget.ends}|${widget.people}|${widget.kids}';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant ReservationQuote old) {
    super.didUpdateWidget(old);
    final before = '${old.facilityId}|${old.userId}|${old.starts}|${old.ends}|${old.people}|${old.kids}';
    if (before != _key) _fetch();
  }

  Future<void> _fetch() async {
    if (widget.userId == null || widget.facilityId == null || !widget.ends.isAfter(widget.starts)) {
      setState(() {
        _quote = null;
        _error = null;
      });
      return;
    }
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final res = await SupabaseService.instance.client.rpc('quote_reservation_fee', params: {
        'p_facility': widget.facilityId,
        'p_user': widget.userId,
        'p_starts': widget.starts.toUtc().toIso8601String(),
        'p_ends': widget.ends.toUtc().toIso8601String(),
        'p_people': widget.people,
        'p_kids': widget.kids,
      });
      if (!mounted || seq != _seq) return;
      setState(() {
        _quote = res is Map ? Map<String, dynamic>.from(res) : null;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _quote = null;
        _error = 'Could not work out the price right now. It will be shown on the bill.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text(_error!, style: TextStyle(fontSize: 12, color: widget.textColor));
    }
    final q = _quote;
    if (q == null) {
      return _loading
          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const SizedBox.shrink();
    }
    final fee = num.tryParse(q['fee']?.toString() ?? '0') ?? 0;
    final breakdown = (q['breakdown'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5EE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fee > 0 ? 'Total: ${formatPeso(fee)}' : 'Free',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: widget.textColor)),
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(breakdown, style: TextStyle(fontSize: 12, color: widget.textColor)),
          ],
          if (fee > 0) ...[
            const SizedBox(height: 4),
            Text('Billed once the booking is approved.',
                style: TextStyle(fontSize: 11.5, color: widget.textColor.withValues(alpha: 0.75))),
          ],
        ],
      ),
    );
  }
}
