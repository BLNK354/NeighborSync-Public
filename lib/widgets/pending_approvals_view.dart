import 'package:flutter/material.dart';
import '../core/address_sort.dart';
import '../core/form_helpers.dart';
import '../core/refresh_bus.dart';
import '../core/roles.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../core/dialog_sizing.dart';
import 'searchable_picker.dart';
import '../core/safe_state.dart';
import '../core/stored_file.dart';

/// Pending registrations, each with a role picker, address and Approve /
/// Reject. Used as a tab in All Accounts; switches to stacked cards on narrow
/// widths.
///
/// [onCount] reports the pending count so a parent can show a badge.
class PendingApprovalsView extends StatefulWidget {
  final ValueChanged<int>? onCount;
  const PendingApprovalsView({super.key, this.onCount});

  @override
  State<PendingApprovalsView> createState() => _PendingApprovalsViewState();
}

class _PendingApprovalsViewState extends State<PendingApprovalsView> with SafeSetState<PendingApprovalsView> {
  List<Map<String, dynamic>> _pending = [];
  final Map<int, String> _selectedRole = {};
  Map<String, int> _roleIds = {};
  Map<String, String> _roleLabels = {};
  String? _myRole;

  /// lot_id -> name of the account already holding that lot, used to warn
  /// before approving onto an occupied lot.
  Map<int, String> _lotOwners = {};

  /// The lot chosen for each applicant; the officer can change the one they
  /// claimed at signup.
  final Map<int, int?> _selectedLot = {};
  List<Map<String, dynamic>> _lots = [];

  /// One phase per phase number, for the officer phase picker.
  List<Map<String, dynamic>> _phases = [];

  /// Phase an officer is approved into. Residents get theirs from their lot;
  /// an officer without one signs in to an empty system.
  final Map<int, String?> _selectedPhase = {};
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  /// Roles this officer may give: all for a super admin, all but super admin
  /// for the HOA president, otherwise only the self-service roles.
  List<String> get _assignableRoles {
    if (_myRole == 'super_admin') {
      return allRoleOrder.where((r) => _roleIds.containsKey(r)).toList();
    }
    if (_myRole == 'hoa_president') {
      return allRoleOrder.where((r) => r != 'super_admin' && _roleIds.containsKey(r)).toList();
    }
    return selfServiceRoles;
  }

  String _roleLabel(String role) => _roleLabels[role] ?? selfServiceRoleLabels[role] ?? role;

