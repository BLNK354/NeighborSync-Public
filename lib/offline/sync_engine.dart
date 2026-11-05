import 'connectivity_service.dart';
import 'offline_repository.dart';
import '../services/supabase_service.dart';

/// Watches connectivity and replays queued offline writes as soon as the
/// app comes back online. Call [start] once, after SupabaseService.init,
/// from main().
class SyncEngine {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  bool _started = false;
  bool _wasOnline = true;

  void start() {
    if (_started) return;
    _started = true;
    _wasOnline = ConnectivityService.instance.isOnline.value;
    ConnectivityService.instance.isOnline.addListener(_handleChange);
    // Also try at startup for writes left queued by an earlier session.
    if (_wasOnline) _replay();
  }

  void _handleChange() {
    final isOnline = ConnectivityService.instance.isOnline.value;
    if (isOnline && !_wasOnline) {
      _replay();
    }
    _wasOnline = isOnline;
  }

  Future<void> _replay() async {
    try {
      await OfflineRepository.instance.replaySyncQueue(SupabaseService.instance.client);
    } catch (_) {
      // A failed replay leaves the queue for the next reconnect.
    }
  }
}
