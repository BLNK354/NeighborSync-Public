/// Pull-to-refresh plumbing.
///
/// Each screen registers its reload from `initState` with
/// `RefreshBus.bind(this, _load);`. Pull-to-refresh then runs them.
library;

import 'package:flutter/widgets.dart';

/// A screen's reload function.
typedef RefreshHandler = Future<void> Function();

/// One screen's reload, tied to its State so dead screens can be skipped.
class _Registration {
  final State state;
  final RefreshHandler handler;
  const _Registration(this.state, this.handler);
}

/// Keeps a list of screens' reloads and runs them on refresh.
///
/// Holds many screens at once so a pushed form does not replace the screen
/// under it. Unmounted screens are skipped, so no `unbind` is needed.
/// [run] reloads every live screen, including hidden tabs.
class RefreshBus {
  RefreshBus._();

  static final List<_Registration> _entries = <_Registration>[];

  /// Called from a screen's `initState`:
  /// `RefreshBus.bind(this, _load);`
  static void bind(State state, RefreshHandler handler) {
    _entries.removeWhere((r) => identical(r.state, state));
    _entries.add(_Registration(state, handler));
    // Keep at most 32 entries; drop unmounted ones first.
    if (_entries.length > 32) {
      _entries.removeWhere((r) => !r.state.mounted);
      while (_entries.length > 32) {
        _entries.removeAt(0);
      }
    }
  }

  /// Reloads every screen that is currently on screen.
  ///
  /// Never throws, or the refresh spinner would stay stuck. One failing
  /// screen does not stop the others.
  static Future<void> run() async {
    _entries.removeWhere((r) => !r.state.mounted);
    if (_entries.isEmpty) return;

    // Copy first: a handler may bind again while we loop.
    final live = List<_Registration>.from(_entries);
    await Future.wait(live.map((r) async {
      if (!r.state.mounted) return;
      try {
        await r.handler();
      } catch (e, st) {
        debugPrint('Refresh failed for ${r.state.runtimeType}: $e\n$st');
      }
    }));
  }

  /// Clears all registrations. For tests only.
  @visibleForTesting
  static void reset() => _entries.clear();
}
