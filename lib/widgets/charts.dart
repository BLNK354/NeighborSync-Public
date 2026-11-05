/// Simple chart widgets (bar, line, donut) drawn with CustomPaint.
/// Put one inside a [ChartCard]. They use only Flutter, no chart package.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// One named, coloured set of values. [values] must line up with the
/// chart's `labels` -- shorter lists are treated as zero.
class ChartSeries {
  final String label;
  final Color color;
  final List<double> values;
  const ChartSeries({required this.label, required this.color, required this.values});

  double at(int i) => i < values.length ? values[i] : 0;
}

/// Strong, easy-to-tell-apart colours for chart series.
const kSeriesColors = <Color>[
  AppColors.badgeGreenText,
  AppColors.badgeBlueText,
  AppColors.badgeAmberText,
  AppColors.badgeRedText,
  Color(0xFF6B4E9B),
  AppColors.badgeGrayText,
];

/// Compact peso/short-number formatting for axis ticks: 1200 -> 1.2K.
String compactNumber(double v) {
  final a = v.abs();
  if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(a >= 10000000 ? 0 : 1)}M';
  if (a >= 1000) return '${(v / 1000).toStringAsFixed(a >= 10000 ? 0 : 1)}K';
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}

/// Rounds a maximum up to a round axis top (2, 2.5, 5 or 10 times a power of 10).
double _niceCeiling(double raw) {
  if (raw <= 0) return 1;
  final exp = (math.log(raw) / math.ln10).floor();
  final pow10 = math.pow(10, exp).toDouble();
  final f = raw / pow10;
  final nice = f <= 1 ? 1.0 : f <= 2 ? 2.0 : f <= 2.5 ? 2.5 : f <= 5 ? 5.0 : 10.0;
  return nice * pow10;
}

// ---------------------------------------------------------------------
// Card shell
// ---------------------------------------------------------------------

/// White card with a title, a legend built from the series, and an empty
/// message. Put a chart in [chart].
class ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<ChartSeries> series;
  final Widget chart;
  final double height;
  final bool isEmpty;
  final String emptyMessage;
  final Widget? trailing;

  const ChartCard({
    super.key,
    required this.title,
    required this.series,
    required this.chart,
    this.subtitle,
    this.height = 220,
    this.isEmpty = false,
    this.emptyMessage = 'Nothing to show for this range yet.',
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (series.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [for (final s in series) _LegendDot(color: s.color, label: s.label)],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: height,
            width: double.infinity,
            child: isEmpty
                ? Center(
                    child: Text(emptyMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  )
                : chart,
          ),
        ],
      ),
    );
  }
}

/// A coloured square with a series name, used in the legend.
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2.5)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Grouped bar chart
// ---------------------------------------------------------------------

/// Vertical bars grouped per x label. Works with one or more series.
class GroupedBarChart extends StatelessWidget {
  final List<String> labels;
  final List<ChartSeries> series;

  /// Formats the y-axis ticks. Defaults to [compactNumber]; pass a
  /// currency formatter for money charts.
  final String Function(double)? formatValue;

