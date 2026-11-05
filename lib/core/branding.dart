import 'dart:async';

import 'package:flutter/material.dart';
// Needed for RealtimeChannel and PostgresChangeEvent; supabase_service does
// not re-export them.
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'site_head.dart';
import 'social_link.dart';

export 'social_link.dart';

/// The community's CMS settings: name, logo, colours, landing-page content,
/// banner, rules, legal text and map pins. Stored in `system_settings`.
/// Use [instance]; listeners re-theme as soon as a value is saved or reloaded.
class AppBranding extends ChangeNotifier {
  AppBranding._();
  static final AppBranding instance = AppBranding._();

  static const defaultCommunityName = "ABC Subdivision";
  static const defaultLogoMonogram = 'AB';
  static const defaultPrimaryColor = Color(0xFF1A6B43);
  static const defaultSidebarColor = Color(0xFF114D30);

  String communityName = defaultCommunityName;
  String logoMonogram = defaultLogoMonogram;
  Color primaryColor = defaultPrimaryColor;
  Color sidebarColor = defaultSidebarColor;

  /// Uploaded logo. Null means no logo, so screens show [logoMonogram].
  String? logoImageUrl;

  // Landing-page text, edited in the CMS. Must stay readable before sign-in.
  // The defaults give a fresh install a sensible page.
  String homeTagline = 'A connected community, managed in one place.';
  String homeAbout =
      'Welcome to our community portal. Residents can view announcements '
      'and events, submit complaints and requests, pay dues, and reach the '
      'HOA office -- all in one place.';
  String homeContact = ''; // free-text contact, the fallback for the fields below

  // Landing-page contact details, edited in the CMS.
  String contactAddress = '';
  String contactHours = '';
  String contactEmail = '';
  String contactPhone = '';
  String contactMapLink = '';

  /// Community social accounts for the landing page, in display order.
  /// Saved as one JSON array in `homepage.social_links`.
  List<SocialLink> socialLinks = const [];

  // Site-wide announcement strip. [bannerLevel] is 'info', 'warning' or
  // 'critical'.
  bool bannerEnabled = false;

  /// Settings > General > Maintenance Mode. Residents cannot sign in while
  /// it is on; signed-in officers see a notice strip (SiteBanner).
  bool maintenanceMode = false;
  String bannerMessage = '';
  String bannerLevel = 'info';

  // Community Rules page, edited in the CMS.
  String rulesTitle = 'Community Rules & Guidelines';
  String rulesContent = '';

  // Terms, Privacy and the browser-storage notice. Must stay readable when
  // signed out: people agree to them on the register screen.
  // [legalVersion] is recorded on each new account as what they agreed to.
  String legalVersion = '';
  String termsTitle = 'Terms and Conditions';
  String termsContent = '';
  String privacyTitle = 'Privacy Notice';
  String privacyContent = '';
  String storageNotice = '';

  /// True when there is text to show. Use these to hide "read it" links
  /// that would otherwise open an empty sheet.
  bool get hasTerms => termsContent.trim().isNotEmpty;
  bool get hasPrivacy => privacyContent.trim().isNotEmpty;

  // Landing-page hero background: a photo or a colour, see [useHeroPhoto].
  String? heroImageUrl;
  Color heroColor = defaultSidebarColor;

  // Background of the home page section below the hero: a photo or a colour,
  // see [useHomeBodyPhoto].
  String? homeBodyImageUrl;
  Color homeBodyColor = const Color(0xFFFFFFFF);

  // Whole-community map picture. Null means none has been uploaded.
  String? communityMapImageUrl;

  // The three user guides (PDF), uploaded in the CMS. Keep the keys under
  // `homepage.*`: the public home page links the residents' guide before
  // sign-in. Which guide a role is shown is not access control.
  String? guideAdminUrl;
  String? guideOfficersUrl;
  String? guideResidentsUrl;

  /// The guide for [role]: the administrator's (or the officers', if that is
  /// missing), the officers', or the residents' for everyone else. Null when
  /// that guide has not been uploaded.
  String? guideUrlForRole(String role) {
    const officers = {'hoa_president', 'secretary', 'treasurer', 'security', 'audit_officer'};
    if (role == 'super_admin') return guideAdminUrl ?? guideOfficersUrl;
    if (officers.contains(role)) return guideOfficersUrl;
    return guideResidentsUrl;
  }

