import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/branding.dart';
import '../core/phase_contacts.dart';
import '../theme/app_theme.dart';
import '../widgets/community_logo.dart';
import '../widgets/legal_documents.dart';
import '../core/safe_state.dart';

/// Public landing page at '/', shown before sign-in. Its text comes from
/// [AppBranding], which the CMS edits. Signed-in users are redirected to
/// their dashboard.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SafeSetState<HomeScreen> {
  /// Marks the contact section so "Contact Us" can scroll to it.
  final _contactKey = GlobalKey();

  /// True when the contact section is shown; also decides whether the
  /// "Contact Us" button is offered.
  bool _hasContact(AppBranding b) =>
      b.hasStructuredContact ||
      b.homeContact.trim().isNotEmpty ||
      _phaseContacts.isNotEmpty;

  /// Phases that have their own contact details or social pages, by phase
  /// number. Phases with nothing get no chip.
  Map<String, PhaseContact> _phaseContacts = {};

  /// Which office the contact card shows: null = the subdivision.
  String? _contactPhase;

  @override
  void initState() {
    super.initState();
    _loadPhaseContacts();
  }

  /// Loads the phase offices that have contact details.
  Future<void> _loadPhaseContacts() async {
    try {
      final all = await loadPhaseContacts();
      if (!mounted) return;
      setState(() => _phaseContacts = {
            for (final e in all.entries)
              if (e.value.hasAnything) e.key: e.value,
          });
    } catch (_) {
      // Subdivision details still show; only the phase chips are missing.
    }
  }

  /// Scrolls the page down to the contact section.
  void _scrollToContact() {
    final ctx = _contactKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      // Stops just below the top edge.
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when branding finishes loading.
    return Scaffold(
      backgroundColor: Colors.white,
      body: ListenableBuilder(
        listenable: AppBranding.instance,
        builder: (context, _) {
          final branding = AppBranding.instance;
          return LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 700;
            return SingleChildScrollView(
              child: Column(
                children: [
                  _topBar(context, branding, narrow),
                  _hero(context, branding, narrow),
                  // Everything below the hero shares one optional background.
                  _bodyWrapper(
                    branding,
                    Column(
                      children: [
                        _aboutSection(branding, narrow),
                        if (_hasContact(branding))
                          KeyedSubtree(
                            key: _contactKey,
                            child: _contactSection(branding, narrow),
                          ),
                        _footer(branding),
                      ],
                    ),
                  ),
                ],
              ),
            );
          });
        },
      ),
    );
  }

  /// Top strip with the logo, community name and "Contact Us" button.
  Widget _topBar(BuildContext context, AppBranding branding, bool narrow) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 48, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          CommunityLogo(size: 34, monogramColor: AppColors.sidebarBg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              branding.communityName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
          if (_hasContact(branding))
            TextButton.icon(
              onPressed: _scrollToContact,
              icon: const Icon(Icons.support_agent_outlined, size: 18),
              // Shorter label on a phone to leave room for the name.
              label: Text(narrow ? 'Contact' : 'Contact Us'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.sidebarBg,
                padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 14, vertical: 10),
                textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  /// Big banner with the name, tagline and the Sign In / Create an Account /
  /// Browse as Visitor buttons.
  Widget _hero(BuildContext context, AppBranding branding, bool narrow) {
    // Hero background: the CMS photo under a dark scrim, or a gradient of
    // the hero colour.
    final heroImage = branding.heroImageUrl;
    final base = branding.heroColor;
    final deep = Color.lerp(base, Colors.black, 0.45) ?? base;
    // True when the CMS is set to use the photo.
    final hasPhoto = branding.useHeroPhoto;

    // Wide screens show the whole picture over a blurred copy, because
    // `cover` would crop it to a thin band. Phones use `cover`.
    final layered = hasPhoto && !narrow;

    final hero = Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 24 : 48, vertical: narrow ? 48 : 80),
      decoration: layered
          ? null
          : hasPhoto
          ? BoxDecoration(
              image: DecorationImage(
                // useHeroPhoto guarantees a non-empty URL here.
                image: NetworkImage(heroImage!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.45), BlendMode.darken),
              ),
            )
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [base, deep],
              ),
            ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: CommunityLogo(size: 76, monogramColor: AppColors.sidebarActiveText),
          ),
          const SizedBox(height: 28),
          Text(
            branding.communityName,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: narrow ? 28 : 38, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              branding.homeTagline,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: narrow ? 14.5 : 17,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.85)),
            ),
          ),
          const SizedBox(height: 32),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.sidebarBg,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    ),
                    child: const Text('Sign In',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  OutlinedButton(
                    onPressed: () => context.go('/register'),
                    // Transparent background is needed: the app theme's
                    // white fill would hide the white label.
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    ),
                    child: const Text('Create an Account'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Public browsing without an account.
              TextButton.icon(
                onPressed: () => context.go('/visitor'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Browse as Visitor'),
              ),
              // Residents' guide PDF; hidden until the office uploads it.
              if (AppBranding.instance.guideResidentsUrl != null)
                TextButton.icon(
                  onPressed: () => launchUrl(
                      Uri.parse(AppBranding.instance.guideResidentsUrl!),
                      webOnlyWindowName: '_blank'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Resident guide (PDF)'),
                ),
            ],
          ),
        ],
      ),
    );
    if (!layered) return hero;

    Widget photo(BoxFit fit) => Image.network(heroImage!,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => const SizedBox.shrink());
    return Stack(children: [
        Positioned.fill(child: ColoredBox(color: deep)),
        Positioned.fill(
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: photo(BoxFit.cover),
            ),
          ),
        ),
        Positioned.fill(child: photo(BoxFit.contain)),
        Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.45))),
        hero,
      ]);
  }

  /// Background for the part of the page below the hero: the CMS photo
  /// under a white scrim, or the CMS body colour.
  Widget _bodyWrapper(AppBranding branding, Widget child) {
    final img = branding.homeBodyImageUrl;
    if (branding.useHomeBodyPhoto) {
      return Stack(
        children: [
          // useHomeBodyPhoto guarantees a non-empty URL. Decorative, so
          // hidden from screen readers.
          Positioned.fill(
            child: ExcludeSemantics(child: Image.network(img!, fit: BoxFit.cover)),
          ),
          // White scrim keeps the text readable.
          Positioned.fill(child: Container(color: Colors.white.withValues(alpha: 0.85))),
          child,
        ],
      );
    }
    // No photo: plain body colour.
    return Container(color: branding.homeBodyColor, child: child);
  }

  /// "About" text plus the four feature cards.
  Widget _aboutSection(AppBranding branding, bool narrow) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 24 : 48, vertical: narrow ? 40 : 64),
      child: Column(
        children: [
          Text('About ${branding.communityName}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.onHomeBodyPrimary)),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              branding.homeAbout,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14.5, height: 1.7, color: AppColors.onHomeBodySecondary),
            ),
          ),
          const SizedBox(height: 40),
          const Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _FeatureCard(
                icon: Icons.campaign_outlined,
                title: 'Announcements & Events',
                text: 'Stay up to date with community news, schedules, and activities.',
              ),
              _FeatureCard(
                icon: Icons.receipt_long_outlined,
                title: 'Billing & Payments',
                text: 'View your dues and payment history in one place.',
              ),
              _FeatureCard(
                icon: Icons.forum_outlined,
                title: 'Complaints & Requests',
                text: 'Submit concerns, permits, and gate passes online.',
              ),
              _FeatureCard(
                icon: Icons.shield_outlined,
                title: 'Community Security',
                text: 'Visitor logging and incident reporting for a safer neighborhood.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Contact card for the subdivision or the chosen phase office.
  Widget _contactSection(AppBranding branding, bool narrow) {
    // A phase's own value wins; blank ones fall back to the subdivision's.
    final pc = _contactPhase == null ? null : _phaseContacts[_contactPhase];
    String pick(String? own, String fallback) =>
        (own ?? '').trim().isNotEmpty ? own!.trim() : fallback;
    final address = pick(pc?.address, branding.contactAddress);
    final hours = pick(pc?.hours, branding.contactHours);
    final phoneText = pick(pc?.phone, branding.contactPhone);
    final email = pick(pc?.email, branding.contactEmail);
    final mapLink = pick(pc?.mapLink, branding.contactMapLink);
    final structured = pc != null || branding.hasStructuredContact;
    final phone = phoneText.replaceAll(RegExp(r'[^0-9+]'), '');
    final mapUrl = SocialLink.normalize(mapLink);

    // Two groups: where to go, and how to reach the office.
    final visit = <Widget>[
      if (address.trim().isNotEmpty)
        _ContactTile(icon: Icons.location_on_outlined, label: 'Address', value: address),
      if (hours.trim().isNotEmpty)
        _ContactTile(icon: Icons.schedule_outlined, label: 'Office hours', value: hours),
      if (mapLink.trim().isNotEmpty)
        _ContactTile(
          icon: Icons.map_outlined,
          label: 'Map',
          value: 'Open in maps',
          action: 'Open the map in a new tab',
          onTap: mapUrl == null ? null : (_) => _open(Uri.parse(mapUrl)),
        ),
    ];
    final reach = <Widget>[
      if (phoneText.trim().isNotEmpty)
        _ContactTile(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: phoneText,
          action: 'Call the office',
          onTap: phone.isEmpty ? null : (_) => _open(Uri.parse('tel:$phone')),
        ),
      if (email.trim().isNotEmpty)
        _ContactTile(
          icon: Icons.email_outlined,
          label: 'Email',
          value: email,
          action: 'Write to the office',
          onTap: email.contains('@') ? (ctx) => _chooseMailApp(ctx, email) : null,
        ),
    ];

    Widget group(String title, List<Widget> tiles) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted)),
            const SizedBox(height: 10),
            for (final t in tiles) ...[t, const SizedBox(height: 10)],
          ],
        );

    final officeName = _contactPhase == null
        ? 'Subdivision office'
        : 'Phase $_contactPhase office';
    final socials = <Widget>[
      if (pc != null && pc.socialLinks.isNotEmpty)
        _socialRow('Follow Phase $_contactPhase', pc.socialLinks),
      if (branding.socialLinks.isNotEmpty)
        _socialRow(
            pc == null
                ? 'Follow the community'
                : '${branding.communityName} (whole subdivision)',
            branding.socialLinks,
            small: pc != null),
    ];

    final card = Container(
      constraints: const BoxConstraints(maxWidth: 880),
      padding: EdgeInsets.all(narrow ? 18 : 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.badgeGreenBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.apartment_outlined,
                  size: 20, color: AppColors.sidebarActiveText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(officeName,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const Text('Tap a line to call, write or open the map.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ]),
            ),
          ]),
          if (_phaseContacts.isNotEmpty) ...[
            const SizedBox(height: 18),
            _phaseChips(),
          ],
          const SizedBox(height: 20),
          if (!structured)
            Text(branding.homeContact,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.6, color: AppColors.textSecondary))
          else
            LayoutBuilder(builder: (context, c) {
              final a = visit.isEmpty ? null : group('Visit the office', visit);
              final b = reach.isEmpty ? null : group('Call or write', reach);
              if (c.maxWidth >= 620 && a != null && b != null) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: a),
                  const SizedBox(width: 20),
                  Expanded(child: b),
                ]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (a != null) a,
                if (a != null && b != null) const SizedBox(height: 6),
                if (b != null) b,
              ]);
            }),
          if (socials.isNotEmpty) ...[
            const Divider(height: 28, color: AppColors.border),
            for (final w in socials) ...[w, const SizedBox(height: 12)],
          ],
        ],
      ),
    );

    // Transparent when a custom body background is set, so it shows
    // through; the card itself is always white.
    final hasBodyPhoto = branding.useHomeBodyPhoto;
    final bc = branding.homeBodyColor;
    final isWhite = bc.r == 1.0 && bc.g == 1.0 && bc.b == 1.0;
    final hasBodyBg = hasBodyPhoto || !isWhite;
    return Container(
      width: double.infinity,
      color: hasBodyBg ? Colors.transparent : AppColors.contentBg,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 48, vertical: 48),
      child: Column(
        children: [
          Text('Contact the HOA Office',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: narrow ? 20 : 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onHomeBodyPrimary)),
          const SizedBox(height: 6),
          Text('Choose your phase to see its own office.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.onHomeBodySecondary)),
          const SizedBox(height: 22),
          card,
        ],
      ),
    );
  }

  /// Pills to pick the subdivision or a phase office.
  Widget _phaseChips() {
    final nums = _phaseContacts.keys.toList()
      ..sort((a, b) =>
          (int.tryParse(a) ?? 999).compareTo(int.tryParse(b) ?? 999));
    Widget pill(String label, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: selected ? AppColors.sidebarActiveText : AppColors.contentBg,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? Colors.white : AppColors.textPrimary)),
              ),
            ),
          ),
        );
    final pills = [
      pill('Subdivision', _contactPhase == null,
          () => setState(() => _contactPhase = null)),
      for (final n in nums)
        pill('Phase $n', _contactPhase == n,
            () => setState(() => _contactPhase = n)),
    ];
    // Wraps on wide screens; scrolls sideways on a phone.
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 600) {
        return Wrap(runSpacing: 8, children: pills);
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: pills),
      );
    });
  }

  /// Opens a link outside the app -- a new browser tab on the web.
  Future<void> _open(Uri uri) async {
    try {
      await launchUrl(uri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {}
  }

  /// Menu to write from Gmail, Outlook or the default app, or copy the
  /// address. A bare mailto: does nothing without a mail program set up.
  Future<void> _chooseMailApp(BuildContext anchor, String email) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    RelativeRect? position;
    if (box != null && overlay != null) {
      final topLeft = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
      position = RelativeRect.fromRect(
          topLeft & Size(box.size.width, 0), Offset.zero & overlay.size);
    }
    final enc = Uri.encodeComponent(email);
    final choice = await showMenu<String>(
      context: anchor,
      position: position ?? const RelativeRect.fromLTRB(0, 0, 0, 0),
      items: const [
        PopupMenuItem(value: 'gmail', child: ListTile(dense: true,
            leading: Icon(Icons.mail_outline), title: Text('Open in Gmail'))),
        PopupMenuItem(value: 'outlook', child: ListTile(dense: true,
            leading: Icon(Icons.mail_outline), title: Text('Open in Outlook'))),
        PopupMenuItem(value: 'default', child: ListTile(dense: true,
            leading: Icon(Icons.forward_to_inbox_outlined),
            title: Text('Default email app'))),
        PopupMenuItem(value: 'copy', child: ListTile(dense: true,
            leading: Icon(Icons.copy_outlined), title: Text('Copy address'))),
      ],
    );
    switch (choice) {
      case 'gmail':
        await _open(Uri.parse(
            'https://mail.google.com/mail/?view=cm&fs=1&to=$enc'));
      case 'outlook':
        await _open(Uri.parse(
            'https://outlook.live.com/mail/0/deeplink/compose?to=$enc'));
      case 'default':
        await launchUrl(Uri(scheme: 'mailto', path: email));
      case 'copy':
        await Clipboard.setData(ClipboardData(text: email));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Email address copied.')));
        }
    }
  }

  /// Social accounts as tappable chips under a heading. Callers only add
  /// it when the list is not empty.
  Widget _socialRow(String heading, List<SocialLink> links,
      {bool small = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading.toUpperCase(),
            style: TextStyle(
                fontSize: small ? 10.5 : 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final link in links)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  side: const BorderSide(color: AppColors.border),
                ),
                onPressed: () => launchUrl(Uri.parse(link.url),
                    mode: LaunchMode.externalApplication,
                    webOnlyWindowName: '_blank'),
                icon: Icon(link.icon, size: 16, color: AppColors.sidebarActiveText),
                label: Text(link.label),
              ),
          ],
        ),
      ],
    );
  }

  /// Bottom line with the community name and legal links.
  Widget _footer(AppBranding branding) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Text(
            '${branding.communityName} · NeighborSync HOA Platform',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.onHomeBodySecondary),
          ),
          const SizedBox(height: 6),
          LegalLinks(color: AppColors.onHomeBodySecondary),
        ],
      ),
    );
  }
}

