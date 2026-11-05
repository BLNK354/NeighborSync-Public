import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../core/form_helpers.dart';
import '../core/permissions.dart';
import '../core/refresh_bus.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/person_link.dart';
import '../widgets/person_files_dialog.dart';
import '../widgets/responsive_officer_shell.dart';
import '../widgets/status_badge.dart';
import '../core/safe_state.dart';
import '../core/text_utils.dart';

/// Shows everything the HOA holds on one person: profile plus their records.
///
/// A section only appears if the officer may read that module, so no empty
/// headings show for features they cannot use. Phase limits come from the
/// database policies, so no extra checks are needed here.
class PersonDetailScreen extends StatefulWidget {
  final int userId;
  const PersonDetailScreen({super.key, required this.userId});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> with SafeSetState<PersonDetailScreen> {
  Map<String, dynamic>? _person;
  Map<String, Set<String>> _perms = {};
  bool _loading = true;
  String? _error;

  /// Module key -> that person's rows. A missing key means "not allowed";
  /// an empty list means "nothing on file".
  final Map<String, List<Map<String, dynamic>>> _records = {};

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// (module, table, owner column, columns to select, ordering column).
  /// The owner column differs per table, so each one is listed.
  static const _sections = <_SectionSpec>[
    _SectionSpec('bills', 'bills', 'user_id',
        'id, bill_number, amount, status, due_date', 'due_date'),
    // payments uses amount_paid; it has no `amount` column.
    _SectionSpec('payments', 'payments', 'user_id',
        'id, or_number, amount_paid, status, payment_date', 'payment_date'),
    _SectionSpec('complaints', 'complaints', 'complainant_id',
        'id, complaint_number, subject, status, created_at', 'created_at'),
    _SectionSpec('permits', 'permits', 'applicant_id',
        'id, permit_number, title, status, created_at', 'created_at'),
    _SectionSpec('vehicles', 'vehicles', 'user_id',
        'id, plate_number, make, model, status', 'created_at'),
    _SectionSpec('gate_passes', 'gate_passes', 'requested_by',
        'id, pass_number, visitor_name, status, created_at', 'created_at'),
    _SectionSpec('move_requests', 'move_requests', 'resident_id',
        'id, request_type, move_date, status', 'created_at'),
    _SectionSpec('household_members', 'household_members', 'resident_id',
        'id, full_name, relationship', 'created_at'),
    _SectionSpec('violations', 'violations', 'reported_against',
        'id, violation_number, status, created_at', 'created_at'),
    _SectionSpec('reservations', 'reservations', 'user_id',
        'id, starts_at, status, facilities(name)', 'starts_at'),
  ];

  /// Loads the person and, in one batch, their records for each allowed module.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = SupabaseService.instance.client;
      final perms = await SupabaseService.instance.getMyPermissions();
      final person = await c
          .from('users')
          // Keep `lot:lot_id(...)`: users has two foreign keys to lots, so a
          // bare `lots(...)` embed is ambiguous and the whole query fails.
          .select('id, first_name, last_name, email, phone, status, phase, '
              'created_at, lot_id, account_label, roles(name, display_name), '
              'lot:lot_id(lot_number, street_address, blocks(block_name, phase))')
          .eq('id', widget.userId)
          .maybeSingle();

      _records.clear();
      // Only query modules this officer may read, to skip useless requests.
      final wanted =
          _sections.where((s) => canAccessModule(perms, s.module)).toList();
      final rows = await Future.wait([
        for (final s in wanted)
          c
              .from(s.table)
              .select(s.columns)
              .eq(s.ownerColumn, widget.userId)
              .order(s.orderBy, ascending: false)
              .limit(100),
      ]);

      if (!mounted) return;
      setState(() {
        _person = person;
        _perms = perms;
        for (var i = 0; i < wanted.length; i++) {
          _records[wanted[i].module] =
              List<Map<String, dynamic>>.from(rows[i] as List);
        }
        _loading = false;
      });

      // Audit log: records who viewed this person's full file.
      // Only logged when the person was found, so blocked views are not recorded.
      if (person != null) {
        unawaited(SupabaseService.instance.logAuditAction(
          'view',
          'accounts',
          resource: [person['first_name'], person['last_name']]
              .where((v) => v != null && v.toString().trim().isNotEmpty)
              .join(' '),
          resourceId: widget.userId,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _queryError(e);
        _loading = false;
      });
    }
  }

