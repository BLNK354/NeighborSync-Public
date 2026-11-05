import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import '../services/supabase_service.dart';
import '../theme/resident_theme.dart';
import '../widgets/member_shell.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';
import '../core/stored_file.dart';

/// Resident Documents: official forms plus files the office has shared
/// (`is_public = true` in `documents`). "View" opens the file outside the
/// app; there is no in-app PDF viewer.
class MemberDocumentsScreen extends StatefulWidget {
  const MemberDocumentsScreen({super.key});

  @override
  State<MemberDocumentsScreen> createState() => _MemberDocumentsScreenState();
}

class _MemberDocumentsScreenState extends State<MemberDocumentsScreen> with SafeSetState<MemberDocumentsScreen> {
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _officialForms = [];
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
      // Only documents the office has shared.
      final results = await Future.wait<dynamic>([
        SupabaseService.instance.client
            .from('documents')
            .select('*')
            .eq('is_public', true)
            .order('created_at', ascending: false)
            .limit(300),
        // Official downloadable forms set by the office.
        SupabaseService.instance.client
            .from('system_settings')
            .select('setting_key, value')
            .inFilter('setting_key', ['forms.complaint_form_url', 'forms.official_forms']),
      ]);
      if (!mounted) return;
      final forms = <Map<String, dynamic>>[];
      for (final r in List<Map<String, dynamic>>.from(results[1] as List)) {
        final v = r['value'] as String?;
        if (r['setting_key'] == 'forms.complaint_form_url' && v != null && v.isNotEmpty) {
          forms.add({'name': 'Complaint / Concern Form', 'url': v});
        } else if (r['setting_key'] == 'forms.official_forms' && v != null && v.isNotEmpty) {
          try {
            forms.addAll(List<Map<String, dynamic>>.from(jsonDecode(v) as List));
          } catch (_) {}
        }
      }
      setState(() {
        _rows = List<Map<String, dynamic>>.from(results[0] as List);
        _officialForms = forms;
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

  // Opens the file. Use the public link when there is one: its storage_path
  // belongs to a different bucket and would not be found.
  Future<void> _view(Map<String, dynamic> d) async {
    final pub = (d['public_url'] ?? '').toString();
    final path = d['storage_path'] as String?;
    if (pub.isEmpty && path == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This document has no file attached.')));
      return;
    }
    try {
      await openStoredFile(
        context,
        path: pub.isEmpty ? path : null,
        publicUrl: pub,
        name: d['name']?.toString(),
        mimeType: d['mime_type']?.toString(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open that file. ${friendlyError(e)}')));
    }
  }

  // Turns a byte count into a label like "2.4 MB".
  String _formatBytes(num? bytes) {
    final n = (bytes ?? 0).toInt();
    if (n <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = n.toDouble();
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: 'Documents',
      activeItem: 'Documents',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_officialForms.isNotEmpty) ...[
                        const Text('Official Forms',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                        const SizedBox(height: 4),
                        const Text('Downloadable HOA forms.',
                            style: TextStyle(fontSize: 11.5, color: ResidentColors.textSecondary)),
                        const SizedBox(height: 12),
                        for (final f in _officialForms) _formRow(f),
                        const SizedBox(height: 24),
                      ],
                      const Text('Shared with residents', style: TextStyle(fontSize: 13, color: ResidentColors.textSecondary)),
                      const SizedBox(height: 16),
                      if (_rows.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: ResidentColors.cardShadow),
                          child: const Text('No documents shared yet.', style: TextStyle(fontSize: 12.5, color: ResidentColors.textSecondary)),
                        )
                      else
                        for (final d in _rows) _row(d),
                    ],
                  ),
                ),
    );
  }

  /// One official form row, opened from its public link.
  Widget _formRow(Map<String, dynamic> f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: ResidentColors.cardShadow),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ResidentColors.badgeBg, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.description_outlined, size: 20, color: ResidentColors.sidebarActiveText),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text((f['name'] ?? 'Form').toString(),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
          ),
          TextButton(
            onPressed: () {
              final url = (f['url'] ?? '').toString();
              if (url.isEmpty) return;
              openStoredFile(context, publicUrl: url, name: f['name']?.toString())
                  .catchError((_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open that form.')));
              });
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  /// One shared document row.
  Widget _row(Map<String, dynamic> d) {
    final ext = ((d['mime_type'] ?? '').toString().contains('pdf')) ? 'PDF' : 'FILE';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: ResidentColors.cardShadow),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ResidentColors.iconBlueBg, borderRadius: BorderRadius.circular(8)),
            child: Text(ext, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: ResidentColors.textPrimary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((d['name'] ?? 'Document').toString(),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if ((d['category'] ?? '').toString().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: ResidentColors.iconGrayBg, borderRadius: BorderRadius.circular(6)),
                        child: Text((d['category'] ?? '').toString(),
                            style: const TextStyle(fontSize: 10.5, color: ResidentColors.textSecondary)),
                      ),
                    if (_formatBytes(d['size_bytes'] as num?).isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(_formatBytes(d['size_bytes'] as num?), style: const TextStyle(fontSize: 10.5, color: ResidentColors.textSecondary)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          TextButton(onPressed: () => _view(d), child: const Text('View')),
        ],
      ),
    );
  }
}
