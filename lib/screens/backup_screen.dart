import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/browser_download.dart';
import '../core/permissions.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/table_sorting.dart';
import '../widgets/admin_shell.dart';
import '../widgets/app_toast.dart';
import '../widgets/dashboard_widgets.dart';
import '../core/refresh_bus.dart';
import '../core/safe_state.dart';

/// Backup & Restore screen: creates backups (full or only what changed),
/// shows their history, sets the Auto Backup schedule and restores.
/// Supabase backups run on the server; a Local backup downloads only what
/// this officer can read. Restore needs the backup:restore permission.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

/// Tables that always back up in full, even in an incremental run.
/// A table with no `created_at` must be here, or the incremental filter
/// fails; others are here because a restore needs them whole (`phases`).
const _kAlwaysFullTables = [
  'phases',
  'roles', 'permissions', 'role_permissions', 'permit_types',
  'violation_types', 'budget_categories', 'system_settings',
  'waste_schedules', 'blocks',
  'document_folders', 'facilities', 'payment_channels', 'backup_settings',
];

/// Tables an incremental backup can filter, mapped to whether each has an
/// `updated_at` column.
/// Keep in step with `FILTERABLE_TABLES` in `create-backup`, which fails
/// the whole backup on a table it cannot dump. A table missing from these
/// lists is silently left out, so check them when adding a table.
/// `system_backups` and `login_sessions` are left out on purpose.
const _kFilterableTables = <String, bool>{
  'users': true, 'lots': true, 'announcements': true, 'events': true,
  'bills': true, 'payments': true, 'payment_submissions': true,
  'budget_expenses': true,
  'complaints': true, 'violations': true, 'permits': true, 'vehicles': true,
  'visitor_logs': true, 'gate_passes': true, 'move_requests': true,
  'household_members': true, 'reservations': true,
  'security_incidents': true, 'documents': true,
  'notifications': true, 'personal_folders': true,
  // Rows are never edited, so created_at alone is enough.
  'audit_logs': false,
};

final _kBackupTables = [..._kAlwaysFullTables, ..._kFilterableTables.keys];

const _kDayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