  // Background behind the cards on portal screens: a photo or a colour, see
  // [usePortalPhoto].
  static const Color defaultPortalBgColor = Color(0xFFF3F6F4);
  Color portalBgColor = defaultPortalBgColor;
  String? portalBgImageUrl;

  // Each background section is 'photo' or 'color'; both values stay saved so
  // an officer can switch back. The `use*Photo` getters also need a URL, so
  // 'photo' with no image shows the colour rather than a broken image.
  String portalBgMode = 'color';
  String heroMode = 'color';
  String homeBodyMode = 'color';

  bool get usePortalPhoto =>
      portalBgMode == 'photo' && (portalBgImageUrl?.isNotEmpty ?? false);
  bool get useHeroPhoto =>
      heroMode == 'photo' && (heroImageUrl?.isNotEmpty ?? false);
  bool get useHomeBodyPhoto =>
      homeBodyMode == 'photo' && (homeBodyImageUrl?.isNotEmpty ?? false);

  // Community map pins: one colour per lot status, and the diameter in
  // logical pixels.
  static const double defaultPinSize = 28;
  static const Color defaultPinColorVacant = Color(0xFF8A6300);
  static const Color defaultPinColorOccupied = Color(0xFF0C5C84);
  Color pinColor = defaultPrimaryColor; // "owned" / default status
  Color pinColorVacant = defaultPinColorVacant;
  Color pinColorOccupied = defaultPinColorOccupied;
  double pinSize = defaultPinSize;

  /// The `system_settings` rows [load] reads. A new setting must be added here.
  static const _keys = [
    'homepage.social_links',
    'branding.community_name',
    'branding.logo_monogram',
    'branding.primary_color',
    'branding.sidebar_color',
    'branding.logo_image_url',
    'homepage.tagline',
    'homepage.about',
    'homepage.contact',
    'homepage.contact_address',
    'homepage.contact_hours',
    'homepage.contact_email',
    'homepage.contact_phone',
    'homepage.map_link',
    'homepage.hero_image_url',
    'homepage.hero_color',
    'homepage.hero_mode',
    'homepage.body_image_url',
    'homepage.body_color',
    'homepage.body_mode',
    'homepage.guide_admin_url',
    'homepage.guide_officers_url',
    'homepage.guide_residents_url',
    'banner.enabled',
    'banner.message',
    'banner.level',
    'rules.title',
    'rules.content',
    'legal.version',
    'legal.terms_title',
    'legal.terms_content',
    'legal.privacy_title',
    'legal.privacy_content',
    'legal.storage_notice',
    'community.map_image_url',
    // From Settings -> General; used by _applyContactFallback().
    'general.contact_email',
    'general.contact_phone',
    'general.address',
    'general.maintenance_mode',
    'portal.bg_color',
    'portal.bg_image_url',
    'portal.bg_mode',
    'map.pin_color',
    'map.pin_color_vacant',
    'map.pin_color_occupied',
    'map.pin_size',
  ];