  const GroupedBarChart({
    super.key,
    required this.labels,
    required this.series,
    this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarPainter(
        labels: labels,
        series: series,
        format: formatValue ?? compactNumber,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Paints the grid, bars and labels for [GroupedBarChart].
class _BarPainter extends CustomPainter {
  final List<String> labels;
  final List<ChartSeries> series;
  final String Function(double) format;

  _BarPainter({required this.labels, required this.series, required this.format});

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || series.isEmpty) return;

    var rawMax = 0.0;
    for (final s in series) {
      for (var i = 0; i < labels.length; i++) {
        rawMax = math.max(rawMax, s.at(i));
      }
    }
    final maxY = _niceCeiling(rawMax);

    const xAxisHeight = 22.0;
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;

    // Y labels come first: their width sets where the plot starts.
    const ticks = 4;
    final tickPainters = <TextPainter>[];
    for (var t = 0; t <= ticks; t++) {
      tickPainters.add(_text(format(maxY * t / ticks), 10, AppColors.textMuted));
    }
    final yAxisWidth =
        tickPainters.map((p) => p.width).reduce(math.max) + 8;

    final plot = Rect.fromLTWH(
      yAxisWidth,
      6,
      size.width - yAxisWidth,
      size.height - xAxisHeight - 6,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    // Gridlines + y labels.
    for (var t = 0; t <= ticks; t++) {
      final y = plot.bottom - plot.height * t / ticks;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final tp = tickPainters[t];
      tp.paint(canvas, Offset(plot.left - tp.width - 8, y - tp.height / 2));
    }

    final slot = plot.width / labels.length;
    // Bars in a group share the slot, leaving a gap between groups.
    final groupWidth = slot * 0.62;
    final barWidth = groupWidth / series.length;

    for (var i = 0; i < labels.length; i++) {
      final slotLeft = plot.left + slot * i;
      final groupLeft = slotLeft + (slot - groupWidth) / 2;

      for (var s = 0; s < series.length; s++) {
        final v = series[s].at(i);
        // Small values get at least a 2px bar so they stay visible.
        final h = maxY <= 0 ? 0.0 : (v / maxY) * plot.height;
        final barH = v > 0 ? math.max(h, 2.0) : 0.0;
        if (barH <= 0) continue;

        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(
            groupLeft + barWidth * s + barWidth * 0.1,
            plot.bottom - barH,
            barWidth * 0.8,
            barH,
          ),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(rect, Paint()..color = series[s].color);
      }

      // X label, dropped when the slot is too narrow to fit it.
      final lp = _text(labels[i], 10, AppColors.textMuted);
      if (lp.width <= slot - 2) {
        lp.paint(canvas, Offset(slotLeft + (slot - lp.width) / 2, plot.bottom + 6));
      }
    }

    // Baseline is drawn last so it stays on top of the bars.
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()
        ..color = AppColors.textMuted.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.labels != labels || old.series != series;
}

// ---------------------------------------------------------------------
// Trend line
// ---------------------------------------------------------------------

/// Line chart with a light fill under the line. Good for showing a trend.
class TrendLineChart extends StatelessWidget {
  final List<String> labels;
  final List<ChartSeries> series;
  final String Function(double)? formatValue;

  const TrendLineChart({
    super.key,
    required this.labels,
    required this.series,
    this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePainter(
        labels: labels,
        series: series,
        format: formatValue ?? compactNumber,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Paints the grid, lines, points and labels for [TrendLineChart].
class _LinePainter extends CustomPainter {
  final List<String> labels;
  final List<ChartSeries> series;
  final String Function(double) format;

  _LinePainter({required this.labels, required this.series, required this.format});

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || series.isEmpty) return;

    var rawMax = 0.0;
    for (final s in series) {
      for (var i = 0; i < labels.length; i++) {
        rawMax = math.max(rawMax, s.at(i));
      }
    }
    final maxY = _niceCeiling(rawMax);

    const xAxisHeight = 22.0;
    const ticks = 4;
    final tickPainters = <TextPainter>[
      for (var t = 0; t <= ticks; t++) _text(format(maxY * t / ticks), 10, AppColors.textMuted)
    ];
    final yAxisWidth = tickPainters.map((p) => p.width).reduce(math.max) + 8;

    final plot = Rect.fromLTWH(
      yAxisWidth,
      6,
      size.width - yAxisWidth,
      size.height - xAxisHeight - 6,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var t = 0; t <= ticks; t++) {
      final y = plot.bottom - plot.height * t / ticks;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final tp = tickPainters[t];
      tp.paint(canvas, Offset(plot.left - tp.width - 8, y - tp.height / 2));
    }

    // One point alone is centred (step 0 avoids dividing by zero).
    final step = labels.length == 1 ? 0.0 : plot.width / (labels.length - 1);
    double xFor(int i) => labels.length == 1 ? plot.center.dx : plot.left + step * i;
    double yFor(double v) => maxY <= 0 ? plot.bottom : plot.bottom - (v / maxY) * plot.height;

    for (final s in series) {
      final pts = <Offset>[
        for (var i = 0; i < labels.length; i++) Offset(xFor(i), yFor(s.at(i)))
      ];

      if (pts.length > 1) {
        final fill = Path()..moveTo(pts.first.dx, plot.bottom);
        for (final p in pts) {
          fill.lineTo(p.dx, p.dy);
        }
        fill
          ..lineTo(pts.last.dx, plot.bottom)
          ..close();
        canvas.drawPath(fill, Paint()..color = s.color.withValues(alpha: 0.12));

        final line = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (final p in pts.skip(1)) {
          line.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
          line,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }

      for (final p in pts) {
        canvas.drawCircle(p, 3.2, Paint()..color = Colors.white);
        canvas.drawCircle(
          p,
          3.2,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    for (var i = 0; i < labels.length; i++) {
      final lp = _text(labels[i], 10, AppColors.textMuted);
      final x = xFor(i) - lp.width / 2;
      // Keep the end labels inside the card.
      final clamped = x.clamp(plot.left - 4, plot.right - lp.width + 4);
      if (step == 0 || lp.width <= step + 6) {
        lp.paint(canvas, Offset(clamped, plot.bottom + 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.labels != labels || old.series != series;
}

// ---------------------------------------------------------------------
// Donut
// ---------------------------------------------------------------------

/// One slice of a [DonutChart].
class DonutSlice {
  final String label;
  final double value;
  final Color color;
  const DonutSlice(this.label, this.value, this.color);
}

/// Donut for status breakdowns (for example paid vs overdue). Shows the
/// total in the middle and a list of slices beside it.
class DonutChart extends StatelessWidget {
  final List<DonutSlice> slices;
  final String centerLabel;

  const DonutChart({super.key, required this.slices, this.centerLabel = 'Total'});

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (s, e) => s + e.value);
    return Row(
      children: [
        SizedBox(
          width: 150,
          height: double.infinity,
          child: CustomPaint(
            painter: _DonutPainter(slices: slices, total: total),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(compactNumber(total),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  Text(centerLabel,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in slices)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                              color: s.color, borderRadius: BorderRadius.circular(2.5)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(s.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          total <= 0
                              ? '0'
                              : '${s.value.toStringAsFixed(0)}  ·  '
                                  '${(s.value / total * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints the ring for [DonutChart]; a grey ring when the total is zero.
class _DonutPainter extends CustomPainter {
  final List<DonutSlice> slices;
  final double total;
  _DonutPainter({required this.slices, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2 - 4;
    if (radius <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final thickness = radius * 0.34;
    final rect = Rect.fromCircle(center: center, radius: radius - thickness / 2);

    if (total <= 0) {
      canvas.drawCircle(
        center,
        radius - thickness / 2,
        Paint()
          ..color = AppColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness,
      );
      return;
    }

    var start = -math.pi / 2;
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = (s.value / total) * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        // Tiny gap between slices so neighbours stay distinct.
        math.max(sweep - 0.012, 0.004),
        false,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.total != total;
}

// ---------------------------------------------------------------------

/// Builds a laid-out text painter for axis labels.
TextPainter _text(String s, double size, Color color) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color)),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp;
}
