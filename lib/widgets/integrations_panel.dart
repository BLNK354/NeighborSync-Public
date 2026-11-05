import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../core/safe_state.dart';

/// Settings -> Integrations.
///
/// One live, read-only card for the AI classifier (which engine answered
/// most recently, from `classification_source`), plus greyed "Coming soon"
/// cards for payment, CCTV, Google Drive and government contact.
class IntegrationsPanel extends StatefulWidget {
  const IntegrationsPanel({super.key});

  @override
  State<IntegrationsPanel> createState() => _IntegrationsPanelState();
}

class _IntegrationsPanelState extends State<IntegrationsPanel> with SafeSetState<IntegrationsPanel> {
  bool _loading = true;
  String? _error;

  /// Rows from both tables: {source, at, kind}.
  List<({String source, DateTime at, String kind})> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = SupabaseService.instance.client;
      // Row-level security limits both reads to the viewed phase.
      final results = await Future.wait([
        client
            .from('complaints')
            .select('classification_source, classified_at')
            .not('classified_at', 'is', null)
            .order('classified_at', ascending: false)
            .limit(1000),
        client
            .from('security_incidents')
            .select('classification_source, classified_at')
            .not('classified_at', 'is', null)
            .order('classified_at', ascending: false)
            .limit(1000),
      ]);
      final rows = <({String source, DateTime at, String kind})>[];
      for (var i = 0; i < results.length; i++) {
        for (final r in (results[i] as List)) {
          final at = DateTime.tryParse((r['classified_at'] ?? '').toString());
          if (at == null) continue;
          rows.add((
            source: (r['classification_source'] ?? '').toString(),
            at: at.toLocal(),
            kind: i == 0 ? 'complaint' : 'incident',
          ));
        }
      }
      rows.sort((a, b) => b.at.compareTo(a.at));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load classifier activity.';
      });
    }
  }

  /// Readable name for a stored `classification_source` value.
  static String engineName(String source) => switch (source) {
        'gemini' => 'Google Gemini',
        'claude' => 'Anthropic Claude',
        'naive_bayes+vader' => 'Built-in model (offline)',
        'keyword' => 'Built-in keyword rules (offline)',
        '' => 'Unknown',
        _ => source,
      };

  static bool _isCloud(String source) =>
      source == 'gemini' || source == 'claude';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _date(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Integrations',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        const Text(
          'Outside services NeighborSync uses. Sign-in, the database and file '
          'storage run on Supabase and are not listed here.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 18),
        _classifierCard(),
        const SizedBox(height: 14),
        _paymentCard(),
        const SizedBox(height: 14),
        _cctvCard(),
        const SizedBox(height: 14),
        _driveCard(),
        const SizedBox(height: 14),
        _governmentCard(),
      ],
    );
  }

  Widget _card({required List<Widget> children, bool muted = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFF4F5F5) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E8E5)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _header(IconData icon, String title, Widget badge,
      {bool muted = false}) {
    final c = muted ? AppColors.textMuted : AppColors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 22, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w600, color: c)),
        ),
        badge,
      ],
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _classifierCard() {
    final latest = _rows.isEmpty ? null : _rows.first;
    final now = DateTime.now();
    final thisMonth =
        _rows.where((r) => r.at.year == now.year && r.at.month == now.month);
    final bySource = <String, int>{};
    for (final r in _rows) {
      bySource[r.source] = (bySource[r.source] ?? 0) + 1;
    }
    final sources = bySource.keys.toList()
      ..sort((a, b) => bySource[b]!.compareTo(bySource[a]!));

    final badge = _loading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2))
        : latest == null
            ? _pill('No activity yet', const Color(0xFFEDEFEE),
                AppColors.textMuted)
            : _isCloud(latest.source)
                ? _pill('Active', AppColors.badgeGreenBg,
                    AppColors.badgeGreenText)
                : _pill('Offline fallback', AppColors.badgeAmberBg,
                    AppColors.badgeAmberText);

    return _card(children: [
      _header(Icons.auto_awesome_outlined, 'AI complaint classifier', badge),
      const SizedBox(height: 8),
      const Text(
        'Suggests a category and priority for each new complaint, and a '
        'severity for each incident. Officers can always change the result. '
        'If the AI service is unavailable, a built-in bilingual model '
        '(English and Filipino) answers instead.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      ] else if (!_loading) ...[
        const SizedBox(height: 14),
        _fact(
            'Last answered by',
            latest == null
                ? 'Nothing classified yet'
                : '${engineName(latest.source)} · ${_date(latest.at)}'),
        _fact('Classified this month',
            '${thisMonth.length} item${thisMonth.length == 1 ? '' : 's'}'),
        _fact('Classified in total',
            '${_rows.length} (${_rows.where((r) => r.kind == 'complaint').length} complaints, '
                '${_rows.where((r) => r.kind == 'incident').length} incidents)'),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in sources)
                _pill('${engineName(s)}: ${bySource[s]}',
                    const Color(0xFFEFF3F1), AppColors.textPrimary),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F8FC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.privacy_tip_outlined,
                  size: 16, color: AppColors.textMuted),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Privacy: only the complaint subject and description are '
                  'sent to the AI service -- never the resident\'s name, '
                  'account or address. Residents are told this in the '
                  'Privacy Notice. Counts cover the phase you are viewing.',
                  style:
                      TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _fact(String label, String value) {
    final labelText = Text(label,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted));
    final valueText = Text(value,
        style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary));
    // Stack label over value on phones; the 170px label column is too wide.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, valueText],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 170, child: labelText),
                Expanded(child: valueText),
              ],
            ),
    );
  }

  Widget _paymentCard() => _comingSoonCard(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Online payment (GCash, Maya, cards)',
        what: 'Pay dues inside the app through a payment gateway, with bills '
            'marked paid automatically. Not connected yet.',
        forNow: 'For now, residents pay through the GCash, Maya or bank QR codes in '
            'Finance -> Payment Channels and send proof of payment for the '
            'treasurer to verify.',
      );

  Widget _cctvCard() => _comingSoonCard(
        icon: Icons.videocam_outlined,
        title: 'CCTV camera system',
        what: 'View the gate and street cameras inside NeighborSync, and attach '
            'footage to a security incident or visitor entry. Not connected yet.',
        forNow: 'For now, guards record incidents in Security and visitors in the '
            'visitor log; footage stays on the guardhouse recorder.',
      );

  Widget _driveCard() => _comingSoonCard(
        icon: Icons.cloud_upload_outlined,
        title: 'Google Drive',
        what: "Copy backups and official documents to the association's Google "
            'Drive automatically. Not connected yet.',
        forNow: 'For now, backups are downloaded from Admin -> Backup and files '
            'are kept in Documents.',
      );

  Widget _governmentCard() => _comingSoonCard(
        icon: Icons.account_balance_outlined,
        title: 'Government contact (barangay, police, LGU)',
        what: 'Forward incident reports to the barangay, police or local '
            'government, and post their advisories to residents. Not connected yet.',
        forNow: 'For now, officers contact the authorities directly and record '
            'the report in Security.',
      );

  /// Greyed card for a planned service; its Connect button is disabled.
  Widget _comingSoonCard({
    required IconData icon,
    required String title,
    required String what,
    required String forNow,
  }) {
    return Opacity(
      opacity: 0.7,
      child: _card(muted: true, children: [
        _header(
          icon,
          title,
          _pill('Coming soon', const Color(0xFFE4E6E5), AppColors.textMuted),
          muted: true,
        ),
        const SizedBox(height: 8),
        Text(what, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        Text(forNow, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        const OutlinedButton(
          onPressed: null,
          child: Text('Connect'),
        ),
      ]),
    );
  }
}
