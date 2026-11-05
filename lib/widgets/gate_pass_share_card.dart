import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/branding.dart';
import '../core/browser_download.dart';
import '../theme/resident_theme.dart';

/// Saves a gate pass as a picture a resident can send to their guest.
///
/// The QR holds `qr_token`, which the guardhouse scanner reads, so anyone
/// with the image can present the pass. The guard checks the visitor name
/// shown on the scan, so the name is printed large above the code.
///
/// If the saved picture is blank, check the web renderer: `toImage()` returns
/// an empty image (no error) under Flutter Web's old HTML renderer.

/// Fixed-width pass card that is rendered to PNG. It is not shown on screen,
/// so the saved picture looks the same on every device.
class GatePassShareCard extends StatelessWidget {
  static const double cardWidth = 380;

  final Map<String, dynamic> pass;

  /// The resident being visited. Either may be blank; a blank line is left out.
  final String hostName;
  final String hostAddress;

  const GatePassShareCard({
    super.key,
    required this.pass,
    this.hostName = '',
    this.hostAddress = '',
  });

  @override
  Widget build(BuildContext context) {
    final branding = AppBranding.instance;
    final status = (pass['status'] ?? '').toString();
    final token = (pass['qr_token'] ?? '').toString();
    final plate = (pass['vehicle_plate'] ?? '').toString().trim();
    final purpose = (pass['purpose'] ?? '').toString().trim();

    return Material(
      // Material supplies text direction and style; the capture overlay has none.
      color: Colors.white,
      child: SizedBox(
        width: cardWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(branding),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (pass['visitor_name'] ?? 'Visitor').toString(),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700, color: ResidentColors.textPrimary, height: 1.15),
                  ),
                  if (purpose.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(purpose,
                        style: const TextStyle(fontSize: 13, color: ResidentColors.textSecondary)),
                  ],
                  const SizedBox(height: 18),
                  Center(child: _qr(token)),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      (pass['pass_number'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 12.5,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                        color: ResidentColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const _Perforation(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hostName.isNotEmpty)
                    _row('VISITING', hostName, sub: hostAddress.isEmpty ? null : hostAddress),
                  _row('VALID UNTIL', _dateLong(pass['valid_until']?.toString()),
                      sub: _time(pass['valid_until']?.toString())),
                  if (plate.isNotEmpty) _row('VEHICLE', plate),
                  const SizedBox(height: 14),
                  _footer(status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Coloured top band with the community name.
  Widget _header(AppBranding branding) {
    return Container(
      color: branding.sidebarColor,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(
        children: [
          // Drawn monogram, not the logo: a network image captures as an empty box.
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(branding.logoMonogram,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: branding.sidebarColor)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(branding.communityName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 2),
                const Text('VISITOR GATE PASS',
                    style: TextStyle(
                        fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: Color(0xFF9DC3AC))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The QR code, or a notice when the pass has no token.
  Widget _qr(String token) {
    if (token.isEmpty) {
      return Container(
        width: 200,
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: ResidentColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('QR unavailable for this pass',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
      );
    }
    return QrImageView(
      data: token,
      version: QrVersions.auto,
      size: 210,
      backgroundColor: Colors.white,
      // Blank margin around the code; many scanners reject one without it.
      padding: const EdgeInsets.all(10),
    );
  }

  /// A small label with its value and an optional second line.
  Widget _row(String label, String value, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 9.5, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: ResidentColors.textSecondary)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: ResidentColors.textPrimary)),
                if (sub != null && sub.isNotEmpty)
                  Text(sub, style: const TextStyle(fontSize: 12, color: ResidentColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Message box that follows the pass status, so a pending pass never
  /// claims the guest is cleared to enter.
  Widget _footer(String status) {
    final s = status.toLowerCase().trim();
    final approved = s == 'approved';
    final dead = s == 'rejected' || s == 'expired' || s == 'used';

    final String line;
    if (approved) {
      line = 'Approved. Show this at the guardhouse with a valid ID.';
    } else if (dead) {
      line = 'This pass is no longer valid. Ask your host to register a new one.';
    } else {
      line = 'Awaiting approval by the guardhouse. Show this on arrival with a '
          'valid ID — the guard will confirm before letting you in.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dead ? const Color(0xFFFDECEC) : (approved ? const Color(0xFFE3F1E9) : const Color(0xFFFBEFD6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            dead ? Icons.block : (approved ? Icons.verified_outlined : Icons.schedule),
            size: 15,
            color: dead
                ? const Color(0xFF8A1C1C)
                : (approved ? const Color(0xFF14532D) : const Color(0xFF8A6300)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(line,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: dead
                      ? const Color(0xFF8A1C1C)
                      : (approved ? const Color(0xFF14532D) : const Color(0xFF6B4D00)),
                )),
          ),
        ],
      ),
    );
  }

  /// Local 12-hour time like "until 05:30 PM"; empty if the date is bad.
  static String _time(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final period = t.hour >= 12 ? 'PM' : 'AM';
    return 'until ${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
  }

  /// Date with the year, since the saved picture stays in chats for months.
  static String _dateLong(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '—';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[t.month - 1]} ${t.day}, ${t.year}';
  }
}

/// Dotted tear line between the QR half and the details half.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, c) {
          const dot = 4.0;
          const gap = 5.0;
          final count = (c.maxWidth - 48) ~/ (dot + gap);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                count < 1 ? 1 : count,
                (_) => Container(
                  width: dot,
                  height: 1.6,
                  color: ResidentColors.border,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Renders [pass] as a PNG and downloads it in the browser.
///
/// Returns null on success, or a message to show the resident. Never throws.
Future<String?> saveGatePassImage(
  BuildContext context,
  Map<String, dynamic> pass, {
  String hostName = '',
  String hostAddress = '',
}) async {
  // Only the browser can download; callers hide the button via [gatePassImageSupported].
  if (!kIsWeb) {
    return 'Saving the pass as a picture is available in the browser version of NeighborSync.';
  }

  final key = GlobalKey();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return 'Could not prepare the image on this screen.';

  // Drawn in an overlay, moved off-screen. Do not hide it with Opacity(0) or
  // Offstage: they skip painting, so the image would come out blank.
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 0,
      top: 0,
      child: Transform.translate(
        offset: const Offset(0, -20000),
        child: RepaintBoundary(
          key: key,
          child: GatePassShareCard(pass: pass, hostName: hostName, hostAddress: hostAddress),
        ),
      ),
    ),
  );

  try {
    overlay.insert(entry);

    // Wait two frames. Do not read `debugNeedsPaint` instead: it throws in release builds.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return 'Could not draw the pass image.';

    // 3x so the code stays sharp when zoomed on a phone.
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return 'Could not draw the pass image.';

    triggerBrowserDownload(
      _fileName(pass),
      // Respect the offset; the ByteData may not start at 0 of its buffer.
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      mimeType: 'image/png',
    );
    return null;
  } catch (e) {
    return 'Could not save the pass image. $e';
  } finally {
    entry.remove();
  }
}

/// Whether this build can save the picture (web only, including installed PWAs).
bool get gatePassImageSupported => kIsWeb;

/// Download name built from the pass number.
String _fileName(Map<String, dynamic> pass) {
  final raw = (pass['pass_number'] ?? pass['id'] ?? 'pass').toString();
  // Replace characters that some systems reject in file names.
  final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  return 'gate-pass-$safe.png';
}
