import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import 'package:go_router/go_router.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/resident_theme.dart';
import '../core/module_registry.dart';
import '../widgets/member_shell.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _editableStatuses = {'draft', 'submitted'};

String _dateLabel(String? iso) {
  final t = DateTime.tryParse(iso ?? '');
  if (t == null) return '—';
  return '${_months[t.month - 1]} ${t.day.toString().padLeft(2, '0')}';
}

/// Resident's "My Permits" list. Tap a row for details, or use
/// "Apply for Permit" to file a new one. Shows only their own permits.
class MemberPermitsScreen extends StatefulWidget {
  const MemberPermitsScreen({super.key});

  @override
  State<MemberPermitsScreen> createState() => _MemberPermitsScreenState();
}

class _MemberPermitsScreenState extends State<MemberPermitsScreen> with SafeSetState<MemberPermitsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
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
      final data = await SupabaseService.instance.client
          .from('permits')
          .select('*')
          .eq('applicant_id', myId as Object)
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

  /// Most active permits a resident may have. The database enforces this;
  /// this copy is only for the message on screen.
  static const _kMaxActivePermits = 3;

  /// How many of the resident's permits count toward that limit.
  int get _activeCount {
    final today = DateTime.now();
    final d0 = DateTime(today.year, today.month, today.day);
    return _rows.where((r) {
      final s = r['status']?.toString();
      if (!const {'draft', 'submitted', 'under_review', 'approved'}.contains(s)) return false;
      final end = DateTime.tryParse((r['end_date'] ?? '').toString());
      return end == null || !end.isBefore(d0);
    }).length;
  }

  /// Line showing how many active permits the resident has, out of the limit.
  Widget _activeNote() {
    final n = _activeCount;
    final full = n >= _kMaxActivePermits;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: full ? AppColors.badgeAmberBg : AppColors.highlight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        full
            ? 'You have $n active permits -- the most you can have at once is '
                '$_kMaxActivePermits. A new application will be refused until one '
                'finishes, is cancelled or is rejected.'
            : 'Active permits: $n of $_kMaxActivePermits. A permit counts until it '
                'ends, or is rejected or cancelled.',
        style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: full ? AppColors.badgeAmberText : ResidentColors.textPrimary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'My Permits',
      activeItem: 'My Permits',
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
                            child: Text('My permit applications',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                          ),
                          FilledButton(
                            // Same form officers use; it hides the office-only fields
                            // for residents.
                            onPressed: () async {
                              final saved =
                                  await showModuleFormDialog(context, permits);
                              if (saved == true) _load();
                            },
                            child: const Text('Apply for Permit'),
                          ),
                        ],
                      ),
                      _activeNote(),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: ResidentColors.cardShadow),
                        child: _rows.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('No permit applications yet.', style: TextStyle(fontSize: 12.5, color: ResidentColors.textSecondary)),
                              )
                            : Column(children: [for (final r in _rows) _row(r)]),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// One permit in the list.
  Widget _row(Map<String, dynamic> r) {
    return InkWell(
      onTap: () async {
        await context.push('/me/permits/${r['id']}');
        _load();
      },
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
                  Text('#${r['permit_number'] ?? r['id']} ${r['title'] ?? ''}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text('Submitted ${_dateLabel(r['created_at']?.toString())}',
                      style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
                ],
              ),
            ),
            StatusBadge((r['status'] ?? '').toString()),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: ResidentColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// One permit's full details. The resident can edit it while it is still
/// a draft or submitted.
class MemberPermitDetailScreen extends StatefulWidget {
  final int permitId;
  const MemberPermitDetailScreen({super.key, required this.permitId});

  @override
  State<MemberPermitDetailScreen> createState() => _MemberPermitDetailScreenState();
}

class _MemberPermitDetailScreenState extends State<MemberPermitDetailScreen> with SafeSetState<MemberPermitDetailScreen> {
  Map<String, dynamic>? _permit;
  bool _loading = true;
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
      final data = await SupabaseService.instance.client
          .from('permits')
          .select('*, permit_types(name)')
          .eq('id', widget.permitId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _permit = data;
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
    final p = _permit;
    final editable = p != null && _editableStatuses.contains((p['status'] ?? '').toString());
    return MemberShell(
      title: 'Permit Details',
      activeItem: 'My Permits',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || p == null
              ? Center(child: Text(_error ?? 'Permit not found.', style: const TextStyle(color: Colors.redAccent)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: ResidentColors.cardShadow),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('#${p['permit_number']} ${p['title'] ?? ''}',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                                  ),
                                  StatusBadge((p['status'] ?? '').toString()),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _field('Type', (p['permit_types']?['name'] ?? '—').toString()),
                              _field('Start', _dateLabel(p['start_date']?.toString())),
                              _field('End', p['end_date'] == null ? '—' : _dateLabel(p['end_date']?.toString())),
                              _field('Est. Cost', p['fee_amount'] == null ? '—' : '₱${p['fee_amount']}'),
                              _field('Scope', (p['description'] ?? '—').toString()),
                              if ((p['review_notes'] ?? '').toString().isNotEmpty) _field('Review Notes', p['review_notes'].toString()),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (editable)
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  // Same form as officers. Residents can only edit their own
                                  // draft or submitted permit; office fields are read-only.
                                  onPressed: () async {
                                    final saved = await showModuleFormDialog(
                                        context, permits,
                                        initial: _permit);
                                    if (saved == true) _load();
                                  },
                                  child: const Text('Edit Request'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
                              ),
                            ],
                          )
                        else
                          OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
                      ],
                    ),
                  ),
                ),
    );
  }

  /// One label-and-value line on the details page.
  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 13.5, color: ResidentColors.textPrimary)),
        ],
      ),
    );
  }
}
