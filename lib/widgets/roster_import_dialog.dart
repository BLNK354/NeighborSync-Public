/// Bulk import of the existing homeowner roster.
///
/// Creates roster records, not login accounts: each row goes into `users`
/// with no `supabase_uid`. When the person registers with the same email,
/// `handle_new_auth_user()` links them to that record instead of adding a duplicate.
///
/// Always previews first: `import_homeowners(rows, dry_run => true)` shows
/// each row's result before anything is saved.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import '../core/xlsx_reader.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../core/dialog_sizing.dart';
import '../core/safe_state.dart';

/// Columns the file may use. Order doesn't matter; header spelling does.
const kRosterColumns = ['first_name', 'last_name', 'email', 'phone', 'block', 'lot', 'role'];

/// Sample file shown to officers. Keep the emails on a real provider:
/// `import_homeowners` rejects reserved domains like example.com.
const kRosterTemplate = 'first_name,last_name,email,phone,block,lot,role\n'
    'Juan,Dela Cruz,juan.delacruz@gmail.com,09171234567,80,2,member_resident\n'
    'Maria,Santos,maria.santos@gmail.com,09189876543,80,5,member_resident\n';

/// Opens the import dialog; resolves to true if rows were imported.
Future<bool?> showRosterImportDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Dialog(child: _RosterImportDialog()),
  );
}

class _RosterImportDialog extends StatefulWidget {
  const _RosterImportDialog();

  @override
  State<_RosterImportDialog> createState() => _RosterImportDialogState();
}

class _RosterImportDialogState extends State<_RosterImportDialog> with SafeSetState<_RosterImportDialog> {
  List<Map<String, String>> _rows = [];
  List<Map<String, dynamic>> _results = [];
  String? _fileName;
  String? _error;
  bool _busy = false;
  bool _previewed = false;
  bool _done = false;
  int _ok = 0;
  int _failed = 0;

