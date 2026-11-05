import '../core/app_locale.dart' show tr;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'charts.dart';
import '../core/local_time.dart';

/// Lays out a row of stat cards: a sideways-scrolling strip on phones
/// (< 640px), equal-width wrapping cards on wider screens. [build] receives
/// the width to give each card.
Widget responsiveStatCards(List<Widget> Function(double cardWidth) build,
    {double gap = 16,
    double narrowCardWidth = 158,
    // Tall enough for a card with both a caption and the link line.
    double narrowHeight = 168,
    /// Smallest a card may shrink to before the row wraps. Roughly the width
    /// at which a label like "Under Review" still fits on one line.
    double minCardWidth = 210}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 640;
      if (narrow) {
        final cards = build(narrowCardWidth);
        // No cards (all gated off by permissions): skip the fixed-height strip
        // so no blank band is left.
        if (cards.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: narrowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: cards.length,
            separatorBuilder: (_, __) => SizedBox(width: gap),
            itemBuilder: (_, i) => cards[i],
          ),
        );
      }
      // Column count rules: never narrower than [minCardWidth], and never a
      // single orphan card on the last row (5 cards become 3 + 2, not 4 + 1).
      final probe = build(0);
      final count = probe.isEmpty ? 1 : probe.length;

      var cols = ((constraints.maxWidth + gap) / (minCardWidth + gap)).floor();
      cols = cols.clamp(1, count);
      while (cols > 2 && count % cols == 1) {
        cols--;
      }

      final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: build(width));
    },
  );
}

