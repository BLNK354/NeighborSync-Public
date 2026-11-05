import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/form_helpers.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';
import '../core/tour_anchors.dart';
import '../core/safe_state.dart';

/// Scan a visitor's gate pass QR and show the pass details.
///
/// Read-only: approving or refusing is done from Review on the Gate Passes
/// list. The QR holds the random `qr_token`, not the pass number. Passes from
/// other phases come back as "No pass found".

/// Opens the scanner dialog; the guard reads the result card and closes it.
Future<void> showGatePassScanner(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _GatePassScannerDialog(),
  );
}

/// The "Scan Pass" button shown on the Gate Passes and Security screens.
class ScanGatePassButton extends StatelessWidget {
  const ScanGatePassButton({super.key, this.compact = false});

  /// Icon-only, for a toolbar that is already full at phone width.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Anchor is here so the tour follows the button on either screen.
    return TourAnchor(
      id: TourAnchorId.scanPass,
      child: compact
          ? IconButton(
              tooltip: 'Scan a gate pass',
              onPressed: () => showGatePassScanner(context),
              icon: const Icon(Icons.qr_code_scanner, size: 20),
            )
          : OutlinedButton.icon(
              onPressed: () => showGatePassScanner(context),
              icon: const Icon(Icons.qr_code_scanner, size: 17),
              label: const Text('Scan Pass'),
            ),
    );
  }
}

/// Camera dialog that scans a QR, looks the pass up and shows the result.
class _GatePassScannerDialog extends StatefulWidget {
  const _GatePassScannerDialog();

  @override
  State<_GatePassScannerDialog> createState() => _GatePassScannerDialogState();
}

class _GatePassScannerDialogState extends State<_GatePassScannerDialog> with SafeSetState<_GatePassScannerDialog> {
  // noDuplicates stops repeat reads; _handled blocks a second scan mid-lookup.
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _handled = false;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _pass;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Called when a QR is read: looks up the pass by its token and logs the scan.
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
    if (raw == null) return;

