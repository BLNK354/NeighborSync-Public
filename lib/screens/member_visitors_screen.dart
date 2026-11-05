import '../core/content_moderation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/field_rules.dart';
import '../core/form_helpers.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../widgets/status_badge.dart';
import '../widgets/gate_pass_share_card.dart';
import '../core/refresh_bus.dart';
import '../core/tour_anchors.dart';
import '../core/safe_state.dart';

/// "My Visitors" page: shows the resident's active gate pass (QR code +
/// details) and a log of visitors who checked in at the gate under their
/// name. "New Gate Pass" requests a pass for a guest; security staff log
/// the actual gate check-in and check-out.
class MemberVisitorsScreen extends StatefulWidget {
  const MemberVisitorsScreen({super.key});

  @override
  State<MemberVisitorsScreen> createState() => _MemberVisitorsScreenState();
}

class _MemberVisitorsScreenState extends State<MemberVisitorsScreen> with SafeSetState<MemberVisitorsScreen> {
  // A resident can have several guests booked at once.
  List<Map<String, dynamic>> _activePasses = [];
  List<Map<String, dynamic>> _recentVisitors = [];
  bool _loading = true;
  String? _error;

  /// Resident's name for the "VISITING" line on the shareable picture.
  /// Blank until loaded. The address comes from each pass, not the profile.
  String _myName = '';

  /// The pass whose picture is being saved, so its button can show a spinner.
  Object? _savingPassId;

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
      if (myId == null) {
        setState(() {
          _loading = false;
          _error = 'Could not resolve your account.';
        });
        return;
      }
      final c = SupabaseService.instance.client;
      final now = DateTime.now().toUtc().toIso8601String();
      final results = await Future.wait<dynamic>([
        c
            .from('gate_passes')
            // The pass's own lot is where the visitor goes; it may differ
            // from the host's address. lots(...) has one FK, so it is safe;
            // a users embed here would need its FK column named.
            .select('*, lots(lot_number, blocks(block_name))')
            // Include pending so a new pass shows right away.
            .eq('requested_by', myId)
            .inFilter('status', const ['approved', 'pending'])
            .gte('valid_until', now)
            // Newest first.
            .order('created_at', ascending: false)
            .limit(20),
        c
            .from('visitor_logs')
            .select('*')
            .eq('host_user_id', myId)
            .order('time_in', ascending: false)
            .limit(10),
      ]);
      if (!mounted) return;
      final passes = List<Map<String, dynamic>>.from(results[0] as List);
      setState(() {
        _activePasses = passes;
        _recentVisitors = List<Map<String, dynamic>>.from(results[1] as List);
        _loading = false;
      });
      // Separate from the Future.wait above, so a failure here cannot block
      // the pass list.
      unawaited(_loadMyIdentity());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  /// Loads the resident's name for the shareable picture. Failures are
  /// ignored because nothing on screen depends on it.
  Future<void> _loadMyIdentity() async {
    try {
      final profile = await SupabaseService.instance.getMyProfile();
      if (profile == null) return;
      final name = [profile['first_name'], profile['last_name']]
          .map((v) => (v ?? '').toString().trim())
          .where((v) => v.isNotEmpty)
          .join(' ');
      if (!mounted) return;
      setState(() => _myName = name);
    } catch (_) {
      // Intentionally silent.
    }
  }

  /// "Block A · Lot 12" for the address ON THE PASS. Empty when the embed
  /// came back without one, so the caller can drop the line.
  String _passAddress(Map<String, dynamic> p) {
    final lot = p['lots'] as Map<String, dynamic>?;
    if (lot == null) return '';
    final block = (lot['blocks'] as Map<String, dynamic>?)?['block_name'];
    final number = lot['lot_number'];
    if (block == null && number == null) return '';
    return 'Block ${block ?? '—'} · Lot ${number ?? '—'}';
  }

