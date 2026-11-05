import 'package:flutter/material.dart';
import '../core/address_sort.dart';
import '../widgets/event_details_dialog.dart';
import '../core/form_helpers.dart';
import '../widgets/pagination_footer.dart';
import 'package:go_router/go_router.dart';
import '../core/branding.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/community_logo.dart';
import '../widgets/legal_documents.dart';
import '../core/refresh_bus.dart';
import '../widgets/phase_scope.dart';
import '../core/safe_state.dart';

/// Public "Browse as Visitor" page, opened from the landing page with no
/// account. Read-only: the community map plus the announcements and events
/// that the database lets signed-out callers read.
class VisitorScreen extends StatefulWidget {
  const VisitorScreen({super.key});

  @override
  State<VisitorScreen> createState() => _VisitorScreenState();
}

class _VisitorScreenState extends State<VisitorScreen> with SafeSetState<VisitorScreen> {
  /// Which list is showing: 0 = Announcements, 1 = Events.
  /// A plain index because TabBarView needs a bounded height, which would
  /// mean a second scroll view inside the page's.
  int _feedTab = 0;

  /// Cards per page in the announcement and event lists.
  static const int _kFeedPageSize = 7;
  int _annPage = 1;
  int _evtPage = 1;


  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _events = [];

  /// One entry per active phase number, from `visitor_map_data()`:
  /// `{number, code, map_image_url}`.
  List<Map<String, dynamic>> _phaseMaps = [];

  /// Which entry of [_phaseMaps] is on screen.
  int _mapPhase = 0;

  /// The community-wide map, used only when no phases come back.
  String? _mapImageUrl;
  final TransformationController _mapTransform = TransformationController();
  bool _loading = true;
  String? _error;

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  @override
  void dispose() {
    _mapTransform.dispose();
    super.dispose();
  }

