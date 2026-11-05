/// The first-run guided tour: a dimmed screen, a spotlight on the region
/// being talked about, and a card explaining it. The same overlay also shows
/// first-visit screen tips and "How do I…?" help guides.
///
/// Mounted once in `MaterialApp.builder`, so it covers the whole window,
/// including the sidebar, top bar and tabs.
/// That is above the Navigator: `context.go` / `context.push` throw in this
/// file, so always navigate through the `onNavigate` callback.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/branding.dart';
import '../core/screen_tips.dart';
import '../core/tour_anchors.dart';
import '../core/tour_steps.dart';
import '../core/user_preferences.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'responsive_officer_shell.dart' show kMobileBreakpoint;
import '../core/safe_state.dart';
import '../core/stored_file.dart';

/// Bumping this re-runs the tour for everyone, once.
/// The seen flag is stored per account, not per device.
const int kTourVersion = 2;

/// Preference key holding the tour version this account has seen.
const String _seenKey = 'tour_seen_version';

/// Screens whose first-visit tips have been shown, as a list of
/// [tipKeyFor] keys. Stored beside the tour flag, per account.
const String _tipsSeenKey = 'tips_seen';

/// Lets Settings re-run the tour without reaching into the host's state.
class TourController {
  TourController._();

  static final ValueNotifier<int> _replayRequests = ValueNotifier(0);

  /// A "How do I…?" guide the reader picked from the help menu. A fresh
  /// list each time, so picking the same guide twice still notifies.
  static final ValueNotifier<List<TourStep>?> _guideRequests =
      ValueNotifier(null);

  /// The tab a tabbed screen (Finance, Community Concern, Announcements &
  /// Events) is showing. Those screens switch tabs inside one route, so the
  /// URL alone cannot tell the tips which tab is up -- the screen reports it.
  static final ValueNotifier<int> _tabChanges = ValueNotifier(0);
  static String? _tabRoute;
  static String? _tabKey;

  /// Called by a tabbed screen on open and on every tab switch. The first
  /// tab keeps the plain route as its tip key; later tabs add `#name`.
  static void tabShown(String route, int index, String tabName) {
    _tabRoute = route;
    _tabKey = index == 0 ? route : '$route#${tabName.toLowerCase()}';
    _tabChanges.value++;
  }

  /// Runs one help guide now. Called by the help menu, which lives below
  /// the Navigator; the host runs it and navigates for it.
  static void runGuide(List<TourStep> steps) {
    _guideRequests.value = List<TourStep>.of(steps);
  }

  /// Starts the tour again immediately, and clears the stored flag so the
  /// request survives a reload.
  static Future<void> replay() async {
    final profile = await SupabaseService.instance.getMyProfile();
    final id = profile?['id'] as int?;
    if (id != null) {
      // Clears the keys, so "seen then reset" looks the same as "never seen".
      try {
        // Replaying brings the screen tips back as well.
        await patchMyPreferences(id, {_seenKey: null, _tipsSeenKey: null});
      } catch (_) {
        // A failed write must not stop the replay the person just asked for.
      }
    }
    _replayRequests.value++;
  }
}

/// Wraps the app and decides when to show the tour, a screen's tips or a
/// help guide on top of it.
class GuidedTourHost extends StatefulWidget {
  final Widget child;

  /// Opens a route. Supplied by `main.dart`, because `context.go` throws
  /// above the Navigator.
  final void Function(String route)? onNavigate;

  /// Where the reader was when the tour started, so it can put them back.
  final String Function()? currentLocation;

  /// Fires when the current screen changes (the router's delegate). This is
  /// what triggers a screen's first-visit tips.
  final Listenable? locationChanges;

  const GuidedTourHost({
    super.key,
    required this.child,
    this.onNavigate,
    this.currentLocation,
    this.locationChanges,
  });

  @override
  State<GuidedTourHost> createState() => _GuidedTourHostState();
}

class _GuidedTourHostState extends State<GuidedTourHost> with SafeSetState<GuidedTourHost> {
  List<TourStep> _steps = const [];
  int _index = 0;
  bool _visible = false;

  /// Guards against re-checking on every auth event for a session that has
  /// already been answered. Reset on sign-out.
  bool _checked = false;

