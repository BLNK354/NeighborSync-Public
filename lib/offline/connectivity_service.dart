import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Tells the app whether the device is online. Watch `isOnline` to choose
/// Supabase or the local cache.
///
/// It only shows that a network exists, not that Supabase is reachable, so
/// still fall back to offline on a real Supabase error.
class ConnectivityService {
  ConnectivityService._internal() {
    // onError is needed or stream errors go uncaught.
    _sub = Connectivity()
        .onConnectivityChanged
        .listen(_handleChange, onError: (_) {});
    // Read the current state once at startup.
    Connectivity().checkConnectivity().then(_handleChange).catchError((_) {});
  }

  static final ConnectivityService instance = ConnectivityService._internal();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _sub;

  void _handleChange(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (isOnline.value != online) {
      isOnline.value = online;
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}
