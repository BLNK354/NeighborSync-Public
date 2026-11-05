import 'package:flutter/material.dart';
import '../core/text_utils.dart';
import '../core/visitor_rules.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';

/// Live summary cards shown inside a module form, set up with
/// `ModuleConfig.contextAfterField` / `contextBuilder`.
///
/// They show the officer facts that are not on the form (who the resident
/// is, what is still owed). Each card loads its own data; if it fails it
/// says so and the form still works.

/// Shared box for all the cards: same padding, radius and tint.
class _ContextCard extends StatelessWidget {
  final Widget child;

  /// Tints the card amber to flag something to act on before saving.
  final bool warn;
  const _ContextCard({required this.child, this.warn = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn ? AppColors.badgeAmberBg : AppColors.highlight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// A quiet card with a short message, used for loading and empty states.
Widget _hint(String text) => _ContextCard(
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
    );

/// Runs [load] and shows [builder] with the result. Shows a placeholder
/// while loading, and [emptyText] on error or no data; never throws into
/// the form.
class _CardLoader<T> extends StatefulWidget {
  final Future<T?> Function() load;
  final Widget Function(T data) builder;
  final String emptyText;
  const _CardLoader(
      {super.key,
      required this.load,
      required this.builder,
      required this.emptyText});

  @override
  State<_CardLoader<T>> createState() => _CardLoaderState<T>();
}

class _CardLoaderState<T> extends State<_CardLoader<T>> {
  late Future<T?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _hint('Loading…');
        }
        if (snap.hasError || snap.data == null) {
          return _hint(widget.emptyText);
        }
        return widget.builder(snap.data as T);
      },
    );
  }
}

/// "First Last" from a user row, or empty if missing.
String _fullName(Map<String, dynamic>? row) {
  if (row == null) return '';
  return [row['first_name'], row['last_name']]
      .map((v) => (v ?? '').toString().trim())
      .where((v) => v.isNotEmpty)
      .join(' ');
}

