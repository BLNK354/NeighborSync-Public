import 'package:flutter/material.dart';
import '../core/branding.dart';
import '../core/refresh_bus.dart';
import '../core/tour_anchors.dart';

/// Wraps [child] with the portal background set in the CMS: a photo, or
/// else the chosen colour. Every app shell uses it and it updates live.
///
/// Also holds the app's one pull-to-refresh. It catches scrolls from any
/// descendant; [RefreshBus] decides which reload runs.
class PortalBackground extends StatelessWidget {
  final Widget child;
  const PortalBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TourAnchor(
      id: TourAnchorId.page,
      child: RefreshIndicator(
        onRefresh: RefreshBus.run,
        child: _background(context),
      ),
    );
  }

  Widget _background(BuildContext context) {
    return AnimatedBuilder(
      animation: AppBranding.instance,
      builder: (context, _) {
        // Use usePortalPhoto, not "a photo exists": a Colour section keeps
        // its uploaded photo on file but must not show it.
        final img = AppBranding.instance.portalBgImageUrl;
        if (AppBranding.instance.usePortalPhoto) {
          // A white scrim over the photo keeps dark text readable.
          return Stack(
            children: [
              // Hidden from screen readers on purpose: it is decoration.
              Positioned.fill(
                child: ExcludeSemantics(
                  child: Image.network(img!, fit: BoxFit.cover),
                ),
              ),
              Positioned.fill(child: Container(color: Colors.white.withValues(alpha: 0.85))),
              child,
            ],
          );
        }
        return Container(
          width: double.infinity,
          color: AppBranding.instance.portalBgColor,
          child: child,
        );
      },
    );
  }
}
