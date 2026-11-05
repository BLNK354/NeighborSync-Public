import 'package:flutter/material.dart';
import 'image_lightbox.dart';

import '../core/form_helpers.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/resident_theme.dart';
import '../core/safe_state.dart';

/// Shows the active payment accounts as cards with a scannable QR.
/// Phase filtering is done by the database policy, so do not filter here.
/// QR images are in a private bucket and are shown through signed URLs.
class PaymentChannelsView extends StatefulWidget {
  /// Narrows to one method when the resident has already said how they are
  /// paying. Null shows everything.
  final String? onlyType;

  const PaymentChannelsView({super.key, this.onlyType});

  @override
  State<PaymentChannelsView> createState() => _PaymentChannelsViewState();
}

class _PaymentChannelsViewState extends State<PaymentChannelsView> with SafeSetState<PaymentChannelsView> {
  List<Map<String, dynamic>> _rows = [];
  final Map<String, String> _urls = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = SupabaseService.instance.client;
      final rows = await client
          .from('payment_channels')
          .select('id, channel_type, label, account_name, account_number, '
              'qr_image_url, instructions, phase')
          .eq('is_active', true)
          .order('sort_order')
          .order('label');
      var list = List<Map<String, dynamic>>.from(rows);
      if (widget.onlyType != null) {
        list = list
            .where((r) => r['channel_type'] == _typeFor(widget.onlyType!))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });

      final storage = client.storage.from('documents');
      for (final r in list) {
        final p = (r['qr_image_url'] ?? '').toString();
        if (p.isEmpty) continue;
        try {
          final u = await storage.createSignedUrl(p, 3600);
          if (!mounted) return;
          setState(() => _urls[p] = u);
        } catch (_) {
          // The account number below still lets them pay by hand.
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  /// Payments call it `bank_transfer`; channels store it as `bank`.
  static String _typeFor(String method) =>
      method == 'bank_transfer' ? 'bank' : method;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(fontSize: 12.5, color: Colors.redAccent));
    }
    if (_rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ResidentColors.iconAmberBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'The HOA office has not published an online payment account yet. '
          'Pay at the office, then come back and tap Send Proof.',
          style: TextStyle(fontSize: 12, color: ResidentColors.iconAmberText, height: 1.4),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final r in _rows) _card(r)],
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final path = (r['qr_image_url'] ?? '').toString();
    final url = _urls[path];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((r['label'] ?? '').toString(),
              style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          if ((r['account_name'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r['account_name'].toString(),
                style: const TextStyle(fontSize: 12.5, color: ResidentColors.textSecondary)),
          ],
          if ((r['account_number'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            // Selectable so the number can be copied if the QR will not scan.
            SelectableText(r['account_number'].toString(),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.sidebarActiveText)),
          ],
          if (path.isNotEmpty) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: url == null
                    ? const Center(
                        child: Text('QR could not be loaded',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11.5, color: ResidentColors.textSecondary)))
                    : TapToPreview(
                        imageUrl: url,
                        semanticLabel: 'Payment QR code',
                        child: Image.network(url,
                        fit: BoxFit.contain,
                        semanticLabel:
                            'QR code for paying ${(r['label'] ?? 'the HOA').toString()}',
                        errorBuilder: (_, __, ___) => const Center(
                              child: Text('QR could not be loaded',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: ResidentColors.textSecondary)),
                            ))),
              ),
            ),
          ],
          if ((r['instructions'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(r['instructions'].toString(),
                style: const TextStyle(
                    fontSize: 12, color: ResidentColors.textSecondary, height: 1.4)),
          ],
        ],
      ),
    );
  }
}