/// One or two capital letters for the avatar circle.
String _initials(String name) {
  final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '—';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

/// "Block X · Lot Y" from a lot row that embeds its block.
String _addressOf(Map<String, dynamic>? lot) {
  if (lot == null) return 'No lot on record';
  final block = (lot['blocks'] as Map<String, dynamic>?)?['block_name'];
  return 'Block ${block ?? '—'} · Lot ${lot['lot_number'] ?? '—'}';
}

/// Date as "5 Oct 2026", or a dash if it cannot be read.
String _shortDate(Object? v) {
  final dt = DateTime.tryParse((v ?? '').toString());
  if (dt == null) return '—';
  const m = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${dt.day} ${m[dt.month]} ${dt.year}';
}

// ---------------------------------------------------------------------
// Billing — who this bill is for
// ---------------------------------------------------------------------

/// Shows the resident a bill is for: name, address and unpaid bill count.
Widget billingResidentCard(Map<String, dynamic> values) {
  final userId = values['user_id'];
  if (userId == null) {
    return _hint('Pick a resident and their address will appear here.');
  }
  return _CardLoader<Map<String, dynamic>>(
    // Keyed on the id so a new pick reloads the details.
    key: ValueKey('billing-resident-$userId'),
    emptyText: 'Could not load this resident.',
    load: () async {
      final c = SupabaseService.instance.client;
      // Name the FK (`lot:lot_id`): users has two FKs to lots, so a bare
      // `lots(...)` embed is ambiguous and the query fails.
      final user = await c
          .from('users')
          .select(
              'first_name, last_name, lot:lot_id(lot_number, blocks(block_name))')
          .eq('id', userId)
          .maybeSingle();
      if (user == null) return null;
      final unpaid = await c
          .from('bills')
          .select('id')
          .eq('user_id', userId)
          .inFilter('status', ['pending', 'partial', 'overdue']);
      return {'user': user, 'unpaid': (unpaid as List).length};
    },
    builder: (data) {
      final user = Map<String, dynamic>.from(data['user'] as Map);
      final unpaid = data['unpaid'] as int;
      final name = _fullName(user);
      return _ContextCard(
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: AppColors.badgeGreenBg,
                  borderRadius: BorderRadius.circular(17)),
              child: Text(_initials(name),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.sidebarActiveText)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? '—' : name,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text(
                    '${_addressOf(user['lot'] as Map<String, dynamic>?)} · '
                    '${unpaid == 0 ? 'nothing outstanding' : '$unpaid unpaid bill${unpaid == 1 ? '' : 's'}'}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------
// Payments — what is still owed on the chosen bill
// ---------------------------------------------------------------------

/// Shows the bill a payment is for, with its remaining balance (amount +
/// penalty - discount - verified payments) and what saving will do.
/// Only payments with status `verified` count toward the bill.
Widget paymentBillCard(Map<String, dynamic> values) {
  final billId = values['bill_id'];
  if (billId == null) {
    return _hint('Pick a bill and its balance will appear here.');
  }
  final status = (values['status'] ?? 'pending').toString();
  return _CardLoader<Map<String, dynamic>>(
    key: ValueKey('payment-bill-$billId-$status'),
    emptyText: 'Could not load this bill.',
    load: () async {
      final c = SupabaseService.instance.client;
      // Name the FK (`resident:user_id`): bills has two FKs to users.
      final bill = await c
          .from('bills')
          .select('bill_number, status, due_date, amount, penalty_amount, '
              'discount_amount, resident:user_id(first_name, last_name), '
              'lot:lot_id(lot_number, blocks(block_name))')
          .eq('id', billId)
          .maybeSingle();
      if (bill == null) return null;
      final paid = await c
          .from('payments')
          .select('amount_paid')
          .eq('bill_id', billId)
          .eq('status', 'verified');
      var paidSoFar = 0.0;
      for (final p in paid as List) {
        paidSoFar += num.tryParse('${p['amount_paid']}')?.toDouble() ?? 0;
      }
      return {'bill': bill, 'paidSoFar': paidSoFar};
    },
    builder: (data) {
      final bill = Map<String, dynamic>.from(data['bill'] as Map);
      final paidSoFar = data['paidSoFar'] as double;
      double n(Object? v) => num.tryParse('${v ?? 0}')?.toDouble() ?? 0;
      final due = n(bill['amount']) +
          n(bill['penalty_amount']) -
          n(bill['discount_amount']);
      final balance = due - paidSoFar;
      final name = _fullName(bill['resident'] as Map<String, dynamic>?);
      final willVerify = status == 'verified';
      // The database refuses a verified payment on a settled bill; warn
      // here before the officer fills in the rest.
      final settled = balance <= 0;

      return _ContextCard(
        warn: settled && willVerify,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((bill['bill_number'] ?? '—').toString(),
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppColors.badgeAmberBg,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(titleCase((bill['status'] ?? '').toString()),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${name.isEmpty ? '—' : name} · '
              '${_addressOf(bill['lot'] as Map<String, dynamic>?)} · '
              'due ${_shortDate(bill['due_date'])}',
              style:
                  const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: AppColors.border),
            ),
            // Balance can be negative; show it as "Overpaid by".
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    balance > 0
                        ? 'Balance remaining'
                        : balance == 0
                            ? 'Fully settled'
                            : 'Overpaid by',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text(formatPeso(balance.abs()),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              settled
                  ? willVerify
                      ? 'Nothing left to pay on this bill — a verified payment '
                          'will be refused. Void the earlier payment first if '
                          'this one is a correction.'
                      : 'Nothing left to pay on this bill. This can be saved as '
                          'Pending, but it cannot be verified while the earlier '
                          'payment stands.'
                  : willVerify
                      ? 'The bill updates to Partial or Paid as soon as this is saved.'
                      : 'Saved as Pending — the bill only updates once this payment is verified.',
              style: TextStyle(
                  fontSize: 11,
                  color: settled ? AppColors.textPrimary : AppColors.textMuted),
            ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------
// Gate passes — the household expecting the visitor
// ---------------------------------------------------------------------

/// Shows the host a gate pass is for: name, address and phone number, so
/// a guard knows who to call.
Widget gatePassHostCard(Map<String, dynamic> values) {
  final hostId = values['requested_by'];
  if (hostId == null) {
    return _hint('Pick the household and their details will appear here.');
  }
  return _CardLoader<Map<String, dynamic>>(
    key: ValueKey('gatepass-host-$hostId'),
    emptyText: 'Could not load this household.',
    load: () async {
      final c = SupabaseService.instance.client;
      // Name the FK (`lot:lot_id`): users has two FKs to lots.
      final user = await c
          .from('users')
          .select('first_name, last_name, phone, '
              'lot:lot_id(lot_number, blocks(block_name))')
          .eq('id', hostId)
          .maybeSingle();
      if (user == null) return null;
      return {'user': user};
    },
    builder: (data) {
      final user = Map<String, dynamic>.from(data['user'] as Map);
      final name = _fullName(user);
      final phone = (user['phone'] ?? '').toString().trim();
      return _ContextCard(
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: AppColors.badgeGreenBg,
                  borderRadius: BorderRadius.circular(17)),
              child: Text(_initials(name),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.sidebarActiveText)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? '—' : name,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text(
                    '${_addressOf(user['lot'] as Map<String, dynamic>?)}'
                    '${phone.isEmpty ? ' · no phone on record' : ' · $phone'}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Shows whose permit this is: applicant name, address and phone.
Widget permitApplicantCard(Map<String, dynamic> values) {
  final applicantId = values['applicant_id'];
  if (applicantId == null) {
    return _hint('Pick the resident applying and their details will appear here.');
  }
  return _CardLoader<Map<String, dynamic>>(
    key: ValueKey('permit-applicant-$applicantId'),
    emptyText: 'Could not load this resident.',
    load: () async {
      final user = await SupabaseService.instance.client
          .from('users')
          .select('first_name, last_name, phone, '
              'lot:lot_id(lot_number, blocks(block_name))')
          .eq('id', applicantId)
          .maybeSingle();
      return user == null ? null : {'user': user};
    },
    builder: (data) {
      final user = Map<String, dynamic>.from(data['user'] as Map);
      final name = _fullName(user);
      final phone = (user['phone'] ?? '').toString().trim();
      return _ContextCard(
        child: Row(
          children: [
            const Icon(Icons.person_outline, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Applicant: ${name.isEmpty ? '—' : name}',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text(
                    '${_addressOf(user['lot'] as Map<String, dynamic>?)}'
                    '${phone.isEmpty ? '' : ' · $phone'}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------
// Vehicles — the plate, at a glance
// ---------------------------------------------------------------------

/// Summary header for a vehicle: plate, status, make/model line and
/// sticker with expiry. Reads only the form values (no query) and shows
/// nothing until a plate is entered.
Widget vehicleSummaryCard(Map<String, dynamic> values) {
  final plate = (values['plate_number'] ?? '').toString().trim();
  if (plate.isEmpty) return const SizedBox.shrink();

  final status = (values['status'] ?? '').toString();
  final sticker = (values['sticker_number'] ?? '').toString().trim();
  final expiry = values['sticker_expiry'];
  final spec = [
    for (final k in ['make', 'model', 'color', 'year'])
      if ((values[k] ?? '').toString().trim().isNotEmpty)
        values[k].toString().trim(),
    if ((values['vehicle_type'] ?? '').toString().isNotEmpty)
      titleCase(values['vehicle_type'].toString()),
  ].join(' · ');

  // A lapsed sticker tints the card amber.
  final expiryDate = DateTime.tryParse((expiry ?? '').toString());
  final lapsed =
      expiryDate != null && expiryDate.isBefore(DateTime.now());

  return _ContextCard(
    warn: lapsed,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(plate,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: AppColors.textPrimary)),
            ),
            if (status.isNotEmpty) StatusBadge(status),
          ],
        ),
        if (spec.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(spec,
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textMuted)),
        ],
        if (sticker.isNotEmpty || expiryDate != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(sticker.isEmpty ? 'No sticker issued' : 'Sticker $sticker',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text(
                expiryDate == null
                    ? ''
                    : '${lapsed ? 'expired' : 'expires'} ${_shortDate(expiry)}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: lapsed ? FontWeight.w600 : FontWeight.w400,
                    color: lapsed
                        ? AppColors.textPrimary
                        : AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

// ---------------------------------------------------------------------
// Budget — what is already committed for the year
// ---------------------------------------------------------------------

/// Shows what the fiscal year already has allocated, and the total after
/// this category is added.
Widget budgetYearCard(Map<String, dynamic> values) {
  final year = values['fiscal_year'];
  if (year == null || year.toString().isEmpty) {
    return _hint('Pick a fiscal year to see what is already allocated.');
  }
  final adding = num.tryParse('${values['allocated_amount'] ?? ''}') ?? 0;
  return _CardLoader<Map<String, dynamic>>(
    key: ValueKey('budget-year-$year'),
    emptyText: 'Could not load this year\'s budget.',
    load: () async {
      final c = SupabaseService.instance.client;
      // No phase filter needed: RLS already limits this to the caller's phase.
      final rows = await c
          .from('budget_categories')
          .select('allocated_amount')
          .eq('fiscal_year', year);
      var total = 0.0;
      for (final r in rows as List) {
        total += num.tryParse('${r['allocated_amount']}')?.toDouble() ?? 0;
      }
      return {'count': (rows).length, 'total': total};
    },
    builder: (data) {
      final count = data['count'] as int;
      final total = data['total'] as double;
      return _ContextCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Already allocated for $year',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text('$count categor${count == 1 ? 'y' : 'ies'}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(formatPeso(total),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                if (adding > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('→ ${formatPeso(total + adding)} after this',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textMuted)),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// Shows when a visitor is expected to leave, worked out from the purpose
/// and time in (see expectedOut() in visitor_rules.dart). Nothing is stored.
Widget visitorClockCard(Map<String, dynamic> values) {
  final rawIn = values['time_in'];
  DateTime? tIn;
  if (rawIn is DateTime) {
    tIn = rawIn;
  } else if (rawIn is String && rawIn.isNotEmpty) {
    tIn = DateTime.tryParse(rawIn);
  }
  final purpose = values['purpose_type']?.toString();
  if (tIn == null || purpose == null || purpose.isEmpty) {
    return _hint('Pick a purpose and a time in to see when this visitor is '
        'expected to leave.');
  }
  final mins = kAllottedMinutesFor(purpose);
  final due = tIn.toLocal().add(Duration(minutes: mins));
  final out = values['time_out'];
  final left = out != null && out.toString().isNotEmpty;
  final late = !left && DateTime.now().isAfter(due);
  final allotted = mins >= 60
      ? '${mins ~/ 60}h${mins % 60 == 0 ? '' : ' ${mins % 60}m'}'
      : '$mins min';
  return _ContextCard(
    warn: late,
    child: Row(
      children: [
        Icon(late ? Icons.timer_off_outlined : Icons.schedule,
            size: 18, color: late ? AppColors.badgeAmberText : AppColors.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Expected time out: ${_clockLabel(due)}  ·  '
            '${visitorPurposeLabel(purpose)} allows $allotted'
            '${late ? '  ·  overstaying' : ''}',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: late ? AppColors.badgeAmberText : AppColors.textPrimary),
          ),
        ),
      ],
    ),
  );
}

/// Date and 12-hour time, e.g. "Oct 5, 3:30 PM".
String _clockLabel(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${months[d.month - 1]} ${d.day}, $h:$m $ap';
}
