import 'package:flutter/material.dart';
import '../core/concern_routing.dart';
import '../core/form_helpers.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/responsive_officer_shell.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/dialog_controllers.dart';
import '../core/safe_state.dart';

/// "Assigned to Me": concerns assigned to the current officer. They can read
/// each one and submit a report (what was done) plus a status change.
class AssignedConcernsScreen extends StatefulWidget {
  const AssignedConcernsScreen({super.key});

  @override
  State<AssignedConcernsScreen> createState() => _AssignedConcernsScreenState();
}

class _AssignedConcernsScreenState extends State<AssignedConcernsScreen> with SafeSetState<AssignedConcernsScreen> {
  static const _statuses = ['in_progress', 'resolved', 'dismissed'];

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  /// This officer's role, used to flag concerns that belong to a different role.
  String? _myRole;

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
      if (myId == null) throw Exception('Could not resolve your account.');
      final role = await SupabaseService.instance.getMyRole();
      final data = await SupabaseService.instance.client
          .from('complaints')
          .select('id, complaint_number, subject, description, category, location, '
              'priority, status, resolution, resolved_at, created_at')
          .eq('assigned_to', myId)
          .order('created_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _myRole = role;
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

  /// True when this concern's category is not this officer's responsibility.
  bool _outOfScope(Map<String, dynamic> c) =>
      !roleHandlesConcern(_myRole, c['category']?.toString());

  int get _outOfScopeCount => _rows.where(_outOfScope).length;

  int get _open => _rows.where((r) => r['status'] != 'resolved' && r['status'] != 'dismissed').length;

  /// Opens the report dialog and saves the write-up and new status.
  Future<void> _report(Map<String, dynamic> c) async {
    final resolutionCtrl = TextEditingController(text: (c['resolution'] ?? '').toString());
    String status = (c['status'] ?? 'in_progress').toString();
    if (!_statuses.contains(status)) status = 'in_progress';
    // The database refuses closing without a resolution, so check it here first.
    String? resolutionError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Report — ${(c['subject'] ?? 'Concern').toString()}'),
          content: SizedBox(
            width: dialogContentWidth(context, 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((c['description'] ?? '').toString().isNotEmpty) ...[
                    const Text('Concern', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text((c['description'] ?? '').toString(),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                  ],
                  const Text('What did you do? (report / result)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: resolutionCtrl,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: kMaxTextLength,
                    onChanged: (_) {
                      if (resolutionError != null) setLocal(() => resolutionError = null);
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: 'Describe the action taken and the outcome…',
                      errorText: resolutionError,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: [
                      for (final s in _statuses)
                        DropdownMenuItem(value: s, child: Text(titleCase(s.replaceAll('_', ' ')))),
                    ],
                    onChanged: (v) => setLocal(() => status = v ?? status),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final closing = status == 'resolved' || status == 'dismissed';
                if (closing && resolutionCtrl.text.trim().isEmpty) {
                  setLocal(() => resolutionError =
                      'Write what was done before marking it ${titleCase(status)}.');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
    final resolutionText = resolutionCtrl.text.trim();
    disposeAfterDialogCloses([resolutionCtrl]);
    if (saved != true) return;

    try {
      await SupabaseService.instance.client.from('complaints').update({
        'resolution': resolutionText.isEmpty ? null : resolutionText,
        'status': status,
        if (status == 'resolved') 'resolved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', c['id']);
      if (mounted) AppToast.success(context, message: 'Report submitted.');
      _load();
    } catch (e) {
      if (mounted) AppToast.error(context, message: 'Could not submit report. ${friendlyError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: 'Assigned to Me',
      activeItem: 'Assigned to Me',
      activeTab: 'Assigned',
      desktopChild: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Concerns assigned to you',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text('$_open open · ${_rows.length} total',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          // Out-of-scope concerns are flagged, not hidden, so none go unnoticed.
          if (_outOfScopeCount > 0) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF6E7),
                border: Border.all(color: const Color(0xFFE8D8AE)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFFB07D18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_outOfScopeCount concern${_outOfScopeCount == 1 ? '' : 's'} '
                      'below ${_outOfScopeCount == 1 ? 'is' : 'are'} outside your role\'s scope. '
                      'Ask an administrator to reassign ${_outOfScopeCount == 1 ? 'it' : 'them'}.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7A5A12), height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (_rows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppColors.cardShadow),
              child: const Text('Nothing is assigned to you right now.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            )
          else
            for (final c in _rows) _card(c),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    final resolved = c['status'] == 'resolved' || c['status'] == 'dismissed';
    final offScope = _outOfScope(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
        border: offScope ? Border.all(color: const Color(0xFFE8D8AE)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (offScope) ...[
            Row(
              children: [
                const Icon(Icons.swap_horiz, size: 14, color: Color(0xFFB07D18)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Normally handled by ${concernOwnerLabel(c['category']?.toString())}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB07D18)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('#${c['complaint_number'] ?? c['id']} · ${(c['subject'] ?? '').toString()}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text([
                      if ((c['category'] ?? '').toString().isNotEmpty) titleCase((c['category'] ?? '').toString()),
                      if ((c['location'] ?? '').toString().isNotEmpty) c['location'].toString(),
                    ].join(' · '), style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              StatusBadge((c['status'] ?? '').toString()),
            ],
          ),
          if ((c['description'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text((c['description'] ?? '').toString(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
          ],
          if ((c['resolution'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.contentBg, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your report', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 3),
                  Text((c['resolution'] ?? '').toString(), style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _report(c),
              icon: const Icon(Icons.assignment_turned_in_outlined, size: 16),
              label: Text(resolved ? 'Update Report' : 'Submit Report'),
            ),
          ),
        ],
      ),
    );
  }
}