  /// Set by a replay request and consumed by _check. Must stay set across
  /// reschedules: a token refresh also calls _scheduleCheck, and without this
  /// it would replace the replay's check and the tour would never open.
  bool _forceNextCheck = false;
  StreamSubscription<dynamic>? _authSub;
  Timer? _retry;
  int _attempts = 0;

  /// Where the reader was before the tour started walking them around.
  String? _returnTo;

  /// Non-null while the cards on screen are one screen's first-visit tips
  /// rather than the tour. Holds that screen's key, recorded as seen when
  /// the tips close.
  String? _tipKey;

  /// True while a "How do I…?" guide is running. It ends on "Got it", records
  /// nothing, and leaves the reader on the screen it brought them to.
  bool _guide = false;

  /// Tips wait until the first-run tour has been answered one way or the
  /// other, so they cannot open on top of it or just before it.
  bool _tourSettled = false;

  /// Keys whose tips have been shown. Kept here so a route change needs no
  /// round trip to decide there is nothing to show.
  Set<String> _tipsSeen = {};
  Timer? _tipTimer;

  /// Rebuilds the overlay while it is up, so the spotlight finds controls
  /// that appear after the screen finishes loading.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    TourController._replayRequests.addListener(_onReplayRequested);
    widget.locationChanges?.addListener(_onLocationChanged);
    TourController._guideRequests.addListener(_onGuideRequested);
    TourController._tabChanges.addListener(_onLocationChanged);
    _authSub = SupabaseService.instance.client.auth.onAuthStateChange.listen(
      (_) {
        if (SupabaseService.instance.client.auth.currentUser == null) {
          _checked = false;
          _tourSettled = false;
          _tipsSeen = {};
          _tipTimer?.cancel();
          _attempts = 0;
          _retry?.cancel();
          if (_visible && mounted) setState(() => _visible = false);
        } else {
          _scheduleCheck();
        }
      },
      // Without a handler stream errors vanish silently. Here, just stop trying.
      onError: (_) => _checked = true,
    );
    _scheduleCheck();
  }

  @override
  void dispose() {
    TourController._replayRequests.removeListener(_onReplayRequested);
    widget.locationChanges?.removeListener(_onLocationChanged);
    TourController._guideRequests.removeListener(_onGuideRequested);
    TourController._tabChanges.removeListener(_onLocationChanged);
    _authSub?.cancel();
    _retry?.cancel();
    _tipTimer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _onGuideRequested() {
    final steps = TourController._guideRequests.value;
    if (steps == null || steps.isEmpty || !mounted) return;
    _tipTimer?.cancel();
    _show(steps, tipKey: null, guide: true);
    _openRouteFor(0);
  }

  void _onReplayRequested() {
    _checked = false;
    _tipsSeen = {};
    _attempts = 0;
    _scheduleCheck(force: true);
  }

  void _scheduleCheck({bool force = false}) {
    // Sticky: a later non-forced call must not cancel a pending replay.
    if (force) _forceNextCheck = true;
    _retry?.cancel();
    _retry = Timer(const Duration(milliseconds: 600), _check);
  }

  /// Starts the tour if a shell is on screen and this account has not seen
  /// the current version (or a replay was asked for).
  Future<void> _check() async {
    if (!mounted) return;
    if (_visible) {
      // Already on screen -- a replay request that arrives mid-tour is
      // satisfied by the tour that is running. Consume the flag so a later
      // auth event cannot re-open the tour after it closes.
      _forceNextCheck = false;
      return;
    }
    final bool force = _forceNextCheck;
    if (_checked && !force) return;

    // The bell exists only in the four shells, so it answers "is a shell on
    // screen?". This keeps the tour off the login and landing pages.
    // Retries are bounded: on the landing page the bell never appears.
    if (!TourAnchors.isVisible(TourAnchorId.bell)) {
      // _forceNextCheck stays set, so the retry keeps the replay's force.
      if (_attempts++ < 12) _scheduleCheck();
      return;
    }

    Map<String, dynamic>? profile;
    try {
      profile = await SupabaseService.instance.getMyProfile();
    } catch (_) {
      _checked = true;
      return;
    }
    if (!mounted || profile == null) {
      _checked = true;
      return;
    }

    final prefs = profile['preferences'];
    final seen = prefs is Map ? prefs[_seenKey] : null;
    final tips = prefs is Map ? prefs[_tipsSeenKey] : null;
    _tipsSeen = tips is List ? tips.map((e) => e.toString()).toSet() : {};
    if (!force && seen is int && seen >= kTourVersion) {
      _checked = true;
      _forceNextCheck = false;
      _tourSettled = true;
      // Whatever screen they signed in to may have tips of its own.
      _onLocationChanged();
      return;
    }

    final role =
        (profile['roles'] as Map<String, dynamic>?)?['name'] as String?;
    final status = profile['status'] as String?;
    final steps = tourFor(
      role: role ?? 'visitor',
      status: status ?? 'active',
      narrow: MediaQuery.of(context).size.width < kMobileBreakpoint,
      communityName: AppBranding.instance.communityName,
    );
    if (steps.isEmpty) {
      _checked = true;
      _tourSettled = true;
      return;
    }

    _returnTo = widget.currentLocation?.call();
    _tipTimer?.cancel();

    _show(steps, tipKey: null);
    _checked = true;
    _forceNextCheck = false;
    _openRouteFor(0);
  }

  /// Opens the screen a step is about, if it names one.
  /// `main.dart` should use `go`, not `push`, so the tour leaves no back stack;
  /// `_finish` returns the reader to where they started.
  void _openRouteFor(int i) {
    final route = _steps[i].route;
    if (route == null) return;
    widget.onNavigate?.call(route);
    // The new screen's anchors are not laid out until the next frame, so
    // recompute the spotlight after it rather than against the old page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible) setState(() {});
    });
  }

  /// Puts [steps] on screen as a tip set ([tipKey]), a [guide], or the tour
  /// (neither).
  void _show(List<TourStep> steps,
      {required String? tipKey, bool guide = false}) {
    setState(() {
      _steps = steps;
      _index = 0;
      _visible = true;
      _tipKey = tipKey;
      _guide = guide;
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted && _visible) setState(() {});
    });
  }

  // -------------------------------------------------------------------
  // First-visit screen tips
  // -------------------------------------------------------------------

  /// Runs when the screen or tab changes: closes a stale tip and queues the
  /// new screen's tips.
  void _onLocationChanged() {
    // A tip belongs to one screen, and the screen can change under the scrim
    // (browser Back, idle sign-out). Close it without recording it as seen,
    // so it is offered again on the next real visit.
    if (_visible && _tipKey != null && !_guide && _currentTipKey() != _tipKey) {
      _tick?.cancel();
      setState(() {
        _visible = false;
        _tipKey = null;
      });
    }
    // Screens the tour walks through do not count as first visits.
    if (_visible || !_tourSettled) return;
    _tipTimer?.cancel();
    // A short wait so the screen has built -- and so tapping quickly
    // through two screens only ever offers the second one's tips.
    _tipTimer = Timer(const Duration(milliseconds: 900), _maybeShowTips);
  }

  /// The tip key for what is on screen: the reported tab when the current
  /// route is a tabbed screen, otherwise the route itself.
  String? _currentTipKey() {
    final location = widget.currentLocation?.call();
    if (location == null) return null;
    final path = Uri.tryParse(location)?.path ?? location;
    final tabRoute = TourController._tabRoute;
    if (tabRoute != null && (path == tabRoute || tipKeyFor(path) == tabRoute)) {
      return TourController._tabKey;
    }
    return tipKeyFor(location);
  }

  /// Shows the current screen's tips if this account has not seen them yet.
  Future<void> _maybeShowTips() async {
    if (!mounted || _visible || !_tourSettled) return;
    if (SupabaseService.instance.client.auth.currentUser == null) return;
    // Same "is a shell on screen?" test as the tour.
    if (!TourAnchors.isVisible(TourAnchorId.bell)) return;

    final key = _currentTipKey();
    if (key == null || _tipsSeen.contains(key)) return;

    Map<String, dynamic>? profile;
    try {
      profile = await SupabaseService.instance.getMyProfile();
    } catch (_) {
      return;
    }
    if (!mounted || profile == null || _visible) return;
    // Pending accounts have their own short tour and can reach two screens;
    // tips about the full app would describe things they cannot use yet.
    if (profile['status'] == 'pending_verification') return;
    // The reader may have moved on while the profile loaded.
    if (_currentTipKey() != key) return;

    final role =
        (profile['roles'] as Map<String, dynamic>?)?['name'] as String? ?? '';
    final tips = screenTipsFor(key: key, role: role);
    if (tips.isEmpty) return;
    _show(tips, tipKey: key);
  }

  /// Closes the overlay and records what was seen, depending on what was
  /// showing: nothing for a guide, the tip key for tips, the version for the
  /// tour (which also returns the reader to where they started).
  Future<void> _finish() async {
    _tick?.cancel();
    final tipKey = _tipKey;
    final wasGuide = _guide;
    setState(() {
      _visible = false;
      _tipKey = null;
      _guide = false;
    });

    if (wasGuide) return;

    if (tipKey != null) {
      // A screen's tips: remembered, and the reader stays where they are.
      _tipsSeen.add(tipKey);
      try {
        final profile = await SupabaseService.instance.getMyProfile();
        final id = profile?['id'] as int?;
        if (id != null) {
          await patchMyPreferences(id, {_tipsSeenKey: _tipsSeen.toList()});
        }
      } catch (_) {
        // Best-effort: worst case the tips show once more next visit.
      }
      return;
    }
    _tourSettled = true;

    // Put the reader back where they were before the tour moved them.
    final back = _returnTo;
    _returnTo = null;
    if (back != null) widget.onNavigate?.call(back);

    try {
      final profile = await SupabaseService.instance.getMyProfile();
      final id = profile?['id'] as int?;
      if (id != null) await patchMyPreferences(id, {_seenKey: kTourVersion});
    } catch (_) {
      // Best-effort: the tour may run once more, but it must always close.
    }
  }

  void _next() {
    if (_index >= _steps.length - 1) {
      _finish();
    } else {
      setState(() => _index++);
      _openRouteFor(_index);
    }
  }

  void _back() {
    if (_index > 0) {
      setState(() => _index--);
      _openRouteFor(_index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _steps.isEmpty) return widget.child;
    return Stack(
      // Expand keeps the app's tight constraints; the default loose ones
      // could resize the page when the tour opens.
      fit: StackFit.expand,
      children: [
        // Scrolling moves anchors, so recompute the spotlight. Must wrap the
        // app, not the overlay: scroll notifications only reach ancestors.
        NotificationListener<ScrollNotification>(
          // Deferred to after the frame: setState during layout throws.
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _visible) setState(() {});
            });
            return false;
          },
          child: widget.child,
        ),
        Positioned.fill(
          child: _TourOverlay(
            isTip: _tipKey != null || _guide,
            step: _steps[_index],
            index: _index,
            total: _steps.length,
            onNext: _next,
            onBack: _back,
            onSkip: _finish,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// The overlay itself
// ---------------------------------------------------------------------

/// The dimmed layer, the spotlight and the card for one step.
class _TourOverlay extends StatefulWidget {
  /// A screen's first-visit tips rather than the tour: the last button
  /// reads "Got it", since there is no tour to be "Done" with.
  final bool isTip;
  final TourStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const _TourOverlay({
    required this.isTip,
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> with SafeSetState<_TourOverlay> {
  static const double _bubbleWidth = 340;

  /// Never narrower than this, whatever the measured viewport claims.
  static const double _kMinBubbleWidth = 240;
  static const double _gap = 14;

  /// Last rect seen for each anchor id. An anchor can report null for a frame
  /// while its screen reloads; without this the card jumps and its buttons
  /// move under the pointer. A fresh rect always wins over this one.
  final Map<String, Rect> _lastRects = {};

  /// The step the cache belongs to. Rects must not carry over to another
  /// step, or a tip could light where a control sat on a different screen.
  TourStep? _cacheStep;

  /// The window rectangle to spotlight for [step], or null for a centred card.
  Rect? _resolveTarget(TourStep step, Size size) {
    if (step.anchor == null) return null;
    if (!identical(_cacheStep, step)) {
      _lastRects.clear();
      _cacheStep = step;
    }
    final raw = TourAnchors.rectOf(step.anchor!);
    if (raw != null) {
      _lastRects[step.anchor!] = raw;
      return _clampToScreen(raw, size);
    }
    final cached = _lastRects[step.anchor!];
    if (cached != null) return _clampToScreen(cached, size);
    // A specific control that is not on screen -- Send Proof with no unpaid
    // bill, a tab hidden for this role -- falls back to lighting the page,
    // so a tip never points at empty space.
    if (step.anchor != TourAnchorId.page) {
      final page = TourAnchors.rectOf(TourAnchorId.page);
      if (page != null) return _clampToScreen(page, size);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // MediaQuery, not LayoutBuilder: anchors report window coordinates, and a
    // bad width renders an invisible card with no error in a release build.
    final size = MediaQuery.sizeOf(context);

    // Null is normal (no such control for this role or width): the step then
    // shows as a centred card.
    final target = _resolveTarget(widget.step, size);

    return Stack(
      // Every child is Positioned, so the Stack never sizes itself from a child.
      fit: StackFit.expand,
      children: [
        // Absorbs taps so the app underneath cannot be used during a step.
        // A tap here does nothing; only Next and Skip move on.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(
              painter: _SpotlightPainter(
                target: target,
                brand: AppBranding.instance.primaryColor,
              ),
            ),
          ),
        ),
        _positionedBubble(size, target),
      ],
    );
  }

  /// Keeps a spotlight inside the window, e.g. while a sidebar is animating.
  /// The explicit `double`s matter: `num.clamp` returns `num`, which
  /// `Rect.fromLTRB` refuses.
  Rect _clampToScreen(Rect r, Size size) {
    final double left = r.left.clamp(0.0, size.width).toDouble();
    final double top = r.top.clamp(0.0, size.height).toDouble();
    final double right = r.right.clamp(0.0, size.width).toDouble();
    final double bottom = r.bottom.clamp(0.0, size.height).toDouble();
    if (right <= left || bottom <= top) return Rect.zero;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Roughly how much room the card needs. Used only to decide whether an
  /// anchored placement would push it off-screen; the card's real height is
  /// never measured.
  static const double _assumedBubbleHeight = 150;

  /// True when the card fits above or below this target inside the window.
  /// Without this check a tall anchor pushes the card off the top of the screen.
  bool _fitsBeside(Size size, Rect target, bool below) {
    final double gap = _gapFor(target);
    return below
        ? size.height - target.bottom - gap >= _assumedBubbleHeight
        : target.top - gap >= _assumedBubbleHeight;
  }

  /// Clearance between the anchor and the card. Follows the spotlight's padding
  /// so the card never sits inside the lit area.
  double _gapFor(Rect target) => spotlightPad(target) + _gap;

  /// Places the card beside, below, above or centred, depending on the target.
  Widget _positionedBubble(Size size, Rect? target) {
    // A floor as well as a cap: a zero or negative width paints nothing in
    // a release build.
    final double available = size.width - 32;
    final double width = available < _kMinBubbleWidth
        ? _kMinBubbleWidth
        : (available < _bubbleWidth ? available : _bubbleWidth);
    final bubble = _bubble(width);

    final bool below =
        target == null ? false : target.center.dy < size.height / 2;
    final bool anchored =
        target != null && !target.isEmpty && _fitsBeside(size, target, below);

    // A tall anchor (the desktop sidebar) gets the card to its right.
    // Must stay before the `!anchored` return: a tall anchor never passes
    // _fitsBeside, so placed after it this branch would never run.
    if (target != null &&
        !target.isEmpty &&
        target.height >= size.height * 0.6) {
      final Rect rect = target;
      // +6 clears the ring's outer stroke on top of the spotlight pad.
      final double sideLeft = rect.right + _gapFor(rect) + 6;
      if (sideLeft + width <= size.width - 16) {
        final double top = (size.height - _assumedBubbleHeight) / 2;
        return Positioned(
          left: sideLeft,
          top: top < 24 ? 24 : top,
          child: bubble,
        );
      }
      // No room beside it, so centre the card as for a step with no anchor.
      final double centreTop = size.height * 0.28;
      return Positioned(
        left: _centredLeft(size, width),
        top: centreTop < 24 ? 24 : centreTop,
        child: bubble,
      );
    }

    if (!anchored) {
      // Explicit coordinates, not Positioned.fill + Center: a layout failure
      // paints nothing and reports nothing in a release build.
      // Sits at 28% because the card grows downward, so a long step stays on
      // a short window.
      final double left = _centredLeft(size, width);
      final double top = size.height * 0.28;
      return Positioned(
        left: left,
        top: top < 24 ? 24 : top,
        child: bubble,
      );
    }

    // Below the target when it sits in the upper half, above it otherwise, so
    // the card does not cover what it points at.
    // `anchored` already proves target is non-null here. clamp throws if its
    // upper bound falls below the lower, hence the maxLeft check first.
    final Rect rect = target;
    final double maxLeft = size.width - width - 16;
    final double left = maxLeft <= 16
        ? 16
        : (rect.center.dx - width / 2).clamp(16.0, maxLeft).toDouble();

    final double gap = _gapFor(rect);
    return Positioned(
      left: left,
      top: below ? rect.bottom + gap : null,
      bottom: below ? null : size.height - rect.top + gap,
      child: bubble,
    );
  }

  /// Horizontal position for a centred card, computed rather than measured.
  double _centredLeft(Size size, double width) {
    final double left = (size.width - width) / 2;
    return left < 16 ? 16 : left;
  }

  /// The card: title, body, optional guide button, step count and buttons.
  /// Do not add a `Spacer` or other flex child: on an unbounded axis it fails
  /// during layout, which paints nothing in a release build.
  Widget _bubble(double width) {
    final brand = AppBranding.instance.primaryColor;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      // Text with no Material ancestor gets Flutter's yellow double underline.
      // Transparent, so the Container keeps the card's colour and shadow.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.step.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: brand,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.step.body,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
            if (widget.step.offersGuide && _guideUrl != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    openStoredFile(context, publicUrl: _guideUrl).catchError((_) {}),
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: const Text('Open my guide (PDF)'),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.index + 1} of ${widget.total}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.index > 0)
                      TextButton(
                          onPressed: widget.onBack, child: const Text('Back')),
                    TextButton(
                      onPressed: widget.onSkip,
                      child: Text(
                        widget.index == widget.total - 1 ? 'Close' : 'Skip',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: widget.onNext,
                      child: Text(widget.index == widget.total - 1
                          ? (widget.isTip ? 'Got it' : 'Done')
                          : 'Next'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// How far the lit area extends beyond the anchor itself. Shared by the
/// painter and the card placement so they stay in step.
double spotlightPad(Rect target) => target.shortestSide < 72 ? 14 : 8;

/// Paints the dark scrim with a rounded hole and a ring around [target].
class _SpotlightPainter extends CustomPainter {
  final Rect? target;
  final Color brand;
  const _SpotlightPainter({required this.target, required this.brand});

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = const Color(0xB3000000);
    final full = Offset.zero & size;

    if (target == null || target!.isEmpty) {
      canvas.drawRect(full, scrim);
      return;
    }

    // Small anchors get a wider pad, so they read as lit rather than outlined.
    final double pad = spotlightPad(target!);
    final hole = RRect.fromRectAndRadius(
      target!.inflate(pad),
      Radius.circular(pad + 4),
    );

    // Even-odd fill: the window plus the hole, so the hole stays unpainted.
    // Draw nothing inside it; bands built with Path.combine came out black
    // over the control on the web renderer.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(full)
        ..addRRect(hole),
      scrim,
    );

    // One ring on the hole's edge: white for small controls, brand colour for
    // large regions, where a white frame is too loud.
    final bool small = target!.shortestSide < 72;
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = small ? 2.5 : 2
        ..color = small ? Colors.white : brand,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.target != target || old.brand != brand;
}

/// The signed-in person's own guide PDF, or null when none is uploaded.
String? get _guideUrl {
  final role = SupabaseService.cachedRole;
  return role == null ? null : AppBranding.instance.guideUrlForRole(role);
}
