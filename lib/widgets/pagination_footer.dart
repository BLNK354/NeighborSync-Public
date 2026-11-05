/// Page footer for long lists: Previous / Next and "Page X of Y".
/// Paging is done on the loaded list, so search and filters cover all pages.
library;

import 'package:flutter/material.dart';

/// Rows per page on every list.
const int kPageSize = 10;

/// Number of pages for [total] rows; never less than 1.
int pageCountFor(int total, {int size = kPageSize}) =>
    total <= 0 ? 1 : (total + size - 1) ~/ size;

/// The slice of [rows] on [page] (1-based).
List<T> pageSlice<T>(List<T> rows, int page, {int size = kPageSize}) {
  // Clamp the page: a filter can shrink the list while on a later page.
  final last = pageCountFor(rows.length, size: size);
  if (page > last) page = last;
  if (page < 1) page = 1;
  final start = (page - 1) * size;
  if (start >= rows.length) return const [];
  final end = (start + size).clamp(0, rows.length);
  return rows.sublist(start, end);
}

/// Previous / Next buttons with a "Page X of Y" label.
class PaginationFooter extends StatelessWidget {
  /// 1-based current page.
  final int page;

  /// Total page count (use [pageCountFor]).
  final int pageCount;

  /// Called with the new page. The caller owns the state; this widget
  /// only renders.
  final ValueChanged<int> onPageChanged;

  const PaginationFooter({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous page',
          onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left, size: 20),
          visualDensity: VisualDensity.compact,
        ),
        Text(
          'Page $page of $pageCount',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        IconButton(
          tooltip: 'Next page',
          onPressed: page < pageCount ? () => onPageChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right, size: 20),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// The footer for [total] rows, or nothing when one page is enough.
Widget pagerFor(int total, int page, ValueChanged<int> onPageChanged,
    {int size = kPageSize}) {
  final pages = pageCountFor(total, size: size);
  if (pages <= 1) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: PaginationFooter(
      page: page > pages ? pages : page,
      pageCount: pages,
      onPageChanged: onPageChanged,
    ),
  );
}
