import '../core/content_moderation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import 'package:go_router/go_router.dart';
import '../core/evidence_upload.dart';
import '../core/module_registry.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/payment_proof_actions.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/tour_anchors.dart';
import '../core/safe_state.dart';
import '../core/stored_file.dart';

// Complaint categories. Keep in step with the officers' form and
// concern_routing.dart.
const _categories = ['noise', 'maintenance', 'billing', 'security', 'parking', 'neighbor_dispute', 'pets', 'sanitation', 'common_area', 'other'];

/// "My Complaints" list. Tap "File a Complaint" to open the form; only
/// shows complaints the current resident filed themselves.
class MemberComplaintsScreen extends StatefulWidget {
  const MemberComplaintsScreen({super.key});

  @override
  State<MemberComplaintsScreen> createState() => _MemberComplaintsScreenState();
}

class _MemberComplaintsScreenState extends State<MemberComplaintsScreen> with SafeSetState<MemberComplaintsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads the signed-in resident's own complaints, newest first.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final myId = await SupabaseService.instance.getMyUserId();
      final data = await SupabaseService.instance.client
          .from('complaints')
          .select('*')
          .eq('complainant_id', myId as Object)
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
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

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'My Complaints',
      activeItem: 'My Complaints',
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
                            child: Text('My complaints',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                          ),
                          TourAnchor(
                            id: TourAnchorId.fileComplaint,
                            child: FilledButton(
                              onPressed: () async {
                                await context.push('/me/complaints/new');
                                _load();
                              },
                              child: const Text('File a Complaint'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: ResidentColors.cardShadow),
                        child: _rows.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('No complaints filed yet.', style: TextStyle(fontSize: 12.5, color: ResidentColors.textSecondary)),
                              )
                            : Column(children: [for (final r in _rows) _row(r)]),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// One complaint in the list; tap to open its details.
  Widget _row(Map<String, dynamic> r) {
    return InkWell(
      onTap: () => _showDetail(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: ResidentColors.border))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((r['subject'] ?? '—').toString(),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                  const SizedBox(height: 3),
                  // A draft has no reference number until it is sent.
                  Text('${_refLabel(r)} · ${titleCase((r['category'] ?? '').toString())}',
                      style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
                ],
              ),
            ),
            StatusBadge((r['status'] ?? '').toString()),
          ],
        ),
      ),
    );
  }

  /// Shows one complaint like the paper form, with a "FOR HOA" section
  /// (date received, actions taken) filled from the record.
  void _showDetail(Map<String, dynamic> r) {
    String d(String? iso) => (iso ?? '').split('T').first;
    // Editing is allowed only while the complaint is still 'submitted'.
    // The database enforces the same rule; this just explains it.
    final isDraft = (r['status'] ?? '').toString() == 'draft';
    final editable = (r['status'] ?? '').toString() == 'submitted';
    final files = <Map<String, dynamic>>[
      if (r['attachments'] is List)
        for (final e in r['attachments'] as List)
          if (e is Map) Map<String, dynamic>.from(e),
    ];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Complaint / Concern · ${_refLabel(r)}'),
        content: SizedBox(
          width: dialogContentWidth(context, 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Nature of Complaint', (r['subject'] ?? '—').toString()),
                _detailRow('Category', titleCase((r['category'] ?? '—').toString())),
                if ((r['location'] ?? '').toString().isNotEmpty)
                  _detailRow('Where', (r['location']).toString()),
                _detailRow('Details', (r['description'] ?? '—').toString()),
                if (r['incident_date'] != null)
                  _detailRow('Date of Incident', d(r['incident_date']?.toString())),
                if (files.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          width: 120,
                          child: Text('Evidence',
                              style: TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final a in files)
                                InkWell(
                                  onTap: () => viewPaymentReceipt(
                                      context, (a['path'] ?? '').toString()),
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.attach_file,
                                            size: 13, color: ResidentColors.textSecondary),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text((a['name'] ?? 'file').toString(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  decoration: TextDecoration.underline,
                                                  color: ResidentColors.textPrimary)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1),
                ),
                const Text('FOR HOA',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: ResidentColors.textPrimary)),
                const SizedBox(height: 8),
                _detailRow('Date Received', d(r['created_at']?.toString())),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 120,
                        child: Text('Status',
                            style: TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
                      ),
                      StatusBadge((r['status'] ?? '').toString()),
                    ],
                  ),
                ),
                if (isDraft)
                  const Padding(
                    padding: EdgeInsets.only(left: 120, bottom: 6),
                    child: Text(
                      'Not sent yet. Only you can see this draft.',
                      style: TextStyle(fontSize: 11, color: ResidentColors.textSecondary),
                    ),
                  )
                else if (!editable)
                  // Explains why there is no Edit button.
                  const Padding(
                    padding: EdgeInsets.only(left: 120, bottom: 6),
                    child: Text(
                      'An officer is handling this, so it can no longer be edited.',
                      style: TextStyle(fontSize: 11, color: ResidentColors.textSecondary),
                    ),
                  ),
                _detailRow(
                    'Actions Taken',
                    (r['resolution'] ?? '').toString().trim().isEmpty
                        ? 'No actions recorded yet.'
                        : (r['resolution']).toString()),
                if (r['resolved_at'] != null)
                  _detailRow('Date Resolved', d(r['resolved_at']?.toString())),
              ],
            ),
          ),
        ),
        actions: [
          if (isDraft) ...[
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _deleteDraft(r);
              },
              child: const Text('Delete draft', style: TextStyle(color: Color(0xFFC62828))),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await context.push('/me/complaints/new', extra: r);
                _load();
              },
              child: const Text('Continue & send'),
            ),
          ],
          if (editable)
            // Same form officers use; office-only fields (category,
            // priority, status, assignment, resolution) show read-only.
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final saved =
                    await showModuleFormDialog(context, complaints, initial: r);
                if (saved == true) _load();
              },
              child: const Text('Edit'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Asks for confirmation, then deletes an unsent draft.
  Future<void> _deleteDraft(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text('It has not been sent, so nobody else has seen it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.instance.client.from('complaints').delete().eq('id', r['id'] as Object);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete. ${friendlyError(e)}')));
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500, color: ResidentColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// The "File a Complaint / Concern" form, modelled on the HOA's paper form.
/// Complainant details come from the signed-in account. Subject and details
/// map to subject + description. A required checkbox stands in for the
/// signature. Priority is not asked; the classifier sets it and officers can
/// override it.
class MemberFileComplaintScreen extends StatefulWidget {
  /// A saved draft to continue editing, or null for a new complaint.
  final Map<String, dynamic>? draft;
  const MemberFileComplaintScreen({super.key, this.draft});