  @override
  void initState() {
    super.initState();
    // Reload when the phase switcher changes.
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Tells the parent how many applications are pending.
  void _reportCount() => widget.onCount?.call(_pending.length);

  /// Loads pending applicants, roles, lots, lot owners and phases.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = SupabaseService.instance.client;
      final results = await Future.wait<dynamic>([
        client
            .from('users')
            .select('id, first_name, last_name, email, phone, created_at, '
                'role_id, roles(name, display_name), requested_lot_id, lot_id, '
                'ownership_proof_path, ownership_proof_type')
            .eq('status', 'pending_verification')
            .order('created_at', ascending: true),
        client.from('roles').select('id, name, display_name'),
        SupabaseService.instance.getMyRole(),
        client.from('lots').select('id, lot_number, street_address, blocks(block_name, phase)'),
        // Who holds each lot; suspended accounts still count.
        client
            .from('users')
            .select('id, first_name, last_name, lot_id')
            .not('lot_id', 'is', null),
        client
            .from('phases')
            .select('code, name, number, letter')
            .eq('is_active', true)
            .order('code'),
      ]);
      if (!mounted) return;
      final pending = List<Map<String, dynamic>>.from(results[0] as List);
      final roleRows = List<Map<String, dynamic>>.from(results[1] as List);
      final myRole = results[2] as String?;
      final lotRows = List<Map<String, dynamic>>.from(results[3] as List);
      final owners = List<Map<String, dynamic>>.from(results[4] as List);
      final phaseRows = sortPhaseRows(results[5] as List);
      setState(() {
        // One entry per phase number (1A and 1B give the same access); the
        // first code is kept because users.phase references phases.code.
        final byNumber = <String, Map<String, dynamic>>{};
        for (final p in phaseRows) {
          byNumber.putIfAbsent((p['number'] ?? '').toString().trim(), () => p);
        }
        _phases = byNumber.values.toList()
          ..sort((a, b) => (a['number'] ?? '')
              .toString()
              .compareTo((b['number'] ?? '').toString()));
        _pending = pending;
        _lots = lotRows
          ..sort(compareLotRows);
        _lotOwners = {
          for (final o in owners)
            (o['lot_id'] as num).toInt():
                '${o['first_name'] ?? ''} ${o['last_name'] ?? ''}'.trim()
        };
        _roleIds = {for (final r in roleRows) r['name'] as String: r['id'] as int};
        _roleLabels = {
          for (final r in roleRows) r['name'] as String: (r['display_name'] as String?) ?? r['name'] as String
        };
        _myRole = myRole;
        for (final u in pending) {
          final roles = u['roles'] as Map<String, dynamic>?;
          _selectedRole[u['id'] as int] = (roles?['name'] as String?) ?? defaultSelfServiceRole;
          _selectedLot[u['id'] as int] =
              (u['lot_id'] ?? u['requested_lot_id']) as int?;
        }
        _loading = false;
      });
      _reportCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  /// Address text like "Phase 1A · Block 104 · Lot 3".
  String _lotLabel(Map<String, dynamic> lot) {
    final blocks = lot['blocks'] as Map<String, dynamic>?;
    final block = (blocks?['block_name'] ?? '').toString().trim();
    final phase = (blocks?['phase'] ?? '').toString().trim();
    final number = lot['lot_number'];
    return [
      if (phase.isNotEmpty) 'Phase $phase',
      if (block.isNotEmpty) 'Block $block',
      'Lot $number',
    ].join(' · ');
  }

  /// The applicant's phase, taken from the chosen address.
  String? _phaseOf(Map<String, dynamic> u) {
    final lot = _lotById(_selectedLot[u['id'] as int]);
    final p = ((lot?['blocks'] as Map<String, dynamic>?)?['phase'] ?? '')
        .toString()
        .trim();
    return p.isEmpty ? null : p;
  }

  /// Lots offered in the picker: open lots for a homeowner, occupied lots
  /// for a tenant. The lot already chosen always stays listed.
  List<Map<String, dynamic>> _lotChoices(int userId) {
    final tenant = _selectedRole[userId] == 'tenant';
    final current = _selectedLot[userId];
    return _lots.where((l) {
      final id = (l['id'] as num).toInt();
      if (id == current) return true;
      final taken = _conflictFor(userId, id) != null;
      return tenant ? taken : !taken;
    }).toList();
  }

  /// Opens the searchable address picker for one applicant.
  Future<void> _pickLot(int userId) async {
    final tenant = _selectedRole[userId] == 'tenant';
    const none = <String, dynamic>{'id': -1};
    final choices = [none, ..._lotChoices(userId)];
    final current = _lotById(_selectedLot[userId]);
    final picked = await showSearchablePicker<Map<String, dynamic>>(
      context: context,
      title: tenant ? 'Which home are they renting?' : 'Assign an address',
      items: choices,
      selected: current ?? none,
      hintText: 'Search phase, block or lot...',
      emptyText: tenant
          ? 'No occupied home matches.'
          : 'No open lot matches. Taken lots are not shown.',
      labelOf: (l) => identical(l, none) ? '— No address —' : _lotLabel(l),
      subtitleOf: (l) {
        if (identical(l, none)) return 'Approve without a home';
        final owner = _conflictFor(userId, (l['id'] as num).toInt());
        return owner != null ? 'Owner: $owner' : 'Open';
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedLot[userId] =
        identical(picked, none) ? null : (picked['id'] as num).toInt());
  }

  /// The lot with this id, or null.
  Map<String, dynamic>? _lotById(int? id) {
    if (id == null) return null;
    for (final l in _lots) {
      if ((l['id'] as num).toInt() == id) return l;
    }
    return null;
  }

  /// Who else already holds this lot, ignoring the applicant themselves.
  String? _conflictFor(int userId, int? lotId) {
    if (lotId == null) return null;
    final owner = _lotOwners[lotId];
    if (owner == null || owner.isEmpty) return null;
    // Their own current lot is not a conflict.
    final pendingUser = _pending.firstWhere((u) => u['id'] == userId,
        orElse: () => const <String, dynamic>{});
    if ((pendingUser['lot_id'] as num?)?.toInt() == lotId) return null;
    return owner;
  }

  /// Approves (`active`) or rejects (`suspended`) an applicant. Approval
  /// first asks the officer to confirm missing proof, address or phase.
  Future<void> _decide(Map<String, dynamic> user, String newStatus) async {
    final id = user['id'] as int;

    // The officer may proceed past each warning, but is always told.
    if (newStatus == 'active') {
      final proof = user['ownership_proof_path'] as String?;
      if (proof == null || proof.isEmpty) {
        final go = await _confirm('No proof of ownership',
            '${user['first_name']} ${user['last_name']} has not uploaded a title, '
            'tax declaration or lease. Nothing on file ties them to the address '
            'they claimed.');
        if (go != true) return;
      }

      final lotId = _selectedLot[id];
      if (lotId == null) {
        final go = await _confirm('Approve without an address?',
            '${user['first_name']} ${user['last_name']} has no lot on record. '
            'They will be able to sign in, but nothing ties them to a home.');
        if (go != true) return;
      } else {
        final clash = _conflictFor(id, lotId);
        if (clash != null) {
          final go = await _confirm('That address is already taken',
              '${_lotLabel(_lotById(lotId)!)} is on record to $clash. '
              'Approving moves it to ${user['first_name']} ${user['last_name']}. '
              'Check the title or tax declaration before you do.');
          if (go != true) return;
        }
      }

      // An officer with no phase sees an empty system.
      if (_needsPhasePick(id) && (_selectedPhase[id] ?? '').isEmpty) {
        final go = await _confirm('No phase assigned',
            '${user['first_name']} ${user['last_name']} is being approved as '
            'an officer but has no phase. Officers only see the phase they '
            'belong to, so they will sign in to an empty system until one '
            'is set.');
        if (go != true) return;
      }
    }

    setState(() => _busy.add(id));
    try {
      final update = <String, dynamic>{'status': newStatus};
      if (newStatus == 'active') {
        final roleName = _selectedRole[id] ?? defaultSelfServiceRole;
        final roleId = _roleIds[roleName];
        if (roleId != null) update['role_id'] = roleId;
        // Approval grants the address: lot_id is set, the claim cleared.
        final lotId = _selectedLot[id];
        if (lotId != null) {
          update['lot_id'] = lotId;
          update['requested_lot_id'] = null;
        }
        // Send phase only without a lot; with a lot, a database trigger
        // sets it from the block and would overwrite this.
        final phase = _selectedPhase[id];
        if (phase != null && phase.isNotEmpty && lotId == null) {
          update['phase'] = phase;
        }
      }
      await SupabaseService.instance.client.from('users').update(update).eq('id', id);

      // No audit call needed: a database trigger records the update.

      if (!mounted) return;
      setState(() {
        _pending.removeWhere((u) => u['id'] == id);
        _busy.remove(id);
      });
      _reportCount();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newStatus == 'active'
            ? '${user['first_name']} approved as ${_roleLabel(_selectedRole[id] ?? defaultSelfServiceRole)}.'
            : '${user['first_name']} rejected.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed. ${friendlyError(e)}')));
    }
  }

  /// Warning dialog; true means the officer chose "Approve anyway".
  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: SizedBox(
              width: dialogContentWidth(context, 400),
              child: Text(body,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary, height: 1.45))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Approve anyway')),
          ],
        ),
      );

  /// Asks before rejecting, then marks the applicant suspended.
  Future<void> _confirmReject(Map<String, dynamic> user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject this application?'),
        content: Text(
            '${user['first_name']} ${user['last_name']} will be marked suspended and won\'t be able to sign in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok == true) _decide(user, 'suspended');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // The one-row card needs ~780px of fixed-width parts; below 980 the
      // name column gets squeezed, so use the stacked card.
      final narrow = c.maxWidth < 980;
      return Padding(
        padding: EdgeInsets.all(narrow ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${_pending.length} pending',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const Spacer(),
                IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh, size: 18)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _body(narrow)),
          ],
        ),
      );
    });
  }

  /// The list, or a loading, error or empty message.
  Widget _body(bool narrow) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text('Could not load approvals: $_error',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      );
    }
    if (_pending.isEmpty) {
      return const Center(
        child: Text('No pending applications right now.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      );
    }
    return ListView.separated(
      itemCount: _pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final u = _pending[i];
        return narrow ? _mobileCard(u) : _desktopCard(u);
      },
    );
  }

  /// True for officer roles, whose phase must be picked by hand.
  bool _needsPhasePick(int id) {
    final role = _selectedRole[id] ?? defaultSelfServiceRole;
    if (!officerRoles.contains(role)) return false;
    // super_admin spans all phases.
    return role != 'super_admin';
  }

  /// Phase picker, shown only for officer roles; a resident's phase comes
  /// from their lot.
  Widget _phaseDropdown(int id, bool busy) {
    if (_phases.isEmpty) {
      return const Text('No phases set up yet',
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Phase ',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        DropdownButton<String?>(
          // The value must be among the items; the list has one code per
          // phase number, so a stored '1B' would break it.
          value: _phases.any((p) => p['code'] == _selectedPhase[id])
              ? _selectedPhase[id]
              : null,
          hint: const Text('choose', style: TextStyle(fontSize: 12.5)),
          underline: const SizedBox.shrink(),
          isDense: true,
          style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
          items: [
            for (final p in _phases)
              DropdownMenuItem(
                value: p['code'] as String,
                child: Text((p['number'] ?? p['code']).toString()),
              ),
          ],
          onChanged: busy ? null : (v) => setState(() => _selectedPhase[id] = v),
        ),
      ],
    );
  }

  /// Role picker for one applicant.
  Widget _roleDropdown(int id, bool busy) {
    final current = _selectedRole[id] ?? defaultSelfServiceRole;
    // The current role stays listed even if this officer cannot assign it;
    // a value missing from the items breaks the dropdown.
    final roles = [
      ..._assignableRoles,
      if (!_assignableRoles.contains(current)) current,
    ];
    return DropdownButton<String>(
      value: current,
      underline: const SizedBox.shrink(),
      isDense: true,
      style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
      items: roles.map((r) => DropdownMenuItem(value: r, child: Text(_roleLabel(r)))).toList(),
      onChanged: busy ? null : (v) => setState(() => _selectedRole[id] = v!),
    );
  }

  /// The claimed address, coloured by whether anyone else already holds it,
  /// with a button to change it.
  Widget _addressBlock(Map<String, dynamic> u, bool busy, {required bool narrow}) {
    final id = u['id'] as int;
    final lotId = _selectedLot[id];
    final lot = _lotById(lotId);
    final clash = _conflictFor(id, lotId);
    final requested = u['requested_lot_id'] as int?;

    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String note;
    if (lot == null) {
      bg = AppColors.badgeAmberBg;
      fg = AppColors.badgeAmberText;
      icon = Icons.help_outline;
      note = 'No address claimed';
    } else if (clash != null) {
      bg = AppColors.badgeRedBg;
      fg = AppColors.badgeRedText;
      icon = Icons.warning_amber_rounded;
      note = 'Already on record to $clash';
    } else {
      bg = AppColors.badgeGreenBg;
      fg = AppColors.badgeGreenText;
      icon = Icons.home_outlined;
      note = requested != null && requested == lotId
          ? 'Claimed at signup · no other owner on record'
          : 'No other owner on record';
    }

    return Container(
      width: narrow ? double.infinity : 300,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(lot == null ? 'Address' : _lotLabel(lot),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(note,
              maxLines: 2,
              style: TextStyle(fontSize: 10.5, color: fg, height: 1.3)),
          if (lot?['street_address'] != null &&
              lot!['street_address'].toString().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(lot['street_address'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.85))),
          ],
          const SizedBox(height: 6),
          // Searchable picker: there are hundreds of lots.
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: busy ? null : () => _pickLot(id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  const Icon(Icons.search, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(lot == null ? 'Choose an address' : 'Change address',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textPrimary)),
                  ),
                  const Icon(Icons.arrow_drop_down,
                      size: 18, color: AppColors.textMuted),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Display names for the proof document types.
  static const _proofLabels = <String, String>{
    'title': 'Land title / TCT',
    'tax_declaration': 'Tax declaration',
    'deed_of_sale': 'Deed of sale',
    'lease_contract': 'Lease contract',
    'utility_bill': 'Utility bill',
    'other': 'Supporting document',
  };

  /// Opens the applicant's proof document (private file; needs users:read).
  Future<void> _viewProof(Map<String, dynamic> u) async {
    final path = u['ownership_proof_path'] as String?;
    if (path == null || path.isEmpty) return;
    try {
      await openStoredFile(context, path: path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the document. ${friendlyError(e)}')));
    }
  }

  /// Link to the proof document, or an amber warning when none was uploaded.
  Widget _proofChip(Map<String, dynamic> u) {
    final path = u['ownership_proof_path'] as String?;
    final has = path != null && path.isNotEmpty;
    if (!has) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: AppColors.badgeAmberBg, borderRadius: BorderRadius.circular(6)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.badgeAmberText),
          SizedBox(width: 5),
          Text('No proof of ownership',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.badgeAmberText)),
        ]),
      );
    }
    return TextButton.icon(
      onPressed: () => _viewProof(u),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        backgroundColor: AppColors.badgeGreenBg,
        foregroundColor: AppColors.badgeGreenText,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.description_outlined, size: 13),
      label: Text(
          _proofLabels[u['ownership_proof_type']] ?? 'View document',
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }

  /// Proof chip plus the phase the applicant is joining.
  Widget _chips(Map<String, dynamic> u) {
    final phase = _phaseOf(u);
    final fg = phase == null ? AppColors.badgeGrayText : AppColors.badgeBlueText;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      _proofChip(u),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: phase == null ? AppColors.badgeGrayBg : AppColors.badgeBlueBg,
            borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.map_outlined, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(phase == null ? 'No phase yet' : 'Phase $phase',
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
        ]),
      ),
    ]);
  }

  Widget _avatar(Map<String, dynamic> u) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.badgeAmberBg,
      child: Text(
        ((u['first_name'] ?? '?').toString().isNotEmpty ? u['first_name'][0] : '?').toString().toUpperCase(),
        style: const TextStyle(color: AppColors.badgeAmberText, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// One-row applicant card for wide screens.
  Widget _desktopCard(Map<String, dynamic> u) {
    final id = u['id'] as int;
    final busy = _busy.contains(u['id']);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _avatar(u),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${u['first_name'] ?? ''} ${u['last_name'] ?? ''}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('${u['email'] ?? ''} · ${u['phone'] ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                _chips(u),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _addressBlock(u, busy, narrow: false),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Role', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
              const SizedBox(height: 2),
              _roleDropdown(id, busy),
              // Officers only; see _needsPhasePick.
              if (_needsPhasePick(id)) ...[
                const SizedBox(height: 6),
                _phaseDropdown(id, busy),
              ],
            ],
          ),
          const SizedBox(width: 16),
          if (busy)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            OutlinedButton(
              onPressed: () => _confirmReject(u),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.badgeRedText),
              child: const Text('Reject'),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => _decide(u, 'active'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.sidebarActiveText),
              child: const Text('Approve'),
            ),
          ],
        ],
      ),
    );
  }

  /// Stacked applicant card for narrow screens.
  Widget _mobileCard(Map<String, dynamic> u) {
    final id = u['id'] as int;
    final busy = _busy.contains(u['id']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppColors.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(u),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${u['first_name'] ?? ''} ${u['last_name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text('${u['email'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _chips(u),
          const SizedBox(height: 10),
          _addressBlock(u, busy, narrow: true),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Role: ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              Expanded(child: _roleDropdown(id, busy)),
            ],
          ),
          if (_needsPhasePick(id))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _phaseDropdown(id, busy),
            ),
          const SizedBox(height: 10),
          if (busy)
            const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmReject(u),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.badgeRedText),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _decide(u, 'active'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.sidebarActiveText),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
