import 'package:flutter/material.dart';
import '../core/module_config.dart';
import '../core/permissions.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';
import '../core/safe_state.dart';

/// A read-only card showing one record, with Edit as a separate action.
///
/// Edit only appears for a caller who holds the module's `update`
/// permission. Returns `true` when the caller chose Edit; the calling
/// screen then opens its own form (this dialog never opens one).
Future<bool?> showModuleDetailDialog(
  BuildContext context,
  ModuleConfig config,
  Map<String, dynamic> row, {
  /// Extra rows shown with the fields, for values the screen computes
  /// instead of stores (e.g. a sticker Valid/Expired badge).
  Map<String, Widget>? extraRows,

  /// One-line summary shown under the title.
  String? subtitle,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _ModuleDetailDialog(
      config: config,
      row: row,
      extraRows: extraRows,
      subtitle: subtitle,
    ),
  );
}

/// The dialog widget behind [showModuleDetailDialog].
class _ModuleDetailDialog extends StatefulWidget {
  const _ModuleDetailDialog({
    required this.config,
    required this.row,
    this.extraRows,
    this.subtitle,
  });

  final ModuleConfig config;
  final Map<String, dynamic> row;
  final Map<String, Widget>? extraRows;
  final String? subtitle;

  @override
  State<_ModuleDetailDialog> createState() => _ModuleDetailDialogState();
}

class _ModuleDetailDialogState extends State<_ModuleDetailDialog> with SafeSetState<_ModuleDetailDialog> {
  Map<String, Set<String>> _perms = {};
  String? _myRole;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Both calls are cached, so only the first one hits the network.
    final perms = await SupabaseService.instance.getMyPermissions();
    final role = await SupabaseService.instance.getMyRole();
    if (!mounted) return;
    setState(() {
      _perms = perms;
      _myRole = role;
      _loading = false;
    });
  }

  bool get _canEdit =>
      widget.config.allowEdit &&
      canPerform(_perms, widget.config.permissionModule, 'update');

  /// Whether to show a field. Role-restricted fields stay hidden, and
  /// reference fields need a `listValueBuilder` or they print a raw id.
  bool _shown(FieldConfig f) {
    if (f.restrictedToRoles != null &&
        !f.restrictedToRoles!.contains(_myRole)) {
      return false;
    }
    if (f.type == FieldType.reference && f.listValueBuilder == null) {
      return false;
    }
    return true;
  }

  /// Content width capped to the screen. AlertDialog's own insets and
  /// padding take 128px, so a fixed width would overflow on a phone.
  double _contentWidth(BuildContext context, double preferred) {
    final available = MediaQuery.sizeOf(context).width - _insetH(context) * 2 - 48;
    return available < preferred ? available : preferred;
  }

  double _insetH(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 500 ? 16 : 40;

  @override
  Widget build(BuildContext context) {
    final title = widget.row[widget.config.titleField]?.toString();
    final fields = widget.config.fields.where((f) => _shown(f)).toList();

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
          horizontal: _insetH(context), vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title == null || title.isEmpty ? widget.config.formNoun : title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(widget.subtitle!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : SizedBox(
              width: _contentWidth(context, 460),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A module's own summary header goes first.
                    if (widget.config.contextBuilder != null &&
                        widget.config.contextAfterField == null) ...[
                      widget.config.contextBuilder!(widget.row),
                      const SizedBox(height: 14),
                    ],
                    for (final f in fields) _row(f),
                    if (widget.extraRows != null)
                      for (final e in widget.extraRows!.entries)
                        _rawRow(e.key, e.value),
                  ],
                ),
              ),
            ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        if (!_loading && _canEdit)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Edit'),
          ),
      ],
    );
  }

  Widget _row(FieldConfig f) {
    // Uses the list's formatter so values match the table.
    final value = f.listDisplay(widget.row);
    return _rawRow(
      f.label,
      f.key == widget.config.statusField
          ? Align(alignment: Alignment.centerLeft, child: StatusBadge(value))
          : Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textPrimary, height: 1.35),
            ),
    );
  }

  /// One label-and-value row. Empty values show a dash instead of being
  /// hidden.
  Widget _rawRow(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted)),
          const SizedBox(height: 3),
          value,
        ],
      ),
    );
  }
}