  @override
  State<MemberFileComplaintScreen> createState() => _MemberFileComplaintScreenState();
}

class _MemberFileComplaintScreenState extends State<MemberFileComplaintScreen> with SafeSetState<MemberFileComplaintScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = _categories.first;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? _profile;
  String? _roleName;
  final _locationCtrl = TextEditingController();
  /// Who the complaint is about. Optional free text, since it may be a
  /// visitor or a house, not an account.
  final _againstCtrl = TextEditingController();
  DateTime? _incidentDate;
  bool _certified = false;
  String? _officialFormUrl;

  /// Evidence files, uploaded as they are picked and saved to the
  /// `attachments` column on submit. Shares its storage folder and policies
  /// with the officer form (see pickAndUploadEvidence).
  final List<Map<String, dynamic>> _evidence = [];
  bool _uploading = false;

  /// Set when continuing a saved draft: saving updates that row instead
  /// of creating a second one.
  dynamic _draftId;

  /// Categories where a complaint is usually about someone. Billing and
  /// maintenance are about the office or a fixture, so the box is hidden.
  bool get _againstApplies => const {
        'noise', 'neighbor_dispute', 'pets', 'parking', 'sanitation', 'security', 'other'
      }.contains(_category);

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    if (d != null) {
      _draftId = d['id'];
      _subjectCtrl.text = (d['subject'] ?? '').toString();
      _descCtrl.text = (d['description'] ?? '').toString();
      _locationCtrl.text = (d['location'] ?? '').toString();
      _againstCtrl.text = (d['against_text'] ?? '').toString();
      final cat = (d['category'] ?? '').toString();
      if (_categories.contains(cat)) _category = cat;
      _incidentDate = DateTime.tryParse((d['incident_date'] ?? '').toString());
      if (d['attachments'] is List) {
        for (final e in d['attachments'] as List) {
          if (e is Map) _evidence.add(Map<String, dynamic>.from(e));
        }
      }
    }
    RefreshBus.bind(this, _loadContext);
    _loadContext();
  }

  /// Loads the resident's profile, role and the official form link.
  Future<void> _loadContext() async {
    try {
      final results = await Future.wait<dynamic>([
        SupabaseService.instance.getMyProfile(),
        SupabaseService.instance.getMyRole(),
        SupabaseService.instance.client
            .from('system_settings')
            .select('value')
            .eq('setting_key', 'forms.complaint_form_url')
            .maybeSingle(),
      ]);
      if (!mounted) return;
      final formRow = results[2] as Map<String, dynamic>?;
      final formUrl = formRow?['value'] as String?;
      setState(() {
        _profile = results[0] as Map<String, dynamic>?;
        _roleName = results[1] as String?;
        _officialFormUrl = (formUrl == null || formUrl.isEmpty) ? null : formUrl;
      });
    } catch (_) {
      // Complainant header falls back to generic text; the form still works.
    }
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _againstCtrl.dispose();
    super.dispose();
  }

  String get _complainantName {
    final p = _profile;
    if (p == null) return 'Your account';
    return [p['first_name'], p['last_name']]
        .where((s) => s != null && s.toString().isNotEmpty)
        .join(' ');
  }

  /// Homeowner, Renter or Others, worked out from the account's role.
  String get _residentType => switch (_roleName) {
        'member_resident' => 'Homeowner',
        'tenant' => 'Renter',
        null => '—',
        _ => 'Others',
      };

  // Asks the classifier to suggest a category and priority. Errors are
  // ignored on purpose: this must never fail a send.
  Future<void> _classifyInBackground(dynamic complaintId) async {
    try {
      await SupabaseService.instance.client.functions
          .invoke('classify-complaint', body: {'complaint_id': complaintId});
    } catch (_) {
      // Ignored on purpose.
    }
  }

  /// Saves the complaint. [send] false keeps it as a private draft the
  /// resident can come back to; true asks for confirmation, sends it to
  /// the office and then confirms it was sent with its reference number.
  Future<void> _save({required bool send}) async {
    if (send) {
      if (!_formKey.currentState!.validate()) return;
      if (!_certified) {
        setState(() => _error = 'Please tick the certification box before sending.');
        return;
      }
    } else if (_subjectCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Give the draft a subject so you can find it later.');
      return;
    }
    // Text is checked for offensive language first (content_moderation.dart).
    setState(() {
      _saving = true;
      _error = null;
    });
    final problem = await moderationProblem(
        [_subjectCtrl.text, _descCtrl.text, _locationCtrl.text, _againstCtrl.text]);
    if (!mounted) return;
    setState(() => _saving = false);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (send) {
      final ok = await _confirmSend();
      if (ok != true) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = SupabaseService.instance.client;
      // complaint_number is left out; a database trigger assigns it.
      final payload = <String, dynamic>{
        'category': _category,
        'subject': _subjectCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'location': _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        'against_text': _againstApplies && _againstCtrl.text.trim().isNotEmpty
            ? _againstCtrl.text.trim()
            : null,
        'incident_date': _incidentDate?.toIso8601String().split('T').first,
        'attachments': _evidence,
        'status': send ? 'submitted' : 'draft',
      };
      final Map<String, dynamic> row;
      if (_draftId == null) {
        final myId = await SupabaseService.instance.getMyUserId();
        row = await client
            .from('complaints')
            .insert({'complainant_id': myId, ...payload})
            .select('id, complaint_number')
            .single();
      } else {
        row = await client
            .from('complaints')
            .update(payload)
            .eq('id', _draftId as Object)
            .select('id, complaint_number')
            .single();
      }
      _draftId = row['id'];
      if (!mounted) return;
      if (send) {
        // Fire and forget; the send must not wait on the classifier.
        unawaited(_classifyInBackground(row['id']));
        await _showSent((row['complaint_number'] ?? '').toString());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Saved as a draft. Open it from My Complaints to finish and send it.')));
      }
      if (!mounted) return;
      // After a direct link or refresh there is nothing to pop, so go to the list.
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/me/complaints');
      }
    } catch (e) {
      setState(() => _error =
          '${send ? 'Could not send the complaint.' : 'Could not save the draft.'} ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Last look before it goes to the office.
  Future<bool?> _confirmSend() {
    final desc = _descCtrl.text.trim();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send this complaint?'),
        content: SizedBox(
          width: dialogContentWidth(ctx, 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_subjectCtrl.text.trim(),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
              const SizedBox(height: 4),
              Text(titleCase(_category),
                  style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
              const SizedBox(height: 10),
              Text(desc.length > 220 ? '${desc.substring(0, 220)}...' : desc,
                  style: const TextStyle(fontSize: 12.5, color: ResidentColors.textPrimary, height: 1.4)),
              if (_evidence.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${_evidence.length} file(s) attached',
                    style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
              ],
              const SizedBox(height: 14),
              const Text(
                'Once sent, the HOA office is notified. You can still correct it '
                'until an officer starts handling it.',
                style: TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
  }

  /// Confirms it actually went, with the number to quote at the office.
  Future<void> _showSent(String reference) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 40),
        title: const Text('Complaint sent'),
        content: Text(
          reference.isEmpty
              ? 'The HOA office has received your complaint. You can follow it in My Complaints.'
              : 'The HOA office has received your complaint.\n\nReference No. $reference\n\n'
                  'Quote this number if you contact the office. You can follow it in My Complaints.',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  /// Uploads a file as soon as it is picked. It is stored under the
  /// uploader's id (the storage policy checks that), since the complaint
  /// does not exist yet. An abandoned upload just stays in the private bucket.
  Future<void> _attachEvidence() async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final myId = await SupabaseService.instance.getMyUserId();
      if (myId == null) return;
      final added =
          await pickAndUploadEvidence(folder: 'complaints', userId: myId);
      if (added == null || !mounted) return;
      setState(() => _evidence.add(added));
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not attach the file. ${friendlyError(e)}');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Opens a date picker; future dates are not allowed.
  Future<void> _pickIncidentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _incidentDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _incidentDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'File a Complaint / Concern',
      activeItem: 'My Complaints',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_officialFormUrl != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () =>
                          openStoredFile(context, publicUrl: _officialFormUrl)
                              .catchError((_) {}),
                      icon: const Icon(Icons.description_outlined, size: 15),
                      label: const Text('View official printed form'),
                    ),
                  ),
                _complainantCard(),
                const SizedBox(height: 18),
                _sectionLabel('Where'),
                const SizedBox(height: 8),
                // Free text, since complaints often happen at shared places.
                TextFormField(
                  controller: _locationCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Where did it happen? (optional)',
                      hintText: 'e.g. near the gym, basketball court, Block 5 street'),
                ),
                const SizedBox(height: 18),
                _sectionLabel('Nature of Complaint / Concern'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(titleCase(c)))],
                  onChanged: (v) => setState(() => _category = v ?? _categories.first),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _subjectCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nature of Complaint / Concern',
                      hintText: 'Short summary, e.g. "Loud karaoke past midnight"'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 6,
                  maxLength: kMaxTextLength,
                  decoration: const InputDecoration(labelText: 'Details', hintText: 'Describe what happened...'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                if (_againstApplies) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _againstCtrl,
                    maxLength: kMaxTextLength,
                    decoration: const InputDecoration(
                        labelText: 'Against (optional)',
                        hintText: 'Who is this about? e.g. "the household at Block 5 Lot 3"'),
                  ),
                ],
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickIncidentDate,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date of Incident (optional)'),
                    child: Text(
                      _incidentDate == null
                          ? 'Tap to select'
                          : _incidentDate!.toIso8601String().split('T').first,
                      style: TextStyle(
                          fontSize: 14,
                          color: _incidentDate == null
                              ? ResidentColors.textSecondary
                              : ResidentColors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _sectionLabel('Evidence (optional)'),
                const SizedBox(height: 4),
                const Text(
                  'Attach a photo or file if you have one. Only you and the '
                  'HOA officers handling this complaint can open it.',
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: ResidentColors.textSecondary),
                ),
                const SizedBox(height: 8),
                for (final a in _evidence)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: ResidentColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_file, size: 15, color: ResidentColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text((a['name'] ?? 'file').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: ResidentColors.textPrimary)),
                        ),
                        TextButton(
                          // The bucket is private, so open via a signed link.
                          onPressed: () => viewPaymentReceipt(context, (a['path'] ?? '').toString()),
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero),
                          child: const Text('Open', style: TextStyle(fontSize: 12)),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          iconSize: 16,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close),
                          // Removes the reference only; the stored file stays.
                          onPressed: () => setState(() => _evidence.remove(a)),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _uploading ? null : _attachEvidence,
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: Text(_uploading ? 'Uploading…' : 'Attach a photo or file',
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(height: 20),
                // Certification checkbox; the account name and send date
                // stand in for a signature.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: ResidentColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _certified,
                            onChanged: (v) => setState(() => _certified = v ?? false),
                          ),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'I hereby certify that the information provided is complete, '
                                'true and correct. I have completed this report for this '
                                'complaint/concern to be investigated, and I would be available '
                                'in case my presence is needed for further investigation/action.',
                                style: TextStyle(fontSize: 12, height: 1.5, color: ResidentColors.textPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Submitting electronically records your name ($_complainantName) '
                        'and today\'s date in place of a signature.',
                        style: const TextStyle(fontSize: 11, color: ResidentColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(send: true),
                    child: Text(_saving ? 'Saving...' : 'Send Complaint / Concern'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _save(send: false),
                    child: const Text('Save as Draft'),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => context.canPop() ? context.pop() : context.go('/me/complaints'),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary));

  /// Name, contact number and resident type, filled from the account.
  Widget _complainantCard() {
    final phone = (_profile?['phone'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: ResidentColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Complainant Information',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
          const SizedBox(height: 10),
          _infoRow('Name', _complainantName),
          _infoRow('Contact No.', phone.isEmpty ? 'Not set on your profile' : phone),
          _infoRow('Resident Type', _residentType),
          const SizedBox(height: 6),
          const Text('Auto-filled from your account -- update your profile if anything is wrong.',
              style: TextStyle(fontSize: 11, color: ResidentColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500, color: ResidentColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// The reference number to show for a complaint. A draft has none until
/// it is sent, so it reads "Draft".
String _refLabel(Map<String, dynamic> r) {
  final n = (r['complaint_number'] ?? '').toString().trim();
  if (n.isNotEmpty) return n;
  return r['status'] == 'draft' ? 'Draft' : '—';
}
