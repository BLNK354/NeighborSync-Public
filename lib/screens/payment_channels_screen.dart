import '../core/field_rules.dart';
import '../core/address_sort.dart';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/image_lightbox.dart';

import '../core/form_helpers.dart';
import '../core/image_compress.dart';
import '../core/permissions.dart';
import '../core/refresh_bus.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/phase_scope.dart';
import '../core/safe_state.dart';

/// Lists the association's GCash, Maya and bank accounts (with QR codes)
/// where residents send their dues. Users with `payments:update` can
/// add, edit, hide and remove them.
class PaymentChannelsScreen extends StatefulWidget {
  const PaymentChannelsScreen({super.key});

  @override
  State<PaymentChannelsScreen> createState() => _PaymentChannelsScreenState();
}

class _PaymentChannelsScreenState extends State<PaymentChannelsScreen> with SafeSetState<PaymentChannelsScreen> {
  List<Map<String, dynamic>> _rows = [];

  /// QR path -> short-lived signed link (the bucket is private).
  final Map<String, String> _qrUrls = {};

  bool _loading = true;
  bool _canManage = false;
  String? _error;

  /// The officer's own phase, used as the default scope.
  String? _myPhase;
  bool _isSuperAdmin = false;
  List<Map<String, dynamic>> _phases = [];

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  /// Loads the channels, the user's permissions and phase info.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = SupabaseService.instance.client;
      final perms = await SupabaseService.instance.getMyPermissions();
      final role = await SupabaseService.instance.getMyRole();
      final profile = await SupabaseService.instance.getMyProfile();

      final rows = await client
          .from('payment_channels')
          .select('*')
          .order('sort_order')
          .order('label');

      final list = List<Map<String, dynamic>>.from(rows);

      // Only super_admin needs the full phase list; officers use their own.
      List<Map<String, dynamic>> phases = [];
      if (role == 'super_admin') {
        final p = await client
            .from('phases')
            .select('code, number, name')
            .eq('is_active', true)
            .order('number');
        phases = sortPhaseRows(p);
      }

      if (!mounted) return;
      setState(() {
        _rows = list;
        _canManage = canPerform(perms, 'payments', 'update');
        _myPhase = profile?['phase'] as String?;
        _isSuperAdmin = role == 'super_admin';
        _phases = phases;
        _loading = false;
      });

      // Runs after the list shows, so a broken QR never hides the account.
      await _refreshQrUrls(list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  /// Creates signed URLs for any QR images not yet loaded.
  Future<void> _refreshQrUrls(List<Map<String, dynamic>> rows) async {
    final storage = SupabaseService.instance.client.storage.from('documents');
    for (final r in rows) {
      final path = (r['qr_image_url'] ?? '').toString();
      if (path.isEmpty || _qrUrls.containsKey(path)) continue;
      try {
        final url = await storage.createSignedUrl(path, 3600);
        if (!mounted) return;
        setState(() => _qrUrls[path] = url);
      } catch (_) {
        // The card shows "QR could not be loaded" for this one.
      }
    }
  }

  // ---------------------------------------------------------------
  // WRITE
  // ---------------------------------------------------------------

  /// Opens the add/edit dialog and reloads if it saved.
  Future<void> _openForm({Map<String, dynamic>? initial}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ChannelDialog(
        initial: initial,
        myPhase: _myPhase,
        isSuperAdmin: _isSuperAdmin,
        phases: _phases,
      ),
    );
    if (saved == true) {
      _qrUrls.clear();
      await _load();
    }
  }

  /// Removes a channel after confirmation.
  Future<void> _delete(Map<String, dynamic> row) async {
    final label = (row['label'] ?? 'this channel').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this payment channel?'),
        content: Text(
          'Residents will no longer see $label when sending proof of payment. '
          'Payments already recorded against it are kept — they simply stop '
          'naming an account.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.instance.client
          .from('payment_channels')
          .delete()
          .eq('id', row['id']);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Could not remove it. ${friendlyError(e)}', error: true);
    }
  }