/// One small card describing a feature on the landing page.
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _FeatureCard({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.badgeGreenBg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: AppColors.sidebarActiveText),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 12, height: 1.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}


/// One way to reach the office: a tinted icon, a small label and the value.
/// Tappable when [onTap] is set (call, write, open the map).
class _ContactTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? action;
  final void Function(BuildContext)? onTap;
  const _ContactTile({
    required this.icon,
    required this.label,
    required this.value,
    this.action,
    this.onTap,
  });

  @override
  State<_ContactTile> createState() => _ContactTileState();
}

class _ContactTileState extends State<_ContactTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tappable = widget.onTap != null;
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _hover ? AppColors.badgeGreenBg : AppColors.contentBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(widget.icon, size: 18, color: AppColors.sidebarActiveText),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label,
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(widget.value,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: tappable ? AppColors.sidebarActiveText : AppColors.textPrimary)),
          ]),
        ),
        if (tappable)
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
      ]),
    );
    if (!tappable) return tile;
    // Semantics label, not a Tooltip: a tooltip would replace the value
    // for screen readers.
    return Semantics(
      link: true,
      label: '${widget.label}: ${widget.value}. ${widget.action ?? ''}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Builder(
          builder: (ctx) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onTap!(ctx),
            child: tile,
          ),
        ),
      ),
    );
  }
}