  /// Saves one pass as a picture and shows the result in a snackbar.
  Future<void> _savePassImage(Map<String, dynamic> p) async {
    setState(() => _savingPassId = p['id']);
    final problem = await saveGatePassImage(
      context,
      p,
      hostName: _myName,
      hostAddress: _passAddress(p),
    );
    if (!mounted) return;
    setState(() => _savingPassId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(problem ??
            'Gate pass saved as a picture. Send it to your visitor — the guard scans it at the gate.'),
        backgroundColor: problem == null ? null : Colors.redAccent,
      ),
    );
  }

  // Keep toLocal(): stored times are UTC and would otherwise show 8 hours off.
  String _time(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '—';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final period = t.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
  }

  String _date(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '—';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[t.month - 1]} ${t.day}';
  }

  String _visitorStatus(Map<String, dynamic> v) => v['time_out'] != null ? 'checked_out' : 'inside';

  /// Opens the New Gate Pass form, then reloads the list.
  Future<void> _openRegisterForm() async {
    await context.push('/me/visitors/new');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'My Visitors',
      activeItem: 'My Visitors',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('My visitor passes',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                          ),
                          TourAnchor(id: TourAnchorId.registerVisitor, child: FilledButton(onPressed: _openRegisterForm, child: const Text('New Gate Pass'))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Passes run across the page, with history underneath.
                      _activePassSection(),
                      const SizedBox(height: 24),
                      _recentVisitorsCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _activePassSection() {
    if (_activePasses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: ResidentColors.cardShadow),
        child: Column(
          children: [
            const Icon(Icons.qr_code_2, size: 34, color: ResidentColors.textSecondary),
            const SizedBox(height: 12),
            const Text('No active gate pass right now',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
            const SizedBox(height: 6),
            const Text('Request a gate pass for your visitor and a pass with a QR code is created for them.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: ResidentColors.textSecondary)),
            const SizedBox(height: 16),
            TourAnchor(id: TourAnchorId.registerVisitor, child: OutlinedButton(onPressed: _openRegisterForm, child: const Text('New Gate Pass'))),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _activePasses.length > 1
              ? 'Active gate passes (${_activePasses.length})'
              : 'Active gate pass',
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          gatePassImageSupported
              ? 'Save a pass as a picture and send it to your guest before they arrive.'
              : 'Show the QR code at the guardhouse when your guest arrives.',
          style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            // A ticket needs about 300px, so columns follow the available
            // width, not the screen size (the sidebar takes part of it).
            const gap = 16.0;
            final columns = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 660 ? 2 : 1);
            // Keep floorToDouble: a fraction of a pixel over maxWidth makes
            // Wrap stack the tickets in one column.
            final width = ((c.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final p in _activePasses) SizedBox(width: width, child: _passTicket(p)),
              ],
            );
          },
        ),
      ],
    );
  }

  /// One gate pass as a ticket: visitor on top, QR code in the middle,
  /// details below.
  /// The QR must encode `qr_token`, not `pass_number`: pass numbers are
  /// sequential, so anyone could guess a valid-looking code.
  Widget _passTicket(Map<String, dynamic> p) {
    final status = (p['status'] ?? '').toString();
    final token = (p['qr_token'] ?? '').toString();
    final purpose = (p['purpose'] ?? '').toString().trim();
    final plate = (p['vehicle_plate'] ?? '').toString().trim();
    final address = _passAddress(p);
    final saving = _savingPassId != null && _savingPassId == p['id'];

    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: ResidentColors.cardShadow),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The visitor's name comes first: the guard checks the guest against it.
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((p['visitor_name'] ?? '—').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700, color: ResidentColors.textPrimary)),
                      if (purpose.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(purpose,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (status.isNotEmpty) StatusBadge(status),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ResidentColors.border),
              ),
              child: token.isEmpty
                  // Fallback for a pass with no token.
                  ? const SizedBox(
                      width: 148,
                      height: 148,
                      child: Center(
                        child: Text('QR unavailable\nfor this pass',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
                      ),
                    )
                  : QrImageView(
                      data: token,
                      version: QrVersions.auto,
                      size: 148,
                      backgroundColor: Colors.white,
                      // Keep this margin: many scanners cannot read a code
                      // flush to the border.
                      padding: const EdgeInsets.all(6),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text('${p['pass_number'] ?? p['id']}',
                style: const TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w600,
                    color: ResidentColors.textSecondary)),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 1, color: ResidentColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metaLine(Icons.event_outlined,
                    'Valid until ${_date(p['valid_until']?.toString())}, ${_time(p['valid_until']?.toString())}'),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _metaLine(Icons.home_outlined, address),
                ],
                if (plate.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _metaLine(Icons.directions_car_outlined, plate),
                ],
                if (gatePassImageSupported) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      // Disabled while saving to block a double tap.
                      onPressed: saving ? null : () => _savePassImage(p),
                      icon: saving
                          ? const SizedBox(
                              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_outlined, size: 16),
                      label: Text(saving ? 'Saving…' : 'Save as picture'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: ResidentColors.textSecondary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _recentVisitorsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: ResidentColors.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent visitors',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
          const SizedBox(height: 2),
          const Text('Logged at the guardhouse when someone arrives under your name.',
              style: TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
          const SizedBox(height: 14),
          if (_recentVisitors.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No visitors logged at the gate yet.',
                  style: TextStyle(fontSize: 12.5, color: ResidentColors.textSecondary)),
            )
          else
            LayoutBuilder(builder: (context, c) {
              // Rows stack on narrow widths, where four columns would cut off text.
              final narrow = c.maxWidth < 560;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Headers appear only in the column layout.
                  if (!narrow) ...[
                    _visitorHeader(),
                    const Divider(height: 1, thickness: 1, color: ResidentColors.border),
                  ],
                  for (final v in _recentVisitors) _visitorRow(v, narrow),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _visitorHeader() {
    const s = TextStyle(
        fontSize: 10, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: ResidentColors.textSecondary);
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('VISITOR', style: s)),
          Expanded(flex: 3, child: Text('PURPOSE', style: s)),
          Expanded(flex: 2, child: Text('ARRIVED', style: s)),
          SizedBox(width: 92, child: Text('STATUS', style: s)),
        ],
      ),
    );
  }

  Widget _visitorRow(Map<String, dynamic> v, bool narrow) {
    final name = (v['visitor_name'] ?? '—').toString();
    final purpose = (v['purpose'] ?? '—').toString();
    final when = _date(v['time_in']?.toString());

    if (narrow) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: ResidentColors.border))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('$purpose · $when',
                      style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(_visitorStatus(v)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: ResidentColors.border))),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(name,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500, color: ResidentColors.textPrimary)),
          ),
          Expanded(
              flex: 3,
              child: Text(purpose, style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary))),
          Expanded(
              flex: 2,
              child: Text(when, style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary))),
          SizedBox(width: 92, child: Align(alignment: Alignment.centerLeft, child: StatusBadge(_visitorStatus(v)))),
        ],
      ),
    );
  }
}

