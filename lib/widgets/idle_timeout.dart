/// Signs the user out after a period with no interaction, on every platform.
///
/// It also signs this device out if another device has signed in
/// ([SupabaseService.signOutOtherDevices] removes the other `login_sessions` rows).
///
/// Wrap it around the whole app once. It watches pointer and key events,
/// so screens need nothing extra.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/session_policy.dart';
import '../services/supabase_service.dart';
import '../core/safe_state.dart';

class IdleTimeout extends StatefulWidget {
  final Widget child;

  /// Called when the session ends, so the app can go to login and say why.
  /// [reason] is `timeout` or `kicked`.
  final void Function(String reason) onTimeout;

  const IdleTimeout({super.key, required this.child, required this.onTimeout});

  @override
  State<IdleTimeout> createState() => _IdleTimeoutState();
}

class _IdleTimeoutState extends State<IdleTimeout> with SafeSetState<IdleTimeout>, WidgetsBindingObserver {
  Timer? _timer;
  DateTime _lastActivity = DateTime.now();
  DateTime? _backgroundedAt;
  bool _expiring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Duration get _limit => SessionPolicy.idleFor(SupabaseService.cachedRole);

  void _restart() {
    _lastActivity = DateTime.now();
    _timer?.cancel();
    // Short repeating tick, not one long timer: a long timer can be lost when
    // the app is suspended. It also spots a sign-in from another device quickly.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  /// Runs every tick: signs out if kicked by another device or idle too long.
  Future<void> _check() async {
    if (_expiring) return;
    if (SupabaseService.instance.client.auth.currentSession == null) return;

    // Another device signed in and took the only allowed session.
    final stillActive =
        await SupabaseService.instance.isCurrentLoginSessionStillActive();
    if (!stillActive) {
      await _expire('kicked');
      return;
    }

    if (DateTime.now().difference(_lastActivity) >= _limit) {
      await _expire('timeout');
    }
  }

  /// Signs out once and tells the app why via [IdleTimeout.onTimeout].
  Future<void> _expire(String reason) async {
    if (_expiring) return;
    _expiring = true;
    _timer?.cancel();
    try {
      await SupabaseService.instance.signOut();
    } catch (_) {
      // A failed server sign-out is fine; the app still goes to login.
    }
    if (mounted) widget.onTimeout(reason);
  }

  void _touch([_]) {
    // Only records the time; the tick does the comparing.
    _lastActivity = DateTime.now();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final away = _backgroundedAt == null
          ? Duration.zero
          : DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      // Time in the background counts as idle, except a brief switch away.
      if (away > SessionPolicy.resumeGrace &&
          DateTime.now().difference(_lastActivity) >= _limit) {
        _expire('timeout');
      } else if (away <= SessionPolicy.resumeGrace) {
        _touch();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _touch,
      onPointerMove: _touch,
      onPointerSignal: _touch,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, __) {
          _touch();
          return KeyEventResult.ignored;
        },
        child: widget.child,
      ),
    );
  }
}