/// One stat tile (icon, label, value) used on every officer dashboard.
class DashboardStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String label;
  final String? value;
  final double width;
  /// Opens the screen behind the number; also shows a hover state and a
  /// "View" hint.
  final VoidCallback? onTap;

  /// Set when the card filters a list: true while the list is narrowed to
  /// this card (brand border, "tap to clear" hint). Null = a plain link.
  final bool? selected;

  /// Small grey line under the value explaining what the number covers.
  final String? caption;

  /// Replaces the "View" text on a plain (selected == null) card.
  final String? hint;
  const DashboardStatCard({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.label,
    this.value,
    required this.width,
    this.onTap,
    this.selected,
    this.caption,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    // Height follows the content; a fixed height would overflow.
    final compact = width < 190;
    final card = Container(
      width: width.clamp(150, 400),
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
        border: Border.all(
          color: selected == true ? AppColors.sidebarActiveText : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 34 : 44,
            height: compact ? 34 : 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Icon(icon, size: compact ? 18 : 20, color: AppColors.textPrimary),
          ),
          SizedBox(height: compact ? 8 : 14),
          Text(tr(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: compact ? 20 : 24, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          if (caption != null) ...[
            SizedBox(height: compact ? 2 : 4),
            Text(caption!,
                // One line on a phone: the strip has a fixed height.
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
          if (onTap != null) ...[
            SizedBox(height: compact ? 4 : 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr(selected == null ? (hint ?? 'View') : (selected! ? 'Showing · tap to clear' : 'Show these')),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.sidebarActiveText)),
                const SizedBox(width: 2),
                Icon(selected == true ? Icons.close : (selected == null ? Icons.arrow_forward : Icons.filter_list),
                    size: 12, color: AppColors.sidebarActiveText),
              ],
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// White rounded panel that holds a chart, table or list.
class DashboardPanel extends StatelessWidget {
  final Widget child;
  final double? height;
  const DashboardPanel({super.key, required this.child, this.height});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: height,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        child: child,
      );
}

/// Small column header text for the dashboard tables.
class DashboardColHeader extends StatelessWidget {
  final String text;
  const DashboardColHeader(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: AppColors.textSecondary));
}

/// Short "nothing here yet" message shown inside a panel.
class DashboardEmptyNote extends StatelessWidget {
  final String text;
  const DashboardEmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(text,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      );
}

/// Billed and collected totals for one calendar month.
class MonthAmount {
  final int year;
  final int month;
  double billed = 0;
  double collected = 0;
  MonthAmount({required this.year, required this.month});
}

const dashboardMonthLabels = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Builds the last 6 monthly buckets plus this year's billed and collected
/// totals from raw bills and payments rows.
({List<MonthAmount> buckets, double billedYear, double collectedYtd}) buildCollectionsBuckets(
  List<Map<String, dynamic>> bills,
  List<Map<String, dynamic>> payments,
) {
  final now = DateTime.now();
  final buckets = <MonthAmount>[];
  for (var i = 5; i >= 0; i--) {
    final d = DateTime(now.year, now.month - i, 1);
    buckets.add(MonthAmount(year: d.year, month: d.month));
  }
  double billedYear = 0;
  double collectedYtd = 0;
  for (final b in bills) {
    final due = DateTime.tryParse(b['due_date']?.toString() ?? '');
    final amt = num.tryParse(b['amount']?.toString() ?? '0') ?? 0;
    if (due == null) continue;
    for (final bucket in buckets) {
      if (due.year == bucket.year && due.month == bucket.month) bucket.billed += amt;
    }
    if (due.year == now.year) billedYear += amt;
  }
  for (final p in payments) {
    if (p['status'] != 'verified') continue;
    // Convert to local time to match the buckets; due_date above is a
    // zone-less date and must not be converted.
    final pd = localTime(p['payment_date']);
    final amt = num.tryParse(p['amount_paid']?.toString() ?? '0') ?? 0;
    if (pd == null) continue;
    for (final bucket in buckets) {
      if (pd.year == bucket.year && pd.month == bucket.month) bucket.collected += amt;
    }
    if (pd.year == now.year) collectedYtd += amt;
  }
  return (buckets: buckets, billedYear: billedYear, collectedYtd: collectedYtd);
}

/// Short peso amount: ₱1.50M, ₱12k, ₱500.
String dashboardMoney(double v) {
  if (v >= 1000000) return '₱${(v / 1000000).toStringAsFixed(2)}M';
  if (v >= 1000) return '₱${(v / 1000).toStringAsFixed(0)}k';
  return '₱${v.toStringAsFixed(0)}';
}

/// Collections Overview: 6-month billed/collected bars and a
/// collection-rate donut.
class CollectionsChart extends StatelessWidget {
  final List<MonthAmount> monthly;
  final double collectionRate;
  final double collectedYtd;

  const CollectionsChart({
    super.key,
    required this.monthly,
    required this.collectionRate,
    required this.collectedYtd,
  });

  @override
  Widget build(BuildContext context) {
    // Billed first so the bars sit in legend order.
    final series = [
      ChartSeries(
          label: 'Billed',
          color: kSeriesColors[1],
          values: [for (final m in monthly) m.billed]),
      ChartSeries(
          label: 'Collected',
          color: kSeriesColors[0],
          values: [for (final m in monthly) m.collected]),
    ];
    return DashboardPanel(
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Collections Overview',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Row(children: [
            _legendDot(kSeriesColors[0], 'Collected'),
            const SizedBox(width: 16),
            _legendDot(kSeriesColors[1], 'Billed'),
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: monthly.isEmpty
                      ? const Center(
                          child: Text('No billing activity yet.',
                              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)))
                      : GroupedBarChart(
                          labels: [
                            for (final m in monthly) dashboardMonthLabels[m.month - 1]
                          ],
                          series: series,
                          // Axis reads 120K, not 120000.
                          formatValue: (v) => '\u20B1${compactNumber(v)}',
                        ),
                ),
                const SizedBox(width: 16),
                Align(alignment: Alignment.center, child: _donut()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(tr(label), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]);


  /// Collection-rate ring with its caption underneath.
  Widget _donut() {
    return SizedBox(
      width: 130,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 110,
                height: 110,
                child: CircularProgressIndicator(
                  value: collectionRate,
                  strokeWidth: 14,
                  backgroundColor: AppColors.badgeGrayBg,
                  valueColor: AlwaysStoppedAnimation(AppColors.sidebarActiveText),
                ),
              ),
              Text('${(collectionRate * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ]),
          ),
          const SizedBox(height: 10),
          Text('Collection rate · ${dashboardMonthLabels[DateTime.now().month - 1]}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text('${dashboardMoney(collectedYtd)} collected YTD',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// "Good morning", "Good afternoon" or "Good evening" by the device clock.
String dashboardGreeting() {
  final h = DateTime.now().hour;
  if (h < 12) return tr('Good morning');
  if (h < 18) return tr('Good afternoon');
  return tr('Good evening');
}

const _kRoleLabels = {
  'super_admin': 'System Administrator',
  'hoa_president': 'HOA President',
  'secretary': 'Secretary',
  'treasurer': 'Treasurer',
  'security': 'Security',
  'audit_officer': 'Audit Officer',
};

/// Display name for an officer role ("hoa_president" -> "HOA President").
String dashboardRoleLabel(String? role) =>
    _kRoleLabels[role] ?? (role ?? '').replaceAll('_', ' ');

/// Greeting block at the top of every officer dashboard.
///
/// [mobile] gives the phone version: role chip under the top bar, then a
/// smaller greeting.
class DashboardHeader extends StatelessWidget {
  final String? firstName;
  final String? role;
  final String communityName;
  final bool mobile;

  const DashboardHeader({
    super.key,
    required this.firstName,
    required this.role,
    required this.communityName,
    this.mobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final name = (firstName ?? '').trim();
    final hello = name.isEmpty ? dashboardGreeting() : '${dashboardGreeting()}, $name';
    if (!mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hello,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.onPortalPrimary)),
          const SizedBox(height: 6),
          Text(
              role == null
                  ? "Here's what's happening in $communityName today"
                  : "${dashboardRoleLabel(role)} · here's what's happening in $communityName today",
              style: TextStyle(fontSize: 14, color: AppColors.onPortalSecondary)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: role == null
                ? const SizedBox(height: 22)
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.sidebarActiveText,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(dashboardRoleLabel(role),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Text(hello,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onPortalPrimary)),
        ),
      ],
    );
  }
}