class _BackupScreenState extends State<BackupScreen>
    with SafeSetState<BackupScreen>, TableSortState {
  // Current page of the history table, starting at 1.
  int _page = 1;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  // Auto Backup form values, loaded from backup_settings.
  bool _autoEnabled = false;
  String _autoFrequency = 'daily';
  int _autoDayOfWeek = 0;
  TimeOfDay _autoTime = const TimeOfDay(hour: 2, minute: 0);
  String _autoBackupType = 'full';
  bool _savingSettings = false;
  bool _canRestore = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads the backup history, the Auto Backup settings and the permissions.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = SupabaseService.instance.client;
      final results = await Future.wait<dynamic>([
        client
            .from('system_backups')
            .select('*, creator:created_by(first_name, last_name)')
            .order('created_at', ascending: false)
            .limit(200),
        client.from('backup_settings').select().eq('id', 1).maybeSingle(),
        SupabaseService.instance.getMyPermissions(),
      ]);
      if (!mounted) return;
      final settings = results[1] as Map<String, dynamic>?;
      final perms = results[2] as Map<String, Set<String>>;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(results[0] as List);
        _canRestore = canPerform(perms, 'backup', 'restore');
        if (settings != null) {
          _autoEnabled = settings['enabled'] as bool? ?? false;
          _autoFrequency = settings['frequency'] as String? ?? 'daily';
          _autoDayOfWeek = settings['day_of_week'] as int? ?? 0;
          _autoBackupType = settings['backup_type'] as String? ?? 'full';
          // A value not in a dropdown's list crashes it, so unknown values
          // fall back to the default.
          if (!const ['daily', 'weekly'].contains(_autoFrequency)) _autoFrequency = 'daily';
          if (_autoDayOfWeek < 0 || _autoDayOfWeek > 6) _autoDayOfWeek = 0;
          if (!const ['full', 'incremental'].contains(_autoBackupType)) _autoBackupType = 'full';
          final timeStr = settings['time_of_day'] as String? ?? '02:00:00';
          final parts = timeStr.split(':');
          _autoTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 2, minute: int.tryParse(parts[1]) ?? 0);
        }
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

  int get _totalBackups => _rows.length;

  int get _storageBytes => _rows
      .where((r) => r['destination'] == 'supabase' && r['status'] == 'completed')
      .fold<int>(0, (sum, r) => sum + ((r['size_bytes'] as num?)?.toInt() ?? 0));

  String get _lastBackupLabel {
    if (_rows.isEmpty) return 'Never';
    final t = DateTime.tryParse(_rows.first['created_at']?.toString() ?? '');
    return _timeAgo(t);
  }

  Map<String, dynamic>? get _lastScheduledBackup {
    for (final r in _rows) {
      if (r['trigger_source'] == 'scheduled' && r['status'] == 'completed') return r;
    }
    return null;
  }

  String _timeAgo(DateTime? t) {
    if (t == null) return '—';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return '—';
    return [p['first_name'], p['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
  }

  (Color, Color, String) _destinationBadge(String? destination) {
    switch (destination) {
      case 'supabase':
        return (AppColors.badgeGreenBg, AppColors.badgeGreenText, 'Supabase');
      case 'local':
        return (AppColors.badgeBlueBg, AppColors.badgeBlueText, 'Local');
      case 'google_drive':
        return (AppColors.badgeAmberBg, AppColors.badgeAmberText, 'Google Drive');
      default:
        return (AppColors.badgeGrayBg, AppColors.badgeGrayText, destination ?? '—');
    }
  }

  (Color, Color, String) _statusBadge(String? status) {
    switch (status) {
      case 'completed':
        return (AppColors.badgeGreenBg, AppColors.badgeGreenText, 'Completed');
      case 'failed':
        return (AppColors.badgeRedBg, AppColors.badgeRedText, 'Failed');
      default:
        return (AppColors.badgeGrayBg, AppColors.badgeGrayText, status ?? '—');
    }
  }

  (Color, Color, String) _modeBadge(String? backupType) {
    return backupType == 'incremental'
        ? (AppColors.badgeAmberBg, AppColors.badgeAmberText, 'Incremental')
        : (AppColors.badgeGrayBg, AppColors.badgeGrayText, 'Full');
  }

  String _triggerLabel(String? trigger) => trigger == 'scheduled' ? 'Auto' : 'Manual';

  /// Runs a server-side backup through the create-backup Edge Function.
  Future<void> _backupToSupabase(String backupType) async {
    try {
      final res = await SupabaseService.instance.client.functions.invoke(
        'create-backup',
        body: {'backup_type': backupType, 'trigger': 'manual'},
      );
      final body = res.data;
      if (res.status != 200) {
        final err = (body is Map) ? body['error']?.toString() : null;
        throw Exception(err ?? 'Backup failed (status ${res.status}).');
      }
      if (!mounted) return;
      AppToast.success(context, message: 'Backup created and stored in Supabase.');
      _load();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, message: 'Supabase backup failed. ${friendlyError(e)}');
    }
  }

  /// Downloads what this officer can read as a JSON file, then logs the
  /// backup in the history.
  Future<void> _backupToLocal(String backupType) async {
    try {
      final client = SupabaseService.instance.client;

      String? since;
      if (backupType == 'incremental') {
        final last = await client
            .from('system_backups')
            .select('created_at')
            .eq('destination', 'local')
            .eq('status', 'completed')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        since = last?['created_at'] as String?;
      }
      // With no earlier local backup to compare against, run a full one.
      final effectiveType = since != null ? backupType : 'full';

      final dump = <String, dynamic>{};
      var rowCount = 0;
      for (final table in _kBackupTables) {
        try {
          var query = client.from(table).select();
          if (effectiveType == 'incremental' && since != null && _kFilterableTables.containsKey(table)) {
            final hasUpdatedAt = _kFilterableTables[table]!;
            query = hasUpdatedAt
                ? query.or('created_at.gte.$since,updated_at.gte.$since')
                : query.gte('created_at', since);
          }
          final data = await query;
          final list = List<Map<String, dynamic>>.from(data as List);
          dump[table] = list;
          rowCount += list.length;
        } catch (_) {
          // This user cannot read the table: leave it empty and carry on.
          dump[table] = [];
        }
      }

      // Adds sign-in accounts, which the API cannot read directly. Includes
      // password hashes so restored logins work; treat the file as sensitive.
      try {
        final auth = await client.rpc('backup_auth_accounts',
            params: {'p_since': effectiveType == 'incremental' ? since : null});
        if (auth is Map) {
          for (final key in const ['auth_users', 'auth_identities']) {
            final list = List<dynamic>.from(auth[key] as List? ?? const []);
            dump[key] = list;
            rowCount += list.length;
          }
        }
      } catch (_) {
        // Without permission the file has no logins; restoring it leaves
        // existing logins as they are.
      }

      final payload = jsonEncode({
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'backup_type': effectiveType,
        'since': since,
        'tables': dump,
      });
      final bytes = utf8.encode(payload);
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final fileName = 'neighborsync_backup_${effectiveType}_$timestamp.json';

      triggerBrowserDownload(fileName, bytes, mimeType: 'application/json');

      final myId = await SupabaseService.instance.getMyUserId();
      await client.from('system_backups').insert({
        'destination': 'local',
        'file_name': fileName,
        'size_bytes': bytes.length,
        'status': 'completed',
        'table_count': _kBackupTables.length,
        'row_count': rowCount,
        'backup_type': effectiveType,
        'since_timestamp': since,
        'created_by': myId,
      });

      if (!mounted) return;
      AppToast.success(context, message: 'Backup downloaded to your device.');
      _load();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, message: 'Local backup failed. ${friendlyError(e)}');
    }
  }

  /// Restores a backup stored in Supabase.
  Future<void> _restoreFromSupabase(Map<String, dynamic> row, bool replace) async {
    final path = row['storage_path'] as String?;
    if (path == null) return;
    await _runRestore(
        body: {'storage_path': path, 'mode': replace ? 'replace' : 'merge'},
        sourceLabel: (row['file_name'] ?? path).toString());
  }

  /// Lets the officer pick a backup .json file, checks it, then restores it.
  Future<void> _restoreFromLocalFile(bool replace) async {
    final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: ['json']);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      AppToast.error(context, message: 'Could not read that file -- try again.');
      return;
    }
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, message: '"${file.name}" is not a valid backup file. ${friendlyError(e)}');
      return;
    }
    final tables = parsed['tables'];
    if (tables is! Map) {
      if (!mounted) return;
      AppToast.error(context, message: '"${file.name}" doesn\'t look like a NeighborSync backup -- no "tables" found.');
      return;
    }
    await _runRestore(body: {
      'tables': tables,
      'backup_type': parsed['backup_type'],
      'mode': replace ? 'replace' : 'merge',
    }, sourceLabel: file.name);
  }

  /// Calls the restore-backup Edge Function, which writes on the server
  /// because an officer's own policies cannot write every table.
  Future<void> _runRestore({required Map<String, dynamic> body, required String sourceLabel}) async {
    setState(() => _restoring = true);
    try {
      final res = await SupabaseService.instance.client.functions.invoke('restore-backup', body: body);
      final data = res.data;
      if (res.status != 200) {
        final err = (data is Map) ? data['error']?.toString() : null;
        throw Exception(err ?? 'Restore failed (status ${res.status}).');
      }
      if (!mounted) return;
      setState(() => _restoring = false);
      await _showRestoreResults(sourceLabel, data as Map<String, dynamic>);
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _restoring = false);
      AppToast.error(context, message: 'Restore failed. ${friendlyError(e)}');
    }
  }

  /// Shows how many rows were restored or removed, and any tables that failed.
  Future<void> _showRestoreResults(String sourceLabel, Map<String, dynamic> data) async {
    final totalRestored = data['total_restored'] as int? ?? 0;
    final removed = data['rows_removed'] as int? ?? 0;
    final replaced = data['mode'] == 'replace';
    final failedTables = List<String>.from(data['failed_tables'] as List? ?? const []);
    final results = (data['results'] as Map?)?.cast<String, dynamic>() ?? const {};
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(failedTables.isEmpty ? 'Restore complete' : 'Restore finished with issues'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Restored $totalRestored row(s) from "$sourceLabel".',
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                if (replaced) ...[
                  const SizedBox(height: 6),
                  Text('Removed $removed row(s) the backup did not contain, so the system now matches it.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ],
                if (failedTables.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('These tables could not be restored:',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.errorRed)),
                  const SizedBox(height: 4),
                  for (final t in failedTables)
                    Text('• $t: ${(results[t] as Map?)?['error'] ?? 'unknown error'}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 10),
                const Text('This restore was recorded in Audit Logs.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Opens the restore dialog with the completed Supabase backups.
  Future<void> _openRestoreDialog() async {
    final supabaseBackups = _rows
        .where((r) => r['destination'] == 'supabase' && r['status'] == 'completed' && r['storage_path'] != null)
        .toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _RestoreBackupDialog(
        backups: supabaseBackups,
        formatBytes: _formatBytes,
        onRestoreFromSupabase: (row, replace) {
          Navigator.pop(dialogContext);
          _restoreFromSupabase(row, replace);
        },
        onRestoreFromLocalFile: (replace) {
          Navigator.pop(dialogContext);
          _restoreFromLocalFile(replace);
        },
      ),
    );
  }

  /// Downloads a stored backup through a short-lived link and logs the download.
  Future<void> _download(Map<String, dynamic> row) async {
    final path = row['storage_path'] as String?;
    if (path == null) return;
    try {
      final url = await SupabaseService.instance.client.storage.from('backups').createSignedUrl(path, 60);

      // `download` saves the file instead of opening it. Keep the link's
      // existing `token` parameter or the link fails.
      final fileName = (row['file_name'] as String?)?.trim();
      final safeName = (fileName == null || fileName.isEmpty)
          ? path.split('/').last
          : fileName;
      final downloadUrl = Uri.parse(url).replace(
        queryParameters: {
          ...Uri.parse(url).queryParameters,
          'download': safeName,
        },
      ).toString();

      // Log each download; no table changes, so no trigger records it.
      await SupabaseService.instance.logAuditAction(
        'download',
        'backup',
        resource: safeName,
      );

      await launchUrl(Uri.parse(downloadUrl), webOnlyWindowName: '_self');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, message: 'Could not generate a download link. ${friendlyError(e)}');
    }
  }

  /// Opens the dialog for choosing backup type and destination.
  Future<void> _openCreateBackupDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _CreateBackupDialog(
        onSupabase: (type) {
          Navigator.pop(dialogContext);
          _backupToSupabase(type);
        },
        onLocal: (type) {
          Navigator.pop(dialogContext);
          _backupToLocal(type);
        },
      ),
    );
  }

  Future<void> _pickAutoTime() async {
    final picked = await showTimePicker(context: context, initialTime: _autoTime);
    if (picked != null) setState(() => _autoTime = picked);
  }

  /// Saves the Auto Backup schedule, which runs on the server.
  Future<void> _saveAutoBackupSettings() async {
    setState(() => _savingSettings = true);
    try {
      final myId = await SupabaseService.instance.getMyUserId();
      final time =
          '${_autoTime.hour.toString().padLeft(2, '0')}:${_autoTime.minute.toString().padLeft(2, '0')}:00';
      await SupabaseService.instance.client.from('backup_settings').update({
        'enabled': _autoEnabled,
        'frequency': _autoFrequency,
        'day_of_week': _autoFrequency == 'weekly' ? _autoDayOfWeek : null,
        'time_of_day': time,
        'backup_type': _autoBackupType,
        'updated_by': myId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', 1);
      if (!mounted) return;
      setState(() => _savingSettings = false);
      AppToast.success(context, message: 'Auto Backup settings saved.');
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingSettings = false);
      AppToast.error(context, message: 'Could not save settings. ${friendlyError(e)}');
    }
  }

  /// Sort value per column: 0 File, 1 Size, 2 Destination, 3 Mode, 4 Trigger,
  /// 5 Created by, 6 Date, 7 Status.
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> r, int col) {
    switch (col) {
      case 0:
        return text(r['file_name']);
      case 1:
        return number(r['size_bytes']);
      case 2:
        return text(r['destination']);
      case 3:
        return text(r['backup_type']);
      case 4:
        return text(r['trigger_source']);
      case 5:
        return text(_name(r['creator'] as Map<String, dynamic>?));
      case 6:
        return date(r['created_at']);
      case 7:
        return rankedKey(r['status'], kStatusRank);
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Backup & Restore',
      activeItem: 'Backup',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load backups: $_error', style: const TextStyle(color: Colors.redAccent)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // The label shortens first, so the buttons stay on screen.
                          const Expanded(
                            child: Text('Backup history',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
                          ),
                          if (_canRestore) ...[
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _restoring ? null : _openRestoreDialog,
                              icon: _restoring
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.restore_outlined, size: 16),
                              label: Text(_restoring ? 'Restoring…' : 'Restore'),
                            ),
                          ],
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: _openCreateBackupDialog,
                            icon: const Icon(Icons.backup_outlined, size: 16),
                            label: const Text('Create Backup'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      responsiveStatCards((w) => [
                        DashboardStatCard(icon: Icons.history_outlined, iconBg: AppColors.badgeGreenBg, label: 'Last Backup', value: _lastBackupLabel, width: w),
                        DashboardStatCard(icon: Icons.folder_zip_outlined, iconBg: AppColors.badgeBlueBg, label: 'Total Backups', value: '$_totalBackups', width: w),
                        DashboardStatCard(icon: Icons.storage_outlined, iconBg: AppColors.badgeAmberBg, label: 'Storage Used (Supabase)', value: _formatBytes(_storageBytes), width: w),
                      ]),
                      const SizedBox(height: 20),
                      _autoBackupCard(),
                      const SizedBox(height: 20),
                      _buildTable(),
                    ],
                  ),
                ),
    );
  }


  /// Card for turning Auto Backup on and setting its schedule.
  Widget _autoBackupCard() {
    final lastAuto = _lastScheduledBackup;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Auto Backup', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(width: 10),
              Switch(value: _autoEnabled, onChanged: (v) => setState(() => _autoEnabled = v)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Runs entirely on the server via a scheduled job -- it keeps working even if nobody has this page open. '
            'Checked roughly every 15 minutes, so a run may land up to 15 minutes after the time below.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 4),
          Text(
            lastAuto != null
                ? 'Last automatic backup: ${_timeAgo(DateTime.tryParse(lastAuto['created_at']?.toString() ?? ''))}'
                : 'No automatic backup has run yet.',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 720;
            final fields = <Widget>[
              SizedBox(
                width: narrow ? double.infinity : 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _autoFrequency,
                  decoration: const InputDecoration(labelText: 'Frequency', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  ],
                  onChanged: (v) => setState(() => _autoFrequency = v ?? _autoFrequency),
                ),
              ),
              if (_autoFrequency == 'weekly')
                SizedBox(
                  width: narrow ? double.infinity : 160,
                  child: DropdownButtonFormField<int>(
                    initialValue: _autoDayOfWeek,
                    decoration: const InputDecoration(labelText: 'Day', isDense: true),
                    items: [
                      for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(_kDayNames[i])),
                    ],
                    onChanged: (v) => setState(() => _autoDayOfWeek = v ?? _autoDayOfWeek),
                  ),
                ),
              SizedBox(
                width: narrow ? double.infinity : 160,
                child: InkWell(
                  onTap: _pickAutoTime,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Time', isDense: true),
                    child: Text(_autoTime.format(context)),
                  ),
                ),
              ),
              SizedBox(
                width: narrow ? double.infinity : 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _autoBackupType,
                  decoration: const InputDecoration(labelText: 'Backup Type', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'full', child: Text('Full')),
                    DropdownMenuItem(value: 'incremental', child: Text('Incremental')),
                  ],
                  onChanged: (v) => setState(() => _autoBackupType = v ?? _autoBackupType),
                ),
              ),
            ];
            return Wrap(spacing: 14, runSpacing: 14, children: fields);
          }),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _savingSettings ? null : _saveAutoBackupSettings,
              child: Text(_savingSettings ? 'Saving…' : 'Save Schedule'),
            ),
          ),
        ],
      ),
    );
  }

  /// The backup history table, or a short message when there are none.
  Widget _buildTable() {
    if (_rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.center,
        child: const Text('No backups yet -- create one above.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: fullWidthTable(
            footer: pagerFor(_rows.length, _page, (p) => setState(() => _page = p)),
            
        DataTable(
          showCheckboxColumn: false,
          sortColumnIndex: sortColumn,
          sortAscending: sortAsc,
          columnSpacing: 28,
          headingRowHeight: 40,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
          headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
          dataTextStyle: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
          columns: [
            DataColumn(label: const Text('BACKUP FILE'), onSort: onSort),
            DataColumn(label: const Text('SIZE'), onSort: onSort),
            DataColumn(label: const Text('DESTINATION'), onSort: onSort),
            DataColumn(label: const Text('MODE'), onSort: onSort),
            DataColumn(label: const Text('TRIGGER'), onSort: onSort),
            DataColumn(label: const Text('CREATED BY'), onSort: onSort),
            DataColumn(label: const Text('DATE'), onSort: onSort),
            DataColumn(label: const Text('STATUS'), onSort: onSort),
            const DataColumn(label: Text('ACTIONS')),
          ],
          rows: [
            for (final r in pageSlice(sortRows(_rows), _page))
              DataRow(cells: [
                DataCell(Text((r['file_name'] ?? '').toString(), overflow: TextOverflow.ellipsis)),
                DataCell(Text(_formatBytes((r['size_bytes'] as num? ?? 0).toInt()))),
                DataCell(_badge(_destinationBadge(r['destination'] as String?))),
                DataCell(_badge(_modeBadge(r['backup_type'] as String?))),
                DataCell(Text(_triggerLabel(r['trigger_source'] as String?))),
                DataCell(Text(_name(r['creator'] as Map<String, dynamic>?))),
                DataCell(Text((r['created_at'] ?? '').toString().split('T').first)),
                DataCell(_badge(_statusBadge(r['status'] as String?))),
                DataCell(
                  r['destination'] == 'supabase' && r['storage_path'] != null
                      ? IconButton(
                          tooltip: 'Download',
                          icon: const Icon(Icons.download_outlined, size: 18),
                          onPressed: () => _download(r),
                        )
                      : const Text('—', style: TextStyle(color: AppColors.textMuted)),
                ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _badge((Color, Color, String) spec) {
    final (bg, fg, label) = spec;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// Dialog for choosing the backup type and where to store it.
class _CreateBackupDialog extends StatefulWidget {
  final void Function(String backupType) onSupabase;
  final void Function(String backupType) onLocal;
  const _CreateBackupDialog({required this.onSupabase, required this.onLocal});

  @override
  State<_CreateBackupDialog> createState() => _CreateBackupDialogState();
}

class _CreateBackupDialogState extends State<_CreateBackupDialog> with SafeSetState<_CreateBackupDialog> {
  String _type = 'full';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Backup'),
      // Shrinks on narrow screens and scrolls on short ones.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text('Backup type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _typeChip('full', 'Full', 'Every row, every table.')),
                const SizedBox(width: 10),
                Expanded(child: _typeChip('incremental', 'Incremental', 'Only what changed since last time.')),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Destination', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            _option(
              icon: Icons.cloud_outlined,
              iconBg: AppColors.badgeGreenBg,
              iconFg: AppColors.badgeGreenText,
              title: 'Supabase',
              subtitle: 'Server-side backup, stored securely in this project\'s storage.',
              buttonLabel: 'Back up',
              onPressed: () => widget.onSupabase(_type),
            ),
            const SizedBox(height: 12),
            _option(
              icon: Icons.download_outlined,
              iconBg: AppColors.badgeBlueBg,
              iconFg: AppColors.badgeBlueText,
              title: 'Local (this device)',
              subtitle: 'Downloads the data your account can see as a JSON file to your computer.',
              buttonLabel: 'Back up',
              onPressed: () => widget.onLocal(_type),
            ),
            const SizedBox(height: 12),
            _option(
              icon: Icons.add_to_drive_outlined,
              iconBg: AppColors.badgeAmberBg,
              iconFg: AppColors.badgeAmberText,
              title: 'Google Drive',
              subtitle: 'Save backups directly to your organization\'s Drive.',
              buttonLabel: 'Coming soon',
              onPressed: null,
            ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Widget _typeChip(String value, String title, String subtitle) {
    final selected = _type == value;
    return InkWell(
      onTap: () => setState(() => _type = value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.badgeGreenBg : Colors.transparent,
          border: Border.all(color: selected ? AppColors.badgeGreenText : AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 16, color: selected ? AppColors.badgeGreenText : AppColors.textMuted),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? AppColors.badgeGreenText : AppColors.textPrimary)),
            ]),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _option({
    required IconData icon,
    required Color iconBg,
    required Color iconFg,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Icon(icon, color: iconFg, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          onPressed == null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.badgeGrayBg, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Coming soon', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.badgeGrayText)),
                )
              : OutlinedButton(onPressed: onPressed, child: Text(buttonLabel)),
        ],
      ),
    );
  }
}

/// Restore dialog: pick a stored backup or upload a .json file, in Merge or
/// Replace mode. Restoring can't be undone, so nothing runs until the
/// officer ticks the checkbox.
class _RestoreBackupDialog extends StatefulWidget {
  final List<Map<String, dynamic>> backups;
  final String Function(int bytes) formatBytes;
  final void Function(Map<String, dynamic> row, bool replace) onRestoreFromSupabase;
  final void Function(bool replace) onRestoreFromLocalFile;

  const _RestoreBackupDialog({
    required this.backups,
    required this.formatBytes,
    required this.onRestoreFromSupabase,
    required this.onRestoreFromLocalFile,
  });

  @override
  State<_RestoreBackupDialog> createState() => _RestoreBackupDialogState();
}

class _RestoreBackupDialogState extends State<_RestoreBackupDialog> with SafeSetState<_RestoreBackupDialog> {
  Map<String, dynamic>? _selected;
  bool _acknowledged = false;
  bool _replace = false;
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Replace deletes records, so it asks for the word typed out as well as
  /// the checkbox; merge only ever adds or overwrites.
  bool get _ready =>
      _acknowledged && (!_replace || _confirmCtrl.text.trim().toUpperCase() == 'REPLACE');

  Widget _modeOption(bool replace, String title, String help) {
    final on = _replace == replace;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _replace = replace),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: on ? AppColors.sidebarActiveText : AppColors.border, width: on ? 1.6 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18, color: on ? AppColors.sidebarActiveText : AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(help, style: const TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restore Backup'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorRedBg,
                  border: Border.all(color: AppColors.errorRedBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.errorRed),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Restoring overwrites any existing row that shares an id with the backup. This can\'t be undone.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.errorRed, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('How to restore', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              _modeOption(false, 'Merge (add and update)',
                  'Puts back every record in the backup and updates matching ones. Records the backup does not have are kept.'),
              const SizedBox(height: 8),
              _modeOption(true, 'Replace (match the backup exactly)',
                  'Also DELETES every record the backup does not have, so the system looks exactly like it did when the backup was taken. Full backups only. Your own account is always kept.'),
              if (_replace) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Type REPLACE to confirm',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _acknowledged,
                onChanged: (v) => setState(() => _acknowledged = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('I understand this will overwrite existing data.', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 12),
              const Text('From a Supabase backup', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              if (widget.backups.isEmpty)
                const Text('No completed Supabase backups yet.', style: TextStyle(fontSize: 12, color: AppColors.textMuted))
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.backups.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, i) {
                      final b = widget.backups[i];
                      return RadioListTile<Map<String, dynamic>>(
                        dense: true,
                        value: b,
                        // ignore: deprecated_member_use
                        groupValue: _selected,
                        // ignore: deprecated_member_use
                        onChanged: _acknowledged ? (v) => setState(() => _selected = v) : null,
                        title: Text((b['file_name'] ?? '').toString(),
                            style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${(b['created_at'] ?? '').toString().split('T').first} · ${widget.formatBytes((b['size_bytes'] as num? ?? 0).toInt())}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              const Text('Or from a local file', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _ready ? () => widget.onRestoreFromLocalFile(_replace) : null,
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: const Text('Choose a backup .json file'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: (_ready && _selected != null) ? () => widget.onRestoreFromSupabase(_selected!, _replace) : null,
          child: const Text('Restore Selected'),
        ),
      ],
    );
  }
}