    _handled = true;
    await _controller.stop();
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      // Named FK: gate_passes has two links to users, so a bare embed fails.
      final row = await SupabaseService.instance.client
          .from('gate_passes')
          .select(
            'id, pass_number, visitor_name, visitor_contact, purpose, '
            'vehicle_plate, valid_from, valid_until, status, current_uses, '
            'max_uses, phase, '
            'host:requested_by(first_name, last_name, phone, address), '
            'lot:lot_id(lot_number, blocks(block_name))',
          )
          .eq('qr_token', raw.trim())
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _loading = false;
        if (row == null) {
          _error = 'No pass found for this code.';
        } else {
          _pass = Map<String, dynamic>.from(row);
        }
      });

      // Log the pass number, never the qr_token (it is the credential).
      if (row != null) {
        unawaited(SupabaseService.instance.logAuditAction(
          'scan',
          'gate_passes',
          resource: (row['pass_number'] ?? '').toString(),
          resourceId: row['id'] is int ? row['id'] as int : null,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not read that pass. ${friendlyError(e)}';
      });
    }
  }

  /// Clears the result and restarts the camera.
  Future<void> _scanAgain() async {
    setState(() {
      _pass = null;
      _error = null;
      _handled = false;
    });
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Dialog chrome takes 128px; keeps the width inside phone screens.
    final maxW = media.size.width - 128;
    final width = maxW < 420 ? maxW : 420.0;

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Scan gate pass')),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: _pass != null
              ? _result(_pass!)
              : _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _camera(media),
        ),
      ),
      actions: [
        if (_pass != null || _error != null)
          TextButton.icon(
            onPressed: _scanAgain,
            icon: const Icon(Icons.qr_code_scanner, size: 17),
            label: const Text('Scan another'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }

  /// The live camera preview, with an error banner if the last scan failed.
  Widget _camera(MediaQueryData media) {
    // Capped so the buttons stay visible in landscape.
    final h = media.size.height * 0.42;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          _banner(_error!, const Color(0xFFA82F2F), const Color(0xFFFBECEC), Icons.error_outline),
          const SizedBox(height: 12),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: h < 200 ? 200 : h,
            width: double.infinity,
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              // Explains why the camera failed (often permission denied).
              errorBuilder: (context, error, child) => Container(
                color: const Color(0xFFF4F4F4),
                padding: const EdgeInsets.all(20),
                alignment: Alignment.center,
                child: Text(
                  'Camera unavailable.\n\n${error.errorDetails?.message ?? error.errorCode.name}\n\n'
                  'Allow camera access for this site, then reopen the scanner.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Point the camera at the QR on the visitor\'s pass.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // ── The result card ──────────────────────────────────────────────────

  /// The pass card: verdict banner, visitor, host and validity details.
  Widget _result(Map<String, dynamic> p) {
    final verdict = _verdict(p);
    final host = p['host'] as Map<String, dynamic>?;
    final hostName = [host?['first_name'], host?['last_name']]
        .where((s) => s != null && s.toString().trim().isNotEmpty)
        .join(' ');

    final lot = p['lot'] as Map<String, dynamic>?;
    final block = (lot?['blocks'] as Map<String, dynamic>?)?['block_name'];
    final address = lot == null
        ? null
        : [if (block != null) 'Block $block', 'Lot ${lot['lot_number']}'].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _banner(verdict.$2, verdict.$3, verdict.$4, verdict.$1),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                (p['visitor_name'] ?? '—').toString(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            StatusBadge((p['status'] ?? '').toString()),
          ],
        ),
        const SizedBox(height: 2),
        Text('Pass #${p['pass_number'] ?? p['id']}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        const SizedBox(height: 14),
        _row('Purpose', p['purpose']),
        _row('Vehicle plate', p['vehicle_plate']),
        _row('Visitor contact', p['visitor_contact']),
        const Divider(height: 22),
        _row('Host', hostName.isEmpty ? null : hostName),
        _row('Host phone', host?['phone']),
        _row('Address', address ?? host?['address']),
        const Divider(height: 22),
        _row('Valid from', _stamp(p['valid_from'])),
        _row('Valid until', _stamp(p['valid_until'])),
        _row('Uses', '${p['current_uses'] ?? 0} of ${p['max_uses'] ?? '—'}'),
        const SizedBox(height: 4),
        const Text(
          'Scanning only looks the pass up. Approving or refusing it is still '
          'done from Review on the Gate Passes list.',
          style: TextStyle(fontSize: 11, height: 1.45, color: AppColors.textMuted),
        ),
      ],
    );
  }

  /// Returns (icon, message, foreground, background) for the pass.
  /// Dates are checked too: an unapproved pass stays `pending` after it
  /// expires, so status alone misleads.
  (IconData, String, Color, Color) _verdict(Map<String, dynamic> p) {
    const red = Color(0xFFA82F2F);
    const redBg = Color(0xFFFBECEC);
    const amber = Color(0xFF8A6100);
    const amberBg = Color(0xFFFBF3E2);
    const green = Color(0xFF1B6B3A);
    const greenBg = Color(0xFFE8F4EC);

    final status = (p['status'] ?? '').toString();
    final now = DateTime.now();
    final from = DateTime.tryParse((p['valid_from'] ?? '').toString())?.toLocal();
    final until = DateTime.tryParse((p['valid_until'] ?? '').toString())?.toLocal();
    final used = (p['current_uses'] as num?)?.toInt() ?? 0;
    final max = (p['max_uses'] as num?)?.toInt();

    if (status == 'rejected') {
      return (Icons.block, 'Rejected — do not admit.', red, redBg);
    }
    if (until != null && now.isAfter(until)) {
      return (Icons.event_busy, 'Expired on ${_stamp(p['valid_until'])}.', red, redBg);
    }
    if (status == 'expired') {
      return (Icons.event_busy, 'Expired.', red, redBg);
    }
    if (status == 'used' || (max != null && used >= max)) {
      return (Icons.done_all, 'Already used — all $used of ${max ?? used} entries spent.', red, redBg);
    }
    if (from != null && now.isBefore(from)) {
      return (Icons.schedule, 'Not valid yet — starts ${_stamp(p['valid_from'])}.', amber, amberBg);
    }
    if (status == 'pending') {
      return (
        Icons.pending_actions,
        'Not approved yet. The guardhouse has to approve this pass before the visitor is admitted.',
        amber,
        amberBg,
      );
    }
    if (status == 'approved') {
      return (Icons.check_circle_outline, 'Valid now.', green, greenBg);
    }
    return (Icons.help_outline, 'Unrecognised status: ${titleCase(status)}.', amber, amberBg);
  }

  /// Coloured message box with an icon.
  Widget _banner(String text, Color fg, Color bg, IconData icon) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600, color: fg)),
            ),
          ],
        ),
      );

  /// One label/value line; empty values show a dash.
  Widget _row(String label, Object? value) {
    final v = value?.toString().trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(v == null || v.isEmpty ? '—' : v,
                style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  /// Formats an ISO timestamp as local "5 Sep 2026, 3:04 PM" (no `intl`).
  String _stamp(Object? iso) {
    final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
    if (d == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '${d.day} ${months[d.month - 1]} ${d.year}, $h:$m $ap';
  }
}
