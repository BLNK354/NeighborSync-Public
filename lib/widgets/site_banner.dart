import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/branding.dart';
import '../core/safe_state.dart';

/// Strip at the top of every screen for the site announcement and the
/// maintenance notice. Added once in MaterialApp.builder.
class SiteBanner extends StatefulWidget {
  const SiteBanner({super.key});

  // Static so a dismissal survives route changes (the State is rebuilt).
  // A different message shows again.
  static String? _dismissedMessage;

  @override
  State<SiteBanner> createState() => _SiteBannerState();
}

class _SiteBannerState extends State<SiteBanner> with SafeSetState<SiteBanner> {
  StreamSubscription<AuthState>? _auth;

  @override
  void initState() {
    super.initState();
    AppBranding.instance.addListener(_onChange);
    // The maintenance notice only shows when signed in.
    _auth = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => _onChange(), onError: (_) {});
  }

  @override
  void dispose() {
    AppBranding.instance.removeListener(_onChange);
    _auth?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final b = AppBranding.instance;
    // Maintenance notice cannot be dismissed.
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    final maintenance = b.maintenanceMode && signedIn;
    final notice = _announcement(b);
    if (!maintenance) return notice ?? const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          type: MaterialType.transparency,
          child: Container(
            width: double.infinity,
            color: const Color(0xFF8A6300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(children: [
              Icon(Icons.construction_outlined, size: 18, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Maintenance mode is ON. Residents, tenants and guests cannot sign in '
                  'until it is turned off in Settings > General.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
        if (notice != null) notice,
      ],
    );
  }

  /// The dismissible announcement bar, or null when there is nothing to show.
  Widget? _announcement(AppBranding b) {
    final msg = b.bannerMessage.trim();
    if (!b.bannerEnabled || msg.isEmpty) return null;
    if (SiteBanner._dismissedMessage == msg) return null;

    final (Color bg, Color fg, IconData icon) = switch (b.bannerLevel) {
      'critical' => (const Color(0xFFA82F2F), Colors.white, Icons.error_outline),
      'warning' => (const Color(0xFF8A6300), Colors.white, Icons.warning_amber_outlined),
      _ => (const Color(0xFF0C5C84), Colors.white, Icons.campaign_outlined),
    };

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: double.infinity,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg)),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: () => setState(() => SiteBanner._dismissedMessage = msg),
              child: Icon(Icons.close, size: 18, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
