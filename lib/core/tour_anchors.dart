/// Where the guided tour is allowed to point.
///
/// Anchors are whole regions (menu, bell, avatar, tab bar), not single nav
/// items, because items vary by role, folded sections and screen width.
///
/// Each [TourAnchor] owns a private key and registers itself, so two
/// shells mounted at once can share an id without a duplicate-key error.
/// [rectOf] returns the first one that is mounted and laid out.
library;

import 'package:flutter/material.dart';
import 'safe_state.dart';

/// Stable ids. Strings would drift between the step list and the shells,
/// so they live here once and both sides import them.
class TourAnchorId {
  /// The officer/resident sidebar (desktop) or the drawer button (phone).
  static const nav = 'nav';

  /// The resident phone's bottom tab bar.
  static const tabs = 'tabs';

  /// Notifications bell. Present in all four shells.
  static const bell = 'bell';

  /// Profile avatar. Present in all four shells.
  static const avatar = 'avatar';

  /// Global search. Officer desktop only.
  static const search = 'search';

  /// Phase label / switcher. Officer shells only.
  static const phase = 'phase';

  /// The ? button beside the bell that opens the "How do I…?" guides.
  static const help = 'help';

  /// The page body (everything but the menu and top bar), registered once
  /// in `PortalBackground`. Steps that open a screen point here.
  static const page = 'page';

  // Specific controls used by the per-screen tips. They may be absent
  // (e.g. Send Proof only shows on an unpaid bill); the tip then lights
  // the page instead.
  static const payQr = 'pay_qr';
  static const sendProof = 'send_proof';
  static const registerVisitor = 'register_visitor';
  static const fileComplaint = 'file_complaint';
  static const selectAddress = 'select_address';
  static const ownershipProof = 'ownership_proof';
  static const pendingTab = 'pending_tab';
  static const scanPass = 'scan_pass';
  static const paymentsTab = 'payments_tab';
  static const channelsTab = 'channels_tab';
  static const phasesTab = 'phases_tab';
}

/// Registry of live anchors, keyed by id. Holds a set per id because two
/// shells can be mounted during a page transition.
class TourAnchors {
  TourAnchors._();

  static final Map<String, Set<_TourAnchorState>> _live = {};

  static void _register(String id, _TourAnchorState state) =>
      _live.putIfAbsent(id, () => <_TourAnchorState>{}).add(state);

  static void _unregister(String id, _TourAnchorState state) {
    final set = _live[id];
    if (set == null) return;
    set.remove(state);
    if (set.isEmpty) _live.remove(id);
  }

  /// The anchor's rectangle in global coordinates, or null when it is not
  /// on screen. Null is normal; the tour then shows a plain centred card.
  static Rect? rectOf(String id) {
    final set = _live[id];
    if (set == null) return null;
    for (final state in set) {
      final rect = state.globalRect;
      if (rect != null) return rect;
    }
    return null;
  }

  /// Whether anything with this id is currently on screen.
  static bool isVisible(String id) => rectOf(id) != null;
}

/// Marks a region the tour may highlight. Renders its child unchanged, so
/// wrapping a widget in one does not affect layout.
class TourAnchor extends StatefulWidget {
  final String id;
  final Widget child;

  const TourAnchor({super.key, required this.id, required this.child});

  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> with SafeSetState<TourAnchor> {
  /// Private to this instance so shared anchor ids never collide.
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    TourAnchors._register(widget.id, this);
  }

  @override
  void didUpdateWidget(TourAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      TourAnchors._unregister(old.id, this);
      TourAnchors._register(widget.id, this);
    }
  }

  // Leave the registry on deactivate (not just dispose): an inactive
  // element is still `mounted`, and looking up its render object throws.
  // Rejoin if the element is reinserted.
  @override
  void deactivate() {
    TourAnchors._unregister(widget.id, this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    TourAnchors._register(widget.id, this);
  }

  @override
  void dispose() {
    TourAnchors._unregister(widget.id, this);
    super.dispose();
  }

  /// This anchor's box on screen, or null if it is not laid out yet.
  Rect? get globalRect {
    if (!mounted) return null;
    final ctx = _key.currentContext;
    if (ctx == null) return null;
    // A lookup must never throw into the overlay's build.
    final RenderObject? box;
    try {
      box = ctx.findRenderObject();
    } catch (_) {
      return null;
    }
    // Reading `size` before layout throws, so check `hasSize` first.
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    if (size.isEmpty) return null;
    return Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}
