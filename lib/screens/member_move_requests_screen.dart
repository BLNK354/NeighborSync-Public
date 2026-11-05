import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import '../core/module_registry.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/status_badge.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// "Move In / Out" page: shows the resident's own move requests and lets
/// them submit a new one.
class MemberMoveRequestsScreen extends StatefulWidget {
  const MemberMoveRequestsScreen({super.key});

  @override
  State<MemberMoveRequestsScreen> createState() => _MemberMoveRequestsScreenState();
}

class _MemberMoveRequestsScreenState extends State<MemberMoveRequestsScreen> with SafeSetState<MemberMoveRequestsScreen> {
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
          .from('move_requests')
          .select('*')
          .eq('resident_id', myId as Object)
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

  /// Opens the shared move request form; it hides office-only fields for
  /// residents.
  Future<void> _openForm() async {
    final saved = await showModuleFormDialog(context, moveRequests);
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'Move In / Out Requests',
      activeItem: 'Move In/Out',
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
                            child: Text('My move requests',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                          ),
                          FilledButton(onPressed: _openForm, child: const Text('New Request')),
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
                                child: Text('No move requests yet.', style: TextStyle(fontSize: 12.5, color: ResidentColors.textSecondary)),
                              )
                            : Column(children: [for (final r in _rows) _requestRow(r)]),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// One move request in the list.
  Widget _requestRow(Map<String, dynamic> r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: ResidentColors.border))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('#${r['request_number'] ?? r['id']} · ${titleCase((r['request_type'] ?? '').toString())}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                const SizedBox(height: 3),
                Text('Move date: ${(r['move_date'] ?? '—').toString()}', style: const TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
              ],
            ),
          ),
          StatusBadge((r['status'] ?? '').toString()),
        ],
      ),
    );
  }
}