  /// Shows the database's own error text when there is one, because it names
  /// the bad column or relationship. Other errors use friendlyError.
  static String _queryError(Object e) {
    if (e is PostgrestException && e.message.trim().isNotEmpty) {
      return e.message;
    }
    return friendlyError(e);
  }

  String get _fullName {
    final p = _person;
    if (p == null) return 'Account';
    final n = [p['first_name'], p['last_name']]
        .where((s) => s != null && s.toString().trim().isNotEmpty)
        .join(' ')
        .trim();
    return n.isEmpty ? 'Account' : n;
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: _loading ? 'Account' : _fullName,
      activeItem: 'All Accounts',
      // No bottom tab belongs to this page, so the tab is left blank.
      activeTab: '',
      desktopChild: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    }
    if (_person == null) {
      // Also shown for other phases; do not reveal that the account exists.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('That account is not available.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ),
      );
    }

    final shown = [
      for (final s in _sections)
        if (_records.containsKey(s.module)) s,
    ];
    final filled = shown.where((s) => _records[s.module]!.isNotEmpty).toList();
    final empty = shown.where((s) => _records[s.module]!.isEmpty).toList();

    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 700;
      return SingleChildScrollView(
        padding: EdgeInsets.all(narrow ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _backLink(),
            const SizedBox(height: 12),
            _profileCard(narrow),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 16),
              _summaryStrip(shown),
            ],
            const SizedBox(height: 20),
            if (filled.isNotEmpty) _sectionGrid(filled, c.maxWidth),
            if (empty.isNotEmpty) ...[
              const SizedBox(height: 4),
              _emptyNote(empty),
            ],
          ],
        ),
      );
    });
  }

  Widget _backLink() => TextButton.icon(
        onPressed: () => context.go('/admin/accounts'),
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
        icon: const Icon(Icons.arrow_back, size: 16),
        label: const Text('All Accounts'),
      );

  String get _initials {
    final p = _person!;
    String first(Object? v) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty ? '' : t[0].toUpperCase();
    }
    final i = '${first(p['first_name'])}${first(p['last_name'])}';
    return i.isEmpty ? '?' : i;
  }

  /// Top card: avatar, name, badges, Files button and contact facts.
  Widget _profileCard(bool narrow) {
    final p = _person!;
    final role = (p['roles'] as Map?)?['display_name']?.toString() ?? '—';
    final lot = p['lot'] as Map<String, dynamic>?;
    final block = (lot?['blocks'] as Map?)?['block_name']?.toString();
    final phase = (lot?['blocks'] as Map?)?['phase']?.toString() ??
        (p['phase'] ?? '').toString();
    final address = lot == null
        ? 'No address on record'
        : [
            if (phase.trim().isNotEmpty) 'Phase $phase',
            if (block != null && block.trim().isNotEmpty) 'Block $block',
            'Lot ${lot['lot_number'] ?? ''}',
            if ((lot['street_address'] ?? '').toString().trim().isNotEmpty)
              lot['street_address'].toString(),
          ].join(' · ');
    String orDash(Object? v) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty ? '—' : t;
    }

    final avatar = Container(
      width: narrow ? 56 : 68,
      height: narrow ? 56 : 68,
      decoration: BoxDecoration(
        color: AppColors.badgeGreenBg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      alignment: Alignment.center,
      child: Text(_initials,
          style: TextStyle(
              fontSize: narrow ? 20 : 24,
              fontWeight: FontWeight.w700,
              color: AppColors.sidebarActiveText)),
    );

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_fullName,
            style: TextStyle(
                fontSize: narrow ? 19 : 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          StatusBadge((p['status'] ?? '').toString()),
          _chip(role),
          if (phase.trim().isNotEmpty) _chip('Phase $phase'),
          if (accountLabelText(p['account_label']) != null)
            AccountLabelChip(p['account_label']),
        ]),
      ],
    );

    final filesButton = canPerform(_perms, 'documents', 'read')
        ? OutlinedButton.icon(
            onPressed: () => showPersonFilesDialog(
              context,
              userId: widget.userId,
              personName: _fullName,
            ),
            icon: const Icon(Icons.folder_outlined, size: 16),
            label: const Text('Files'),
          )
        : null;

    final facts = [
      _Fact(Icons.email_outlined, 'Email', orDash(p['email'])),
      _Fact(Icons.phone_outlined, 'Phone', orDash(p['phone'])),
      _Fact(Icons.home_outlined, 'Address', address),
      _Fact(Icons.event_outlined, 'Joined',
          orDash((p['created_at'] ?? '').toString().split('T').first)),
    ];

    return _card(
      padding: EdgeInsets.all(narrow ? 16 : 22),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            avatar,
            const SizedBox(width: 16),
            Expanded(child: heading),
            if (filesButton != null && !narrow) filesButton,
          ]),
          if (filesButton != null && narrow) ...[
            const SizedBox(height: 12),
            filesButton,
          ],
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 520 ? 2 : 1);
            const gap = 10.0;
            final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (final f in facts) SizedBox(width: w, child: _factTile(f)),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _factTile(_Fact f) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.contentBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(f.icon, size: 17, color: AppColors.sidebarActiveText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.label,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(f.value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ]),
          ),
        ]),
      );

  /// One tile per section the officer may read, with its count. Tapping a
  /// tile that has records scrolls to that section.
  Widget _summaryStrip(List<_SectionSpec> shown) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final s in shown) _summaryTile(s),
    ]);
  }

  Widget _summaryTile(_SectionSpec s) {
    final n = _records[s.module]!.length;
    final has = n > 0;
    final tile = Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: has ? AppColors.badgeGreenBg : AppColors.highlight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(s.icon,
              size: 16,
              color: has ? AppColors.sidebarActiveText : AppColors.textMuted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: has ? AppColors.textPrimary : AppColors.textMuted)),
            Text(s.shortTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
      ]),
    );
    if (!has) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          final ctx = _sectionKeys[s.module]?.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 300),
                alignment: 0.05);
          }
        },
        child: tile,
      ),
    );
  }

  /// Keys used to scroll to each section from its summary tile.
  final Map<String, GlobalKey> _sectionKeys = {};

  /// Lays out the sections that have records, one or two columns wide.
  Widget _sectionGrid(List<_SectionSpec> filled, double width) {
    final cols = width >= 1000 ? 2 : 1;
    const gap = 14.0;
    final w = ((width - (width < 700 ? 32 : 48) - gap * (cols - 1)) / cols)
        .floorToDouble();
    return Wrap(spacing: gap, runSpacing: gap, children: [
      for (final s in filled)
        SizedBox(
          key: _sectionKeys.putIfAbsent(s.module, () => GlobalKey()),
          width: w,
          child: _sectionCard(s),
        ),
    ]);
  }

  /// One card listing a section's records.
  Widget _sectionCard(_SectionSpec s) {
    final rows = _records[s.module] ?? const [];
    return _card(
      padding: EdgeInsets.zero,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Icon(s.icon, size: 18, color: AppColors.sidebarActiveText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.title,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              _chip('${rows.length}'),
            ]),
          ),
          const Divider(height: 1, color: AppColors.border),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
            _recordRow(s, rows[i]),
          ],
        ],
      ),
    );
  }

  Widget _recordRow(_SectionSpec s, Map<String, dynamic> r) {
    final (title, subtitle) = s.describe(r);
    final status = (r['status'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          if (status.isNotEmpty) StatusBadge(status),
        ],
      ),
    );
  }

  /// Names the empty sections on one line instead of showing empty cards.
  Widget _emptyNote(List<_SectionSpec> empty) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.inbox_outlined, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nothing on file yet for: '
              '${empty.map((s) => s.shortTitle).join(', ')}.',
              style: const TextStyle(
                  fontSize: 12.5, height: 1.45, color: AppColors.textSecondary),
            ),
          ),
        ]),
      );

  Widget _card(Widget child, {EdgeInsetsGeometry padding = const EdgeInsets.all(16)}) =>
      Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        child: child,
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.highlight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      );
}

