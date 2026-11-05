import 'package:flutter/material.dart';

/// Small layout helpers that avoid overflow on narrow screens.

/// A row of buttons or chips that wraps onto a second line when it runs
/// out of room.
///
/// Not for rows with a search field; use `Row` + `Expanded` so it shrinks.
class ActionButtonBar extends StatelessWidget {
  final List<Widget> children;
  final WrapAlignment alignment;
  final double spacing;
  final double runSpacing;
  const ActionButtonBar({
    super.key,
    required this.children,
    this.alignment = WrapAlignment.end,
    this.spacing = 10,
    this.runSpacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: spacing,
      runSpacing: runSpacing,
      children: children,
    );
  }
}

/// Stat cards in one row, or a 2-column grid when narrower than [breakpoint].
class ResponsiveStatRow extends StatelessWidget {
  final List<Widget> cards;
  final double breakpoint;
  final double spacing;
  const ResponsiveStatRow({
    super.key,
    required this.cards,
    this.breakpoint = 560,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final c in cards)
              SizedBox(width: (constraints.maxWidth - spacing) / 2, child: c),
          ],
        );
      },
    );
  }
}

/// Title on the left and actions on the right. Under [breakpoint] the
/// actions drop below the title and wrap.
class TitleActionRow extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;
  final double breakpoint;
  const TitleActionRow({
    super.key,
    required this.title,
    required this.actions,
    this.breakpoint = 480,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 10),
              ActionButtonBar(children: actions),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 10),
            ActionButtonBar(alignment: WrapAlignment.start, children: actions),
          ],
        );
      },
    );
  }
}

/// Text for a stat card that cuts off with "..." instead of wrapping.
class SafeStatText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int maxLines;
  const SafeStatText(this.text, {super.key, required this.style, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}
