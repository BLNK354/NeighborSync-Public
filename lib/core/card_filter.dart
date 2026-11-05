import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Passes a filter from a dashboard card to a list screen.
/// The card calls [request] before navigating; the list calls [take] in
/// initState. The value must be what that screen's own stat card would set.
class CardFilter {
  CardFilter._();

  static ({String screen, String value, DateTime at})? _pending;

  /// Remembers the filter [value] for [screen] to pick up.
  static void request(String screen, String value) =>
      _pending = (screen: screen, value: value, at: DateTime.now());

  /// The filter waiting for [screen], used once. Ignored after 20 seconds
  /// so an old request cannot narrow a later visit.
  static String? take(String screen) {
    final p = _pending;
    if (p == null || p.screen != screen) return null;
    _pending = null;
    if (DateTime.now().difference(p.at) > const Duration(seconds: 20)) {
      return null;
    }
    return p.value;
  }
}

/// Navigate to [route] with [screen]'s list filtered to [value].
void goFiltered(
    BuildContext context, String route, String screen, String value) {
  CardFilter.request(screen, value);
  context.go(route);
}