/// One labelled contact detail in the profile card.
class _Fact {
  final IconData icon;
  final String label;
  final String value;
  const _Fact(this.icon, this.label, this.value);
}

/// Describes one record section: what to query and how to show a row.
class _SectionSpec {
  final String module;
  final String table;
  final String ownerColumn;
  final String columns;
  final String orderBy;

  const _SectionSpec(
      this.module, this.table, this.ownerColumn, this.columns, this.orderBy);

  String get title {
    switch (module) {
      case 'bills':
        return 'Bills';
      case 'payments':
        return 'Payments';
      case 'complaints':
        return 'Complaints filed';
      case 'permits':
        return 'Permits';
      case 'vehicles':
        return 'Vehicles';
      case 'gate_passes':
        return 'Gate passes';
      case 'move_requests':
        return 'Move in / out';
      case 'household_members':
        return 'Household members';
      case 'violations':
        return 'Violations issued';
      case 'reservations':
        return 'Reservations';
      default:
        return module;
    }
  }

  String get shortTitle {
    switch (module) {
      case 'complaints':
        return 'Complaints';
      case 'violations':
        return 'Violations';
      case 'household_members':
        return 'Household';
      default:
        return title;
    }
  }

  IconData get icon {
    switch (module) {
      case 'bills':
        return Icons.receipt_long_outlined;
      case 'payments':
        return Icons.payments_outlined;
      case 'complaints':
        return Icons.report_outlined;
      case 'permits':
        return Icons.assignment_outlined;
      case 'vehicles':
        return Icons.directions_car_outlined;
      case 'gate_passes':
        return Icons.qr_code_2_outlined;
      case 'move_requests':
        return Icons.local_shipping_outlined;
      case 'household_members':
        return Icons.family_restroom_outlined;
      case 'violations':
        return Icons.gavel_outlined;
      case 'reservations':
        return Icons.event_available_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  /// Returns (title, subtitle) for one row of this module.
  (String, String) describe(Map<String, dynamic> r) {
    String s(Object? v) => (v ?? '').toString();
    String date(Object? v) => s(v).split('T').first;
    switch (module) {
      case 'bills':
        return ('#${s(r['bill_number'])}',
            '${formatPeso(r['amount'])} · due ${date(r['due_date'])}');
      case 'payments':
        return ('OR ${s(r['or_number'])}',
            '${formatPeso(r['amount_paid'])} · ${date(r['payment_date'])}');
      case 'complaints':
        return ('#${s(r['complaint_number'])}',
            '${s(r['subject'])} · ${date(r['created_at'])}');
      case 'permits':
        return ('#${s(r['permit_number'])}',
            '${s(r['title'])} · ${date(r['created_at'])}');
      case 'vehicles':
        return (s(r['plate_number']),
            [s(r['make']), s(r['model'])].where((x) => x.isNotEmpty).join(' '));
      case 'gate_passes':
        return ('#${s(r['pass_number'])}',
            '${s(r['visitor_name'])} · ${date(r['created_at'])}');
      case 'move_requests':
        return (s(r['request_type']).isEmpty ? 'Request' : s(r['request_type']),
            'Move ${date(r['move_date'])}');
      case 'household_members':
        return (s(r['full_name']), s(r['relationship']));
      case 'violations':
        return ('#${s(r['violation_number'])}', date(r['created_at']));
      case 'reservations':
        return (s((r['facilities'] as Map?)?['name']).isEmpty
            ? 'Reservation'
            : s((r['facilities'] as Map?)?['name']),
            date(r['starts_at']));
      default:
        return (s(r['id']), '');
    }
  }
}