  /// Shows or hides a channel from residents.
  Future<void> _toggleActive(Map<String, dynamic> row) async {
    final next = !((row['is_active'] as bool?) ?? true);
    try {
      await SupabaseService.instance.client
          .from('payment_channels')
          .update({'is_active': next, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', row['id']);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Could not change it. ${friendlyError(e)}', error: true);
    }
  }

  /// Shows a message at the bottom; red when [error] is true.
  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade600 : null,
    ));
  }

  // ---------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    final narrow = MediaQuery.of(context).size.width < 700;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(narrow ? 16 : 24, 20, narrow ? 16 : 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(narrow),
          const SizedBox(height: 18),
          if (_rows.isEmpty) _emptyState() else ..._rows.map(_channelCard),
        ],
      ),
    );
  }

  Widget _header(bool narrow) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment Channels',
            style: TextStyle(
                fontSize: narrow ? 17 : 19,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text(
          'The accounts residents send their dues to. Each one you add here '
          'becomes selectable when they submit proof of payment.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.45),
        ),
      ],
    );
    if (!_canManage) return title;

    final button = FilledButton.icon(
      onPressed: () => _openForm(),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add Channel'),
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [title, const SizedBox(height: 12), button],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: title), const SizedBox(width: 16), button],
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.qr_code_2_outlined, size: 40, color: AppColors.textMuted),
          SizedBox(height: 14),
          Text('No payment channels yet',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          SizedBox(height: 8),
          SizedBox(
            width: 420,
            child: Text(
              'Until one is added, residents can only pay cash at the office — '
              'GCash, Maya and bank transfer stay switched off on their side.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  /// One channel: details, optional QR, and manage buttons.
  Widget _channelCard(Map<String, dynamic> r) {
    final active = (r['is_active'] as bool?) ?? true;
    final path = (r['qr_image_url'] ?? '').toString();
    final url = _qrUrls[path];
    final narrow = MediaQuery.of(context).size.width < 700;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_iconFor(r['channel_type']?.toString()),
                size: 18, color: AppColors.sidebarActiveText),
            const SizedBox(width: 8),
            Flexible(
              child: Text((r['label'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
            const SizedBox(width: 8),
            _chip(_scopeLabel(r['phase']?.toString())),
            if (!active) ...[
              const SizedBox(width: 6),
              _chip('Hidden', amber: true),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if ((r['account_name'] ?? '').toString().isNotEmpty)
          _detailRow('Account name', r['account_name'].toString()),
        if ((r['account_number'] ?? '').toString().isNotEmpty)
          _detailRow('Account number', r['account_number'].toString()),
        if ((r['instructions'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(r['instructions'].toString(),
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textMuted, height: 1.45)),
        ],
        if (_canManage) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openForm(initial: r),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
              TextButton(
                onPressed: () => _toggleActive(r),
                child: Text(active ? 'Hide from residents' : 'Show to residents'),
              ),
              TextButton(
                onPressed: () => _delete(r),
                child: Text('Remove', style: TextStyle(color: Colors.red.shade600)),
              ),
            ],
          ),
        ],
      ],
    );

    final qr = _qrBox(path, url);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? AppColors.border : const Color(0xFFE8E2CE)),
      ),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (qr != null) ...[qr, const SizedBox(height: 14)],
                details,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (qr != null) ...[qr, const SizedBox(width: 18)],
                Expanded(child: details),
              ],
            ),
    );
  }

  /// The QR image box, or null when the channel has no QR.
  Widget? _qrBox(String path, String? url) {
    if (path.isEmpty) return null;
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text('QR could not be loaded',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
            )
          : TapToPreview(
              imageUrl: url,
              semanticLabel: 'Payment QR code',
              child: Image.network(
              url,
              fit: BoxFit.contain,
              semanticLabel: 'Payment QR code',
              errorBuilder: (_, __, ___) => const Center(
                child: Text('QR could not be loaded',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
            ),
            ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {bool amber = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: amber ? const Color(0xFFFFF4DB) : const Color(0xFFEFF6F1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: amber ? const Color(0xFF8A6300) : AppColors.sidebarActiveText)),
    );
  }

  static String _scopeLabel(String? phase) =>
      (phase == null || phase.isEmpty) ? 'All phases' : 'Phase ${phaseNumberOf(phase)}';

  static IconData _iconFor(String? type) {
    switch (type) {
      case 'gcash':
      case 'maya':
        return Icons.smartphone_outlined;
      case 'bank':
        return Icons.account_balance_outlined;
      default:
        return Icons.payments_outlined;
    }
  }
}

// =================================================================
// ADD / EDIT
// =================================================================

/// Add or edit one payment channel (type, account, scope, QR image).
class _ChannelDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final String? myPhase;
  final bool isSuperAdmin;
  final List<Map<String, dynamic>> phases;

  const _ChannelDialog({
    this.initial,
    required this.myPhase,
    required this.isSuperAdmin,
    required this.phases,
  });

  @override
  State<_ChannelDialog> createState() => _ChannelDialogState();
}