  /// Small CSV reader that handles quoted fields and commas inside them.
  List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        row.add(field.toString());
        field = StringBuffer();
      } else if (ch == '\n' || ch == '\r') {
        // Swallow CRLF as one break.
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field = StringBuffer();
        if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }
    row.add(field.toString());
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  /// Lets the user pick a file, checks its header, then runs the preview.
  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'txt'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read that file.');
      return;
    }

    try {
      // Both .xlsx and CSV become the same table; chosen by file extension.
      final name = picked.files.first.name.toLowerCase();
      final isXlsx = name.endsWith('.xlsx');

      // Old .xls is neither zip nor text. The picker filter does not stop it
      // on web, so reject it here with a clear message.
      if (name.endsWith('.xls')) {
        setState(() => _error =
            'That is an older Excel workbook (.xls), which cannot be read here.\n'
            'Open it in Excel and use File → Save As to save it as .xlsx or .csv, '
            'then upload that.');
        return;
      }

      final List<List<String>> table;
      if (isXlsx) {
        table = readXlsxSheet(bytes);
      } else {
        // Excel exports are often not UTF-8; tolerate bad bytes.
        final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
        table = _parseCsv(text);
      }
      if (table.length < 2) {
        setState(() => _error = 'That file has a header but no rows.');
        return;
      }

      final header = table.first.map((h) => h.trim().toLowerCase()).toList();
      final missing =
          ['first_name', 'last_name', 'email'].where((c) => !header.contains(c)).toList();
      if (missing.isNotEmpty) {
        // List the columns found so a wrong file is easy to spot.
        final found = table.first.map((h) => h.trim()).where((h) => h.isNotEmpty).toList();
        setState(() => _error =
            'Missing required column${missing.length == 1 ? '' : 's'}: ${missing.join(', ')}.\n'
            '${found.isEmpty ? 'The first row of this file is empty.' : 'This file\'s first row has: ${found.take(8).join(', ')}${found.length > 8 ? ', ...' : ''}.'}\n'
            'The header row must use the names under "File format" exactly'
            '${isXlsx ? ', and it must be on the first sheet' : ''}.');
        return;
      }

      final parsed = <Map<String, String>>[];
      for (final line in table.skip(1)) {
        final map = <String, String>{};
        for (var i = 0; i < header.length && i < line.length; i++) {
          if (kRosterColumns.contains(header[i])) {
            map[header[i]] = line[i].trim();
          }
        }
        if (map.values.any((v) => v.isNotEmpty)) parsed.add(map);
      }

      setState(() {
        _fileName = picked.files.first.name;
        _rows = parsed;
        _results = [];
        _previewed = false;
        _done = false;
        _error = null;
      });
      await _run(dryRun: true);
    } on XlsxReadException catch (e) {
      // Its message already says how to fix the file; show it as is.
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not read that file. $e');
    }
  }

  /// Sends the rows to `import_homeowners`; with [dryRun] nothing is saved.
  Future<void> _run({required bool dryRun}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await SupabaseService.instance.client.rpc(
        'import_homeowners',
        params: {'p_rows': _rows, 'p_dry_run': dryRun},
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (!mounted) return;
      setState(() {
        _results = List<Map<String, dynamic>>.from(
            (map['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        _ok = (map['ok'] as num).toInt();
        _failed = (map['failed'] as num).toInt();
        _previewed = true;
        _done = !dryRun;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Import homeowner roster',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.pop(context, _done),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
                'Creates a record for each homeowner so the office has the roster on '
                'file. These records cannot sign in — when a homeowner later registers '
                'with the same email, their account links to the record instead of '
                'creating a duplicate.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.45)),
            const SizedBox(height: 14),
            _fileRow(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.badgeRedBg, borderRadius: BorderRadius.circular(8)),
                child: Text(_error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.badgeRedText)),
              ),
            ],
            if (_previewed) ...[
              const SizedBox(height: 14),
              _summary(),
              const SizedBox(height: 10),
              Flexible(child: _resultList()),
            ],
            const SizedBox(height: 16),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _fileRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.table_chart_outlined, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _fileName ?? 'No file chosen',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  color: _fileName == null ? AppColors.textMuted : AppColors.textPrimary),
            ),
          ),
          if (_fileName != null)
            Text('${_rows.length} row${_rows.length == 1 ? '' : 's'}  ',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          OutlinedButton(
            onPressed: _busy || _done ? null : _pickFile,
            child: Text(_fileName == null ? 'Choose file' : 'Change'),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    return Row(
      children: [
        _pill('$_ok ready', AppColors.badgeGreenBg, AppColors.badgeGreenText),
        if (_failed > 0) ...[
          const SizedBox(width: 8),
          _pill('$_failed skipped', AppColors.badgeAmberBg, AppColors.badgeAmberText),
        ],
        const Spacer(),
        Text(
          _done
              ? 'Imported.'
              : 'Preview only — nothing has been saved yet.',
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: _done ? FontWeight.w600 : FontWeight.w400,
              color: _done ? AppColors.badgeGreenText : AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _resultList() {
    // Failed rows first.
    final sorted = [..._results]..sort((a, b) {
        final ao = a['ok'] == true ? 1 : 0;
        final bo = b['ok'] == true ? 1 : 0;
        if (ao != bo) return ao - bo;
        return (a['row'] as num).compareTo(b['row'] as num);
      });

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final r = sorted[i];
          final ok = r['ok'] == true;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
                    size: 15,
                    color: ok ? AppColors.badgeGreenText : AppColors.badgeAmberText),
                const SizedBox(width: 10),
                SizedBox(
                  width: 34,
                  child: Text('#${r['row']}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          (r['name'] as String?)?.trim().isNotEmpty == true
                              ? r['name'] as String
                              : '(no name)',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      Text((r['message'] ?? '').toString(),
                          style: TextStyle(
                              fontSize: 11.5,
                              color: ok ? AppColors.textSecondary : AppColors.badgeAmberText)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _actions() {
    if (_done) {
      return Row(
        children: [
          const Expanded(
            child: Text('Skipped rows were not saved — fix them in the file and import again.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
        ],
      );
    }
    return Row(
      children: [
        TextButton.icon(
          onPressed: _busy ? null : _showTemplate,
          icon: const Icon(Icons.help_outline, size: 16),
          label: const Text('File format'),
        ),
        const Spacer(),
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _busy || !_previewed || _ok == 0 ? null : () => _run(dryRun: false),
          child: Text(_busy
              ? 'Working…'
              : _ok == 0
                  ? 'Nothing to import'
                  : 'Import $_ok record${_ok == 1 ? '' : 's'}'),
        ),
      ],
    );
  }

  void _showTemplate() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('File format'),
        content: SizedBox(
          width: dialogContentWidth(context, 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'An Excel workbook (.xlsx) or a CSV. The first row must be the '
                  'header, spelled exactly as below. first_name, last_name and '
                  'email are required; the rest are optional.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.highlight, borderRadius: BorderRadius.circular(8)),
                child: const SelectableText(kRosterTemplate,
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.5)),
              ),
              const SizedBox(height: 12),
              const Text(
                  '• email is required because it is how the homeowner later claims '
                  'their account.\n'
                  '• block and lot must already exist in the system, and must not '
                  'already belong to someone else.\n'
                  '• role may be member_resident or tenant only. Officer accounts are '
                  'created individually.\n'
                  '• In Excel, format the phone column as Text before typing the '
                  'numbers. Excel drops the leading 0 from 09171234567 the moment '
                  'it treats the cell as a number, and the file it saves no longer '
                  'has that digit to give back.\n'
                  '• Only the first sheet of a workbook is read.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.5)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}