  /// Loads the saved settings. On any failure (offline, no access) it keeps
  /// the current values, so branding can never block startup.
  Future<void> load() async {
    try {
      final rows = await SupabaseService.instance.client
          .from('system_settings')
          .select('setting_key, value')
          .inFilter('setting_key', _keys);
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final value = row['value'] as String?;
        if (row['setting_key'] == 'branding.logo_image_url') {
          // Empty means the logo was cleared.
          logoImageUrl = (value == null || value.isEmpty) ? null : value;
          continue;
        }
        if (row['setting_key'] == 'homepage.hero_image_url') {
          // Empty means no hero photo.
          heroImageUrl = (value == null || value.isEmpty) ? null : value;
          continue;
        }
        if (row['setting_key'] == 'homepage.body_image_url') {
          // Empty means no body photo.
          homeBodyImageUrl = (value == null || value.isEmpty) ? null : value;
          continue;
        }
        if (row['setting_key'] == 'community.map_image_url') {
          // Empty means no map picture.
          communityMapImageUrl =
              (value == null || value.isEmpty) ? null : value;
          continue;
        }
        if (row['setting_key'] == 'portal.bg_image_url') {
          // Empty means no portal photo.
          portalBgImageUrl = (value == null || value.isEmpty) ? null : value;
          continue;
        }
        if (value == null || value.isEmpty) continue;
        switch (row['setting_key']) {
          case 'branding.community_name':
            communityName = value;
          case 'branding.logo_monogram':
            logoMonogram = value;
          case 'branding.primary_color':
            primaryColor = _parseHex(value) ?? primaryColor;
          case 'branding.sidebar_color':
            sidebarColor = _parseHex(value) ?? sidebarColor;
          case 'homepage.tagline':
            homeTagline = value;
          case 'homepage.about':
            homeAbout = value;
          case 'homepage.contact':
            homeContact = value;
          case 'homepage.contact_address':
            contactAddress = value;
          case 'homepage.contact_hours':
            contactHours = value;
          case 'homepage.contact_email':
            contactEmail = value;
          case 'homepage.contact_phone':
            contactPhone = value;
          case 'homepage.map_link':
            contactMapLink = value;
          case 'homepage.guide_admin_url':
            guideAdminUrl = value.isEmpty ? null : value;
          case 'homepage.guide_officers_url':
            guideOfficersUrl = value.isEmpty ? null : value;
          case 'homepage.guide_residents_url':
            guideResidentsUrl = value.isEmpty ? null : value;
          case 'homepage.social_links':
            socialLinks = SocialLink.decode(value);
          case 'homepage.hero_color':
            heroColor = _parseHex(value) ?? heroColor;
          case 'homepage.body_color':
            homeBodyColor = _parseHex(value) ?? homeBodyColor;
          case 'banner.enabled':
            bannerEnabled = value == 'true';
          case 'banner.message':
            bannerMessage = value;
          case 'banner.level':
            bannerLevel = value;
          case 'rules.title':
            rulesTitle = value;
          case 'rules.content':
            rulesContent = value;
          case 'legal.version':
            legalVersion = value;
          case 'legal.terms_title':
            termsTitle = value;
          case 'legal.terms_content':
            termsContent = value;
          case 'legal.privacy_title':
            privacyTitle = value;
          case 'legal.privacy_content':
            privacyContent = value;
          case 'legal.storage_notice':
            storageNotice = value;
          case 'portal.bg_color':
            portalBgColor = _parseHex(value) ?? portalBgColor;
          // Anything other than 'photo' means colour, so a bad value cannot
          // break a section.
          case 'portal.bg_mode':
            portalBgMode = value == 'photo' ? 'photo' : 'color';
          case 'homepage.hero_mode':
            heroMode = value == 'photo' ? 'photo' : 'color';
          case 'homepage.body_mode':
            homeBodyMode = value == 'photo' ? 'photo' : 'color';
          case 'map.pin_color':
            pinColor = _parseHex(value) ?? pinColor;
          case 'map.pin_color_vacant':
            pinColorVacant = _parseHex(value) ?? pinColorVacant;
          case 'map.pin_color_occupied':
            pinColorOccupied = _parseHex(value) ?? pinColorOccupied;
          case 'map.pin_size':
            pinSize = double.tryParse(value) ?? pinSize;
          // Settings -> General. Held aside, then used only to fill gaps.
          case 'general.contact_email':
            _generalEmail = value;
          case 'general.contact_phone':
            _generalPhone = value;
          case 'general.address':
            _generalAddress = value;
          case 'general.maintenance_mode':
            maintenanceMode = value == 'true';
        }
      }
      _applyContactFallback();
      notifyListeners();
      // Use the logo as the browser tab icon (web only).
      applyFavicon(logoImageUrl);
    } catch (_) {
      // No access or offline: keep the current values.
    }
  }

  RealtimeChannel? _liveChannel;
  Timer? _reloadDebounce;
  Timer? _pollTimer;

  /// Watches `system_settings` so a CMS change reaches every open device
  /// without a page reload. Safe to call more than once.
  /// Each event only triggers [load]; its payload is ignored on purpose, so
  /// settings are always read through the normal query and its access rules.
  void startLiveUpdates() {
    if (_liveChannel != null) return;
    final client = SupabaseService.instance.client;

    _liveChannel = client
        .channel('public:system_settings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'system_settings',
          callback: (_) => _scheduleReload(),
        )
        .subscribe();

    // Backup poll: a websocket can drop silently, with no error to react to.
    _pollTimer ??= Timer.periodic(const Duration(minutes: 5), (_) => load());
  }

  /// Waits briefly before reloading. One CMS save arrives as several events,
  /// and each would otherwise re-theme the whole app.
  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 400), load);
  }

  /// Stops the channel and timers. The app itself never calls this; it is
  /// for tests or a teardown.
  void stopLiveUpdates() {
    _reloadDebounce?.cancel();
    _reloadDebounce = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    final ch = _liveChannel;
    _liveChannel = null;
    if (ch != null) SupabaseService.instance.client.removeChannel(ch);
  }

  // Contact details from Settings -> General, separate from the CMS fields.
  String _generalEmail = '';
  String _generalPhone = '';
  String _generalAddress = '';

  /// Fills empty landing-page contact fields from Settings -> General.
  /// CMS values always win, so a different public address can still be shown.
  void _applyContactFallback() {
    if (contactEmail.trim().isEmpty) contactEmail = _generalEmail;
    if (contactPhone.trim().isEmpty) contactPhone = _generalPhone;
    if (contactAddress.trim().isEmpty) contactAddress = _generalAddress;
  }

  /// True if any structured contact field is filled in.
  bool get hasStructuredContact => [
        contactAddress,
        contactHours,
        contactEmail,
        contactPhone,
        contactMapLink
      ].any((s) => s.trim().isNotEmpty);

  /// Saves the name, monogram, colours and logo, then re-themes the app.
  /// Pass [logoImageUrl] as null to clear the logo and show the monogram.
  Future<void> save({
    required String communityName,
    required String logoMonogram,
    required Color primaryColor,
    required Color sidebarColor,
    required String? logoImageUrl,
  }) async {
    final updatedBy = await SupabaseService.instance.getMyUserId();
    final rows = [
      {
        'setting_key': 'branding.community_name',
        'value': communityName,
        'type': 'string',
        'category': 'branding',
        'is_public': true,
        if (updatedBy != null) 'updated_by': updatedBy,
      },
      {
        'setting_key': 'branding.logo_monogram',
        'value': logoMonogram,
        'type': 'string',
        'category': 'branding',
        'is_public': true,
        if (updatedBy != null) 'updated_by': updatedBy,
      },
      {
        'setting_key': 'branding.primary_color',
        'value': _toHex(primaryColor),
        'type': 'string',
        'category': 'branding',
        'is_public': true,
        if (updatedBy != null) 'updated_by': updatedBy,
      },
      {
        'setting_key': 'branding.sidebar_color',
        'value': _toHex(sidebarColor),
        'type': 'string',
        'category': 'branding',
        'is_public': true,
        if (updatedBy != null) 'updated_by': updatedBy,
      },
      {
        'setting_key': 'branding.logo_image_url',
        'value': logoImageUrl,
        'type': 'string',
        'category': 'branding',
        'is_public': true,
        if (updatedBy != null) 'updated_by': updatedBy,
      },
    ];
    await SupabaseService.instance.client
        .from('system_settings')
        .upsert(rows, onConflict: 'setting_key');

    this.communityName = communityName;
    this.logoMonogram = logoMonogram;
    this.primaryColor = primaryColor;
    this.sidebarColor = sidebarColor;
    this.logoImageUrl = logoImageUrl;
    notifyListeners();
    applyFavicon(logoImageUrl);
  }

  /// Saves [rows] as public settings, recording who changed them.
  Future<void> _upsert(List<Map<String, dynamic>> rows) async {
    final updatedBy = await SupabaseService.instance.getMyUserId();
    final withMeta = rows
        .map((r) => {
              ...r,
              'is_public': true,
              if (updatedBy != null) 'updated_by': updatedBy
            })
        .toList();
    await SupabaseService.instance.client
        .from('system_settings')
        .upsert(withMeta, onConflict: 'setting_key');
  }

  /// Saves the landing-page contact details.
  Future<void> saveContact({
    required String address,
    required String hours,
    required String email,
    required String phone,
    required String mapLink,
  }) async {
    Map<String, dynamic> row(String k, String v) => {
          'setting_key': k,
          'value': v,
          'type': 'string',
          'category': 'homepage'
        };
    await _upsert([
      row('homepage.contact_address', address),
      row('homepage.contact_hours', hours),
      row('homepage.contact_email', email),
      row('homepage.contact_phone', phone),
      row('homepage.map_link', mapLink),
    ]);
    contactAddress = address;
    contactHours = hours;
    contactEmail = email;
    contactPhone = phone;
    contactMapLink = mapLink;
    notifyListeners();
  }

  /// Saves the social links. Separate from [saveContact] so the two editors
  /// cannot overwrite each other.
  Future<void> saveSocialLinks(List<SocialLink> links) async {
    await _upsert([
      {
        'setting_key': 'homepage.social_links',
        'value': SocialLink.encode(links),
        'type': 'json',
        'category': 'homepage',
      }
    ]);
    socialLinks = List.unmodifiable(links);
    notifyListeners();
  }

  /// Saves the site-wide announcement banner.
  Future<void> saveBanner({
    required bool enabled,
    required String message,
    required String level,
  }) async {
    Map<String, dynamic> row(String k, String v, String t) =>
        {'setting_key': k, 'value': v, 'type': t, 'category': 'banner'};
    await _upsert([
      row('banner.enabled', '$enabled', 'boolean'),
      row('banner.message', message, 'string'),
      row('banner.level', level, 'string'),
    ]);
    bannerEnabled = enabled;
    bannerMessage = message;
    bannerLevel = level;
    notifyListeners();
  }

  /// Saves the hero background. [mode] picks 'photo' or 'color'; both values
  /// are kept so the officer can switch back. Null [imageUrl] clears the photo.
  Future<void> saveHero({
    required String? imageUrl,
    required Color color,
    required String mode,
  }) async {
    await _upsert([
      {
        'setting_key': 'homepage.hero_image_url',
        'value': imageUrl,
        'type': 'string',
        'category': 'homepage',
      },
      {
        'setting_key': 'homepage.hero_color',
        'value': _toHex(color),
        'type': 'string',
        'category': 'homepage',
      },
      {
        'setting_key': 'homepage.hero_mode',
        'value': mode,
        'type': 'string',
        'category': 'homepage',
      },
    ]);
    heroImageUrl = imageUrl;
    heroColor = color;
    heroMode = mode;
    notifyListeners();
  }

  /// Saves the Community Rules page.
  Future<void> saveRules(
      {required String title, required String content}) async {
    Map<String, dynamic> row(String k, String v) =>
        {'setting_key': k, 'value': v, 'type': 'string', 'category': 'rules'};
    await _upsert([
      row('rules.title', title),
      row('rules.content', content),
    ]);
    rulesTitle = title;
    rulesContent = content;
    notifyListeners();
  }

  /// Saves the Terms, Privacy Notice and browser-storage notice.
  /// Sets the version to today's date, which later signups record as what
  /// they agreed to; accounts keep the version they already have.
  Future<void> saveLegal({
    required String termsTitle,
    required String termsContent,
    required String privacyTitle,
    required String privacyContent,
    required String storageNotice,
  }) async {
    final version = DateTime.now().toIso8601String().split('T').first;
    Map<String, dynamic> row(String k, String v) =>
        {'setting_key': k, 'value': v, 'type': 'string', 'category': 'legal'};
    await _upsert([
      row('legal.version', version),
      row('legal.terms_title', termsTitle),
      row('legal.terms_content', termsContent),
      row('legal.privacy_title', privacyTitle),
      row('legal.privacy_content', privacyContent),
      row('legal.storage_notice', storageNotice),
    ]);
    legalVersion = version;
    this.termsTitle = termsTitle;
    this.termsContent = termsContent;
    this.privacyTitle = privacyTitle;
    this.privacyContent = privacyContent;
    this.storageNotice = storageNotice;
    notifyListeners();
  }

  /// Saves the background below the hero. [mode] picks 'photo' or 'color';
  /// both values are kept. Null [imageUrl] clears the photo.
  Future<void> saveHomeBody({
    required String? imageUrl,
    required Color color,
    required String mode,
  }) async {
    await _upsert([
      {
        'setting_key': 'homepage.body_image_url',
        'value': imageUrl,
        'type': 'string',
        'category': 'homepage',
      },
      {
        'setting_key': 'homepage.body_color',
        'value': _toHex(color),
        'type': 'string',
        'category': 'homepage',
      },
      {
        'setting_key': 'homepage.body_mode',
        'value': mode,
        'type': 'string',
        'category': 'homepage',
      },
    ]);
    homeBodyImageUrl = imageUrl;
    homeBodyColor = color;
    homeBodyMode = mode;
    notifyListeners();
  }

  /// Saves the whole-community map picture. Pass null to clear it.
  Future<void> saveCommunityMapImage(String? imageUrl) async {
    await _upsert([
      {
        'setting_key': 'community.map_image_url',
        'value': imageUrl,
        'type': 'string',
        'category': 'community',
      },
    ]);
    communityMapImageUrl = imageUrl;
    notifyListeners();
  }

  /// Saves the portal background. [mode] picks 'photo' or 'color'; both
  /// values are kept so the officer can switch back without re-uploading.
  Future<void> saveOfficerPortalBg({
    required String? imageUrl,
    required Color color,
    required String mode,
  }) async {
    await _upsert([
      {
        'setting_key': 'portal.bg_image_url',
        'value': imageUrl,
        'type': 'string',
        'category': 'branding'
      },
      {
        'setting_key': 'portal.bg_color',
        'value': _toHex(color),
        'type': 'string',
        'category': 'branding'
      },
      {
        'setting_key': 'portal.bg_mode',
        'value': mode,
        'type': 'string',
        'category': 'branding'
      },
    ]);
    portalBgMode = mode;
    portalBgImageUrl = imageUrl;
    portalBgColor = color;
    notifyListeners();
  }

  /// Saves the map pin colours (one per lot status) and diameter.
  Future<void> saveMapPins({
    required Color owned,
    required Color vacant,
    required Color occupied,
    required double pinSize,
  }) async {
    await _upsert([
      {
        'setting_key': 'map.pin_color',
        'value': _toHex(owned),
        'type': 'string',
        'category': 'map'
      },
      {
        'setting_key': 'map.pin_color_vacant',
        'value': _toHex(vacant),
        'type': 'string',
        'category': 'map'
      },
      {
        'setting_key': 'map.pin_color_occupied',
        'value': _toHex(occupied),
        'type': 'string',
        'category': 'map'
      },
      {
        'setting_key': 'map.pin_size',
        'value': pinSize.toStringAsFixed(0),
        'type': 'string',
        'category': 'map'
      },
    ]);
    pinColor = owned;
    pinColorVacant = vacant;
    pinColorOccupied = occupied;
    this.pinSize = pinSize;
    notifyListeners();
  }

  /// Saves the landing-page tagline and about text. The free-text [contact]
  /// is written only when passed; [saveContact] handles the contact fields.
  Future<void> saveHomeContent({
    required String tagline,
    required String about,
    String? contact,
  }) async {
    final updatedBy = await SupabaseService.instance.getMyUserId();
    Map<String, dynamic> row(String key, String value) => {
          'setting_key': key,
          'value': value,
          'type': 'string',
          'category': 'homepage',
          'is_public': true,
          if (updatedBy != null) 'updated_by': updatedBy,
        };
    final rows = [
      row('homepage.tagline', tagline),
      row('homepage.about', about),
      if (contact != null) row('homepage.contact', contact),
    ];
    await SupabaseService.instance.client
        .from('system_settings')
        .upsert(rows, onConflict: 'setting_key');

    homeTagline = tagline;
    homeAbout = about;
    if (contact != null) homeContact = contact;
    notifyListeners();
  }

  /// Reads 'RRGGBB', with or without '#'. Returns null if it is not valid.
  static Color? _parseHex(String hex) {
    final h = hex.replaceAll('#', '').trim();
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  /// Writes [c] as '#RRGGBB', the format stored in the settings.
  static String _toHex(Color c) {
    int channel(double v) => (v * 255).round().clamp(0, 255).toInt();
    final r = channel(c.r).toRadixString(16).padLeft(2, '0');
    final g = channel(c.g).toRadixString(16).padLeft(2, '0');
    final b = channel(c.b).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b'.toUpperCase();
  }
}