/// "New Gate Pass" form. Submitting creates a pending gate pass valid for
/// the rest of the selected day.
class MemberRegisterVisitorScreen extends StatefulWidget {
  const MemberRegisterVisitorScreen({super.key});

  @override
  State<MemberRegisterVisitorScreen> createState() => _MemberRegisterVisitorScreenState();
}

class _MemberRegisterVisitorScreenState extends State<MemberRegisterVisitorScreen> with SafeSetState<MemberRegisterVisitorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  DateTime _visitDate = DateTime.now();
  TimeOfDay _expectedTime = TimeOfDay.now();

  /// The resident's own approved lot, used for the pass. Null when they have
  /// no verified address; the pass is then not tied to a lot.
  int? _myLotId;
  String _myAddressLabel = '';
  bool _loadingProfile = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _loadMyAddress);
    _loadMyAddress();
  }

  Future<void> _loadMyAddress() async {
    try {
      final profile = await SupabaseService.instance.getMyProfile();
      final lotId = profile?['lot_id'] as int?;
      String label = '';
      if (lotId != null) {
        final lot = await SupabaseService.instance.client
            .from('lots')
            .select('lot_number, blocks(block_name)')
            .eq('id', lotId)
            .maybeSingle();
        final block = (lot?['blocks'] as Map<String, dynamic>?)?['block_name'] ?? '—';
        label = 'Block $block · Lot ${lot?['lot_number'] ?? ''}';
      }
      if (!mounted) return;
      setState(() {
        _myLotId = lotId;
        _myAddressLabel = label;
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _purposeCtrl.dispose();
    _plateCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    // Checked by the integrated AI first (content_moderation.dart).
    final problem = await moderationProblem([_nameCtrl.text, _purposeCtrl.text]);
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _saving = false;
        _error = problem;
      });
      return;
    }
    try {
      final myId = await SupabaseService.instance.getMyUserId();
      final validFrom = DateTime(_visitDate.year, _visitDate.month, _visitDate.day, _expectedTime.hour, _expectedTime.minute);
      // Pass stays valid until the end of the selected day.
      final validUntil = DateTime(_visitDate.year, _visitDate.month, _visitDate.day, 23, 59);
      await SupabaseService.instance.client.from('gate_passes').insert({
        // pass_number is left out: a database trigger assigns it.
        'requested_by': myId,
        if (_myLotId != null) 'lot_id': _myLotId,
        'visitor_name': _nameCtrl.text.trim(),
        'purpose': _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
        'vehicle_plate': _plateCtrl.text.trim().isEmpty ? null : _plateCtrl.text.trim().toUpperCase(),
        'visitor_contact': _contactCtrl.text.trim(),
        // Keep .toUtc(): a local time has no offset, so Postgres would read it as UTC.
        'valid_from': validFrom.toUtc().toIso8601String(),
        'valid_until': validUntil.toUtc().toIso8601String(),
        // No status is sent: the database makes a resident's new pass pending.
      });
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = 'Could not register visitor. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'New Gate Pass',
      activeItem: 'My Visitors',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  inputFormatters: nameInputFormatters,
                  decoration: const InputDecoration(labelText: 'Visitor Name'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : nameRule(v, const {}),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _purposeCtrl, decoration: const InputDecoration(labelText: 'Purpose / notes (optional)')),
                const SizedBox(height: 12),
                // Same rules as the officer form.
                TextFormField(
                  controller: _contactCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: phoneInputFormatters,
                  decoration: const InputDecoration(
                      labelText: 'Visitor Contact Number', hintText: '09XXXXXXXXX'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : phoneRule(v, const {}),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _plateCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: kPlateMaxLength,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(kPlateAllowedChars))],
                  decoration: const InputDecoration(
                      labelText: 'Vehicle Plate (optional)', hintText: 'e.g. ABC 1234', counterText: ''),
                  validator: (v) => plateRule(v, const {}),
                ),
                const SizedBox(height: 12),
                // Read-only: always the resident's own verified address.
                _loadingProfile
                    ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
                    : InputDecorator(
                        decoration: const InputDecoration(labelText: 'Visiting'),
                        child: Row(
                          children: [
                            const Icon(Icons.home_outlined, size: 16, color: ResidentColors.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _myLotId != null
                                    ? '$_myAddressLabel (your address)'
                                    : 'Your account — no verified address yet',
                                style: const TextStyle(fontSize: 13.5, color: ResidentColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _visitDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 1)),
                            lastDate: DateTime.now().add(const Duration(days: 90)),
                          );
                          if (picked != null) setState(() => _visitDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Visit Date'),
                          child: Text('${_visitDate.month}/${_visitDate.day}/${_visitDate.year}'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(context: context, initialTime: _expectedTime);
                          if (picked != null) setState(() => _expectedTime = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Expected Time'),
                          child: Text(_expectedTime.format(context)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Must stay true to the database: a resident's pass starts as pending.
                const Text('Your pass goes to the guardhouse for approval, then covers the rest of the selected day.',
                    style: TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving || _loadingProfile ? null : _submit,
                    child: Text(_saving ? 'Sending...' : 'Request Gate Pass'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(onPressed: _saving ? null : () => context.pop(), child: const Text('Cancel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