  /// Loads announcements, events and the phase maps.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = SupabaseService.instance.client;
      final results = await Future.wait([
        c
            .from('announcements')
            .select('title, content, category, priority, target_audience, created_at, '
                'publish_at, expire_at, phase, image_url, author_name')
            .order('created_at', ascending: false)
            // Keep this high: the cap covers all phases and the phase filter
            // runs on the device, so a low cap hides whole phases' notices.
            .limit(500),
        c
            .from('events')
            .select('title, description, venue, start_datetime, end_datetime, category, max_attendees, status, phase, image_url')
            .order('start_datetime', ascending: true)
            // Keep this high, for the same reason as announcements above.
            .limit(500),
      ]);
      // The map is optional: if this call fails, the rest of the page
      // still loads.
      String? mapImageUrl;
      var phaseMaps = <Map<String, dynamic>>[];
      try {
        final m = await c.rpc('visitor_map_data');
        final obj = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
        mapImageUrl = obj['map_image_url'] as String?;
        final raw = obj['phases'];
        if (raw is List) {
          phaseMaps = [
            for (final p in raw)
              if (p is Map) Map<String, dynamic>.from(p),
          ];
        }
        phaseMaps = sortPhaseRows(phaseMaps);
        // Open on the first phase that has a map picture.
        final firstWithMap =
            phaseMaps.indexWhere((p) => (p['map_image_url'] ?? '').toString().isNotEmpty);
        if (firstWithMap > 0) _mapPhase = firstWithMap;
      } catch (_) {
        // leave the map hidden
      }
      if (!mounted) return;
      setState(() {
        _announcements = List<Map<String, dynamic>>.from(results[0]);
        _events = List<Map<String, dynamic>>.from(results[1]);
        _mapImageUrl = mapImageUrl;
        _phaseMaps = phaseMaps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  String _date(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return '';
    return '${_months[dt.month]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _topBar(context),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? const Center(
                        child: Text('Could not load community info.',
                            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)))
                    : LayoutBuilder(builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 980;
                        return SingleChildScrollView(
                          // Extra right padding leaves a clear gutter for the
                          // page scrollbar so it doesn't sit over the content.
                          padding: EdgeInsets.fromLTRB(
                              narrow ? 20 : 48, 28, narrow ? 28 : 68, 28),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1400),
                            child: Column(
                              children: [
                                _layout(narrow),
                                const SizedBox(height: 32),
                                const Divider(height: 1, color: AppColors.border),
                                const SizedBox(height: 14),
                                // Terms and Privacy, readable without an account.
                                const LegalLinks(),
                              ],
                            ),
                          ),
                        );
                      }),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => context.go('/'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Home'),
          ),
          const SizedBox(width: 12),
          CommunityLogo(size: 28, monogramColor: AppColors.sidebarBg),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${AppBranding.instance.communityName} · Visitor View',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          FilledButton(onPressed: () => context.go('/login'), child: const Text('Sign In')),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.sidebarActiveText),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );
  }

  /// True when any phase has a site plan. If not, the map section is left out.
  bool get _hasAnyMap =>
      (_mapImageUrl ?? '').isNotEmpty ||
      _phaseMaps.any((p) => (p['map_image_url'] ?? '').toString().isNotEmpty);

  /// Map on the left, announcements and events on the right; stacked on a
  /// phone. The phase chips at the top filter both sides.
  Widget _layout(bool narrow) {
    final header = <Widget>[
      if (_phaseMaps.length > 1) ...[
        Row(
          children: [
            const Icon(Icons.filter_alt_outlined, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text('Showing ${_selectedPhaseNumber == null ? 'all phases' : 'Phase $_selectedPhaseNumber'}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 8),
        _phaseMapChips(),
        const SizedBox(height: 18),
      ],
    ];
    final feed = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_feedTabs(), const SizedBox(height: 18), _feedBody()],
    );
    if (!_hasAnyMap) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...header, feed]);
    }
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [...header, _communityMapSection(), const SizedBox(height: 28), feed],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...header,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _communityMapSection()),
            const SizedBox(width: 28),
            Expanded(flex: 2, child: feed),
          ],
        ),
      ],
    );
  }

  /// The phase NUMBER the chips are set to, or null when there is only one
  /// phase (nothing to filter by).
  String? get _selectedPhaseNumber {
    if (_phaseMaps.length < 2) return null;
    final i = _mapPhase < _phaseMaps.length ? _mapPhase : 0;
    final n = _phaseMaps[i]['number'];
    return n?.toString();
  }

  /// Posted to every phase (null) always shows; otherwise the item's phase
  /// must be the selected one. 1A and 1B are one association, so compare
  /// numbers.
  bool _inSelectedPhase(dynamic phase) {
    final sel = _selectedPhaseNumber;
    final code = (phase ?? '').toString();
    if (sel == null || code.isEmpty) return true;
    return phaseNumberOf(code) == sel;
  }

  List<Map<String, dynamic>> get _visibleAnnouncements =>
      _announcements.where((a) => _inSelectedPhase(a['phase'])).toList();

  /// Events in the selected phase, unsorted; [_eventsSection] orders them.
  List<Map<String, dynamic>> get _visibleEvents =>
      _events.where((e) => _inSelectedPhase(e['phase'])).toList();

  /// True until the event's end time (or start time, if it has no end).
  bool _isUpcoming(Map<String, dynamic> e) {
    final end = DateTime.tryParse((e['end_datetime'] ?? '').toString());
    final start = DateTime.tryParse((e['start_datetime'] ?? '').toString());
    final ref = end ?? start;
    return ref != null && ref.isAfter(DateTime.now());
  }

  Widget _feedBody() {
    return _feedTab == 1 ? _eventsSection() : _announcementsSection();
  }

  void _showAnnouncement(Map<String, dynamic> a) =>
      showAnnouncementDetails(context, a);

  /// Announcements / Events switcher.
  Widget _feedTabs() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // On narrow screens, drop the counts so the labels still fit.
        final compact = constraints.maxWidth < 560;

        Widget tab(int index, String label, IconData icon, int count) {
          final selected = _feedTab == index;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() {
                _feedTab = index;
              }),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: EdgeInsets.symmetric(
                    vertical: 11, horizontal: compact ? 4 : 8),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selected ? AppColors.cardShadow : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: 16,
                        color: selected ? AppColors.sidebarActiveText : AppColors.textMuted),
                    SizedBox(width: compact ? 5 : 7),
                    Flexible(
                      child: Text(
                        (count > 0 && !compact) ? '$label ($count)' : label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 12 : 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? AppColors.textPrimary : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.highlight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              tab(0, 'Announcements', Icons.campaign_outlined, _visibleAnnouncements.length),
              const SizedBox(width: 4),
              tab(1, 'Events', Icons.event_outlined, _visibleEvents.length),
            ],
          ),
        );
      },
    );
  }

  /// Which phase posted this item; a null phase means all phases.
  String _phaseLabel(dynamic phase) {
    final code = (phase ?? '').toString();
    return code.isEmpty ? 'All phases' : 'Phase ${phaseNumberOf(code)}';
  }

  /// One card for an announcement or event: picture or icon, title, one
  /// detail line. Tap to open.
  Widget _feedCard({
    required IconData icon,
    String? imageUrl,
    required String title,
    required String meta,
    String? excerpt,
    required VoidCallback onTap,
    bool faded = false,
  }) {
    return _FeedCard(
      icon: icon,
      imageUrl: imageUrl,
      title: title,
      meta: meta,
      excerpt: excerpt,
      onTap: onTap,
      faded: faded,
    );
  }

  Widget _announcementsSection() {
    final items = _visibleAnnouncements;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          const Text('No announcements right now.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))
        else
          for (final a in pageSlice(items, _annPage, size: _kFeedPageSize))
            _feedCard(
              icon: Icons.campaign_outlined,
              imageUrl: a['image_url']?.toString(),
              title: (a['title'] ?? '').toString(),
              meta: '${_titleCase((a['category'] ?? 'general').toString())} · '
                  '${_date((a['publish_at'] ?? a['created_at'])?.toString())} · ${_phaseLabel(a['phase'])}',
              excerpt: (a['content'] ?? '').toString(),
              onTap: () => _showAnnouncement(a),
            ),
        pagerFor(items.length, _annPage, (p) => setState(() => _annPage = p),
            size: _kFeedPageSize),
      ],
    );
  }

  /// Upcoming events (soonest first), then past events (newest first, faded).
  Widget _eventsSection() {
    final all = _visibleEvents;
    final upcoming = all.where(_isUpcoming).toList()
      ..sort((x, y) => (x['start_datetime'] ?? '').toString().compareTo((y['start_datetime'] ?? '').toString()));
    final past = all.where((e) => !_isUpcoming(e)).toList()
      ..sort((x, y) => (y['start_datetime'] ?? '').toString().compareTo((x['start_datetime'] ?? '').toString()));
    Widget card(Map<String, dynamic> e, {bool faded = false}) => _feedCard(
          icon: Icons.event_outlined,
          imageUrl: e['image_url']?.toString(),
          title: (e['title'] ?? '').toString(),
          meta: '${_date(e['start_datetime']?.toString())} · ${(e['venue'] ?? 'TBD')} · ${_phaseLabel(e['phase'])}',
          excerpt: (e['description'] ?? '').toString(),
          onTap: () => showEventDetails(context, e),
          faded: faded,
        );
    // Upcoming then past, paged as ONE list so the order survives the
    // page break. Each heading is drawn where its group starts on the
    // current page.
    final ordered = [
      for (final e in upcoming) (event: e, past: false),
      for (final e in past) (event: e, past: true),
    ];
    final pageRows = pageSlice(ordered, _evtPage, size: _kFeedPageSize);
    Widget sub(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Text(t,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.textMuted)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (all.isEmpty)
          const Text('No public events scheduled.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))
        else ...[
          if (pageRows.isNotEmpty && !pageRows.first.past) sub('UPCOMING'),
          if (upcoming.isEmpty && _evtPage == 1) ...[
            sub('UPCOMING'),
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text('Nothing scheduled yet.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            ),
          ],
          for (var i = 0; i < pageRows.length; i++) ...[
            if (pageRows[i].past && (i == 0 || !pageRows[i - 1].past)) ...[
              if (i > 0) const SizedBox(height: 8),
              sub('PAST'),
            ],
            card(pageRows[i].event, faded: pageRows[i].past),
          ],
          pagerFor(ordered.length, _evtPage, (p) => setState(() => _evtPage = p),
              size: _kFeedPageSize),
        ],
      ],
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Zooms the map about its centre by [factor], kept between 1x and 5x.
  /// [w] and [h] are the current viewport size.
  void _zoomBy(double factor, double w, double h) {
    final m = _mapTransform.value;
    final scale = m.getMaxScaleOnAxis();
    final target = (scale * factor).clamp(1.0, 5.0);
    if ((target - scale).abs() < 0.001) return;
    if (target <= 1.0001) {
      _mapTransform.value = Matrix4.identity();
      return;
    }
    final f = target / scale;
    // Zoom about the viewport centre, on top of the current transform so
    // any existing pan is kept.
    final cx = w / 2;
    final cy = h / 2;
    final zoom = Matrix4.identity()..scaleByDouble(f, f, 1, 1);
    zoom.setTranslationRaw(cx * (1 - f), cy * (1 - f), 0);
    _mapTransform.value = zoom.multiplied(m);
  }

  /// The zoom in, zoom out and reset buttons shown on the map.
  Widget _zoomControls(double w, double h) {
    Widget btn(IconData icon, String tip, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Tooltip(
            message: tip,
            child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(icon, size: 18, color: AppColors.textPrimary)),
          ),
        );
    Widget card(Widget child) => Material(
          color: Colors.white,
          elevation: 3,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // +/- stacked in one rounded card, like a maps app.
        card(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(Icons.add, 'Zoom in', () => _zoomBy(1.4, w, h)),
            const Divider(height: 1, thickness: 1),
            btn(Icons.remove, 'Zoom out', () => _zoomBy(1 / 1.4, w, h)),
          ],
        )),
        const SizedBox(height: 8),
        // Reset to the default framing.
        card(btn(Icons.center_focus_strong_outlined, 'Reset view',
            () => _mapTransform.value = Matrix4.identity())),
      ],
    );
  }

  /// The site plan currently selected, or null when this phase has none.
  String? get _currentMapUrl {
    if (_phaseMaps.isEmpty) return _mapImageUrl;
    final i = _mapPhase < _phaseMaps.length ? _mapPhase : 0;
    final url = (_phaseMaps[i]['map_image_url'] ?? '').toString();
    return url.isEmpty ? null : url;
  }

  /// One chip per phase. Picking one changes the map and both lists.
  Widget _phaseMapChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _phaseMaps.length; i++)
          ChoiceChip(
            label: Text('Phase ${_phaseMaps[i]['number'] ?? '?'}'),
            selected: _mapPhase == i,
            onSelected: (_) => setState(() {
              _mapPhase = i;
              _annPage = 1;
              _evtPage = 1;
              // Reset zoom, or it carries over to the next phase's picture.
              _mapTransform.value = Matrix4.identity();
            }),
          ),
      ],
    );
  }

  /// Read-only map picture of the selected phase. Zoom with the +/- buttons,
  /// drag to pan once zoomed in.
  Widget _communityMapSection() {
    final url = _currentMapUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Community Map', Icons.map_outlined),
        const SizedBox(height: 4),
        Text(
          url == null
              ? 'This part of the subdivision has no site plan on file yet.'
              : 'Use the + / - buttons to zoom, then drag to pan around.',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 14),
        if (url == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppColors.cardShadow,
            ),
            child: const Column(
              children: [
                Icon(Icons.map_outlined, size: 28, color: AppColors.textMuted),
                SizedBox(height: 10),
                Text('No site plan uploaded yet.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppColors.cardShadow,
            ),
            padding: const EdgeInsets.all(8),
            child: AspectRatio(
              // Same box shape as the officer and resident maps.
              aspectRatio: 1.3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    // No lot pins on purpose: visitors must not see where
                    // households are. Do not add them here or to the RPC.
                    return Stack(
                      children: [
                        InteractiveViewer(
                          transformationController: _mapTransform,
                          panEnabled: true,
                          // Off so the mouse wheel scrolls the page; the +/-
                          // buttons do the zooming.
                          scaleEnabled: false,
                          minScale: 1.0,
                          maxScale: 5.0,
                          clipBehavior: Clip.antiAlias,
                          // A DecorationImage is silent to screen readers
                          // unless wrapped like this.
                          child: Semantics(
                            image: true,
                            label: 'Site plan of the subdivision. '
                                'Individual homes are not marked.',
                            child: Container(
                              width: w,
                              height: h,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF2EC),
                                // contain, not cover: cropping would hide
                                // whole blocks of the plan.
                                image: DecorationImage(
                                    image: NetworkImage(url), fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        ),
                        Positioned(right: 12, bottom: 12, child: _zoomControls(w, h)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A clickable announcement or event card. On hover it shows a dark border,
/// a light grey tint, a deeper shadow and the hand cursor.
class _FeedCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String meta;
  final String? excerpt;
  final VoidCallback onTap;
  final bool faded;
  /// The post's photo, shown in place of the icon when it has one.
  final String? imageUrl;

  const _FeedCard({
    required this.icon,
    this.imageUrl,
    required this.title,
    required this.meta,
    required this.excerpt,
    required this.onTap,
    required this.faded,
  });

  @override
  State<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<_FeedCard> with SafeSetState<_FeedCard> {
  Widget _iconTile() => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: AppColors.badgeGreenBg, borderRadius: BorderRadius.circular(12)),
        child: Icon(widget.icon, size: 18, color: AppColors.sidebarActiveText),
      );

  /// A post with a photo shows it here; one without keeps the icon.
  Widget _thumb() {
    final u = (widget.imageUrl ?? '').trim();
    if (u.isEmpty) return _iconTile();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(u,
          width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _iconTile()),
    );
  }

  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final excerpt = widget.excerpt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _hover ? const Color(0xFFF2F4F3) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hover ? const Color(0xFF1F2937) : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: _hover
                  ? const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))]
                  : AppColors.cardShadow,
            ),
            child: Opacity(
              opacity: widget.faded && !_hover ? 0.65 : 1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _thumb(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(widget.meta, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                        if (excerpt != null && excerpt.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(excerpt,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5, height: 1.45, color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: _hover ? const Color(0xFF1F2937) : AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