class _ChannelDialogState extends State<_ChannelDialog> with SafeSetState<_ChannelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _type = 'gcash';
  bool _active = true;

  /// Empty string means "all phases"; a null would show a blank dropdown.
  String _scope = '';

  String? _qrPath;
  String? _qrPreviewUrl;
  Uint8List? _pendingQrBytes;
  String? _pendingQrName;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _type = (i['channel_type'] ?? 'gcash').toString();
      // The dropdown crashes on a value it has no item for.
      if (!const ['gcash', 'maya', 'bank', 'other'].contains(_type)) _type = 'other';
      _labelCtrl.text = (i['label'] ?? '').toString();
      _nameCtrl.text = (i['account_name'] ?? '').toString();
      _numberCtrl.text = (i['account_number'] ?? '').toString();
      _notesCtrl.text = (i['instructions'] ?? '').toString();
      _active = (i['is_active'] as bool?) ?? true;
      _scope = (i['phase'] ?? '').toString();
      _qrPath = (i['qr_image_url'] ?? '').toString().isEmpty
          ? null
          : i['qr_image_url'].toString();
    } else {
      // New channels start on the officer's own phase.
      _scope = widget.myPhase ?? '';
    }
    if (_qrPath != null) _signExisting();
  }

  /// Gets a preview link for the QR already saved.
  Future<void> _signExisting() async {
    try {
      final url = await SupabaseService.instance.client.storage
          .from('documents')
          .createSignedUrl(_qrPath!, 3600);
      if (mounted) setState(() => _qrPreviewUrl = url);
    } catch (_) {}
  }

  /// GCash and Maya use a mobile number; banks use an account number.
  bool get _isWallet => _type == 'gcash' || _type == 'maya';

  @override
  void dispose() {
    _labelCtrl.dispose();
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// Lets the user pick a QR image from their device.
  Future<void> _pickQr() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;

    // Must stay lossless: JPEG blurs the QR and it may stop scanning.
    final shrunk = compressImageBytes(
      file.bytes!,
      file.name,
      maxEdge: kMaxQrEdge,
      lossless: true,
    );

    setState(() {
      _pendingQrBytes = shrunk.bytes;
      _pendingQrName = shrunk.filename;
      _qrPreviewUrl = null;
    });
  }

  /// Uploads the new QR (if any) and inserts or updates the channel.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = SupabaseService.instance.client;
      var path = _qrPath;

      if (_pendingQrBytes != null) {
        final safe = (_pendingQrName ?? 'qr.png')
            .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        // Timestamped so a replaced QR never overwrites the old file.
        path = 'payment-qr/${DateTime.now().millisecondsSinceEpoch}-$safe';
        await client.storage.from('documents').uploadBinary(path, _pendingQrBytes!);
      }

      final payload = <String, dynamic>{
        'channel_type': _type,
        'label': _labelCtrl.text.trim(),
        'account_name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'account_number':
            _numberCtrl.text.trim().isEmpty ? null : _numberCtrl.text.trim(),
        'instructions': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'qr_image_url': path,
        'is_active': _active,
        // Must be a real NULL for "all phases"; '' breaks the phases.code link.
        'phase': _scope.isEmpty ? null : _scope,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': await SupabaseService.instance.getMyUserId(),
      };

      if (widget.initial == null) {
        await client.from('payment_channels').insert(payload);
      } else {
        await client
            .from('payment_channels')
            .update(payload)
            .eq('id', widget.initial!['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Width follows the screen so it fits phones.
    final insetH = media.size.width < 500 ? 16.0 : 40.0;
    final contentWidth =
        (media.size.width - (insetH * 2) - 48).clamp(240.0, 460.0).toDouble();

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: insetH, vertical: 24),
      title: Text(widget.initial == null ? 'Add Payment Channel' : 'Edit Payment Channel'),
      content: SizedBox(
        width: contentWidth,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                    DropdownMenuItem(value: 'maya', child: Text('Maya')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'gcash'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _labelCtrl,
                  decoration: InputDecoration(
                    labelText: 'Label',
                    hintText: _type == 'bank' ? 'BPI, BDO, Landbank…' : 'HOA GCash',
                    helperText: _type == 'bank'
                        ? 'Name the bank — residents need to know which one.'
                        : 'What the resident sees in the list.',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'A label is required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameCtrl,
                  inputFormatters: nameInputFormatters,
                  decoration: const InputDecoration(
                    labelText: 'Account name',
                    hintText: 'Sunrise Heights HOA',
                    // The filter drops digits silently, so state the rule.
                    helperText: 'Letters only — no digits.',
                  ),
                  validator: (v) => nameRule(v, const {}),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  // New key per type so the length limit re-applies on switch.
                  key: ValueKey('acct-$_isWallet'),
                  controller: _numberCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: _isWallet
                      ? phoneInputFormatters
                      : accountNumberInputFormatters,
                  decoration: InputDecoration(
                    labelText: _isWallet ? 'Mobile number' : 'Account number',
                    hintText: _isWallet ? '09XXXXXXXXX' : 'Digits only',
                    helperText: 'Shown so a resident can type it if the QR will not scan.',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    if (_isWallet) return phoneError(t);
                    return RegExp(r'^\d{6,16}$').hasMatch(t)
                        ? null
                        : 'Enter 6 to 16 digits';
                  },
                ),
                const SizedBox(height: 14),
                _scopeField(),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  maxLength: kMaxTextLength,
                  decoration: const InputDecoration(
                    labelText: 'Instructions (optional)',
                    hintText: 'Put your lot number in the message field.',
                  ),
                ),
                const SizedBox(height: 18),
                _qrPicker(),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('Show to residents', style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text(
                    'Turn off to retire an account without deleting the payments '
                    'recorded against it.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }

  /// Scope picker. Only offers scopes the database accepts: an officer's own
  /// phase or shared.
  Widget _scopeField() {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('All phases (shared)')),
    ];
    if (widget.isSuperAdmin) {
      final seen = <String>{};
      for (final p in widget.phases) {
        final num = (p['number'] ?? '').toString();
        if (num.isEmpty || !seen.add(num)) continue;
        items.add(DropdownMenuItem(
            value: (p['code'] ?? '').toString(), child: Text('Phase $num')));
      }
    } else if (widget.myPhase != null && widget.myPhase!.isNotEmpty) {
      items.add(DropdownMenuItem(
          value: widget.myPhase!,
          child: Text('Phase ${phaseNumberOf(widget.myPhase!)} only')));
    }

    // Only "shared" is possible, so show text instead of a one-item dropdown.
    if (items.length == 1) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('This channel will be shared with every phase.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      );
    }

    return DropdownButtonFormField<String>(
      key: ValueKey('scope-${items.length}'),
      initialValue: items.any((i) => i.value == _scope) ? _scope : '',
      decoration: const InputDecoration(
        labelText: 'Who pays into this',
        helperText: 'Dues are collected per phase, so this usually stays on your own.',
      ),
      items: items,
      onChanged: (v) => setState(() => _scope = v ?? ''),
    );
  }

  /// QR preview with an upload/replace button.
  Widget _qrPicker() {
    final hasPreview = _pendingQrBytes != null || _qrPreviewUrl != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('QR code',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF5C5C66))),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: !hasPreview
                  ? const Icon(Icons.qr_code_2_outlined, color: AppColors.textMuted)
                  : _pendingQrBytes != null
                      ? Image.memory(_pendingQrBytes!,
                          fit: BoxFit.contain, semanticLabel: 'Payment QR code')
                      : Image.network(_qrPreviewUrl!,
                          fit: BoxFit.contain, semanticLabel: 'Payment QR code'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickQr,
                    icon: const Icon(Icons.upload_outlined, size: 16),
                    label: Text(hasPreview ? 'Replace QR' : 'Upload QR'),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Saved without re-compressing, so the code still scans. '
                    'Screenshot it straight from the GCash or Maya app.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
