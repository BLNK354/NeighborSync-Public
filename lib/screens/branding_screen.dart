import 'package:flutter/services.dart' show TextInputFormatter;
import '../core/address_sort.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/form_helpers.dart';
import '../core/image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException;
import '../core/branding.dart';
import '../core/phase_contacts.dart';
import '../core/permissions.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/user_guides_card.dart';
import '../widgets/office_hours_field.dart';
import '../widgets/responsive_officer_shell.dart';
import '../core/dialog_sizing.dart';
import '../core/refresh_bus.dart';
import '../widgets/phase_scope.dart' show phaseNumberOf;
import '../core/dialog_controllers.dart';
import '../core/facility_rates.dart';
import '../core/safe_state.dart';
import '../core/stored_file.dart';

/// Preset colours. Tapping one fills the hex text field.
const _presetColors = [
  Color(0xFF1A6B43), // NeighborSync green (default accent)
  Color(0xFF114D30), // NeighborSync dark green (default sidebar)
  Color(0xFF0C5C84), // blue
  Color(0xFF8A6300), // amber
  Color(0xFFA82F2F), // red
  Color(0xFF5B3A8E), // violet
  Color(0xFF1B2A22), // near-black
  Color(0xFF063A2E), // deep teal
];

/// The CMS screen, one tab per area: branding, home page, banner, rules,
/// map, official forms, facilities, categories and legal text.
/// Each section has its own Save button. Branding and page content apply
/// live through AppBranding.
class BrandingScreen extends StatefulWidget {
  const BrandingScreen({super.key});

  @override
  State<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends State<BrandingScreen> with SafeSetState<BrandingScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _monogramCtrl;
  late final TextEditingController _primaryHexCtrl;
  late final TextEditingController _sidebarHexCtrl;

  /// Null = use the letter monogram. An upload shows in the preview at once
  /// but is only applied when "Save Branding" is pressed.
  String? _logoImageUrl;
  bool _uploadingLogo = false;

  /// Landing-page hero background photo (null = fall back to the colour).
  String? _heroImageUrl;
  bool _uploadingHero = false;

  // 'photo' or 'color' for each background section. Both values are saved,
  // so switching to Colour keeps the uploaded photo for later.
  String _heroMode = 'color';
  String _homeBodyMode = 'color';
  String _portalBgMode = 'color';

  // Home page body (About-section) background photo + fallback colour.
  String? _homeBodyImageUrl;
  late final TextEditingController _homeBodyHexCtrl;
  bool _uploadingHomeBody = false;
  bool _savingHomeBody = false;

  // Map picture of the selected phase, including an upload not yet saved.
  String? _communityMapImageUrl;
  bool _uploadingCommunityMap = false;
  bool _savingCommunityMap = false;

  // Each phase has its own map (`phases.map_image_url`). A phase officer
  // edits their own; the super admin picks which one.
  /// Phase number -> its codes (e.g. '1' -> ['1A', '1B']).
  Map<String, List<String>> _phaseCodes = {};
  /// Phase number -> its saved map URL.
  Map<String, String?> _phaseMapUrls = {};
  /// The phase whose map the card is editing (null until loaded).
  String? _mapPhase;

  // Officer portal content background (photo + fallback colour).
  String? _portalBgImageUrl;
  late final TextEditingController _portalBgHexCtrl;
  bool _uploadingPortalBg = false;
  bool _savingPortalBg = false;
  late final TextEditingController _heroHexCtrl;
  bool _savingHero = false;

  // Community map pin appearance (one colour per lot status + size).
  late final TextEditingController _pinHexCtrl; // owned / default
  late final TextEditingController _pinVacantHexCtrl;
  late final TextEditingController _pinOccupiedHexCtrl;
  double _pinSize = AppBranding.defaultPinSize;
  bool _savingPins = false;

  late final TextEditingController _taglineCtrl;
  late final TextEditingController _aboutCtrl;
  late final TextEditingController _contactCtrl;
  bool _savingHome = false;

  // Structured contact block (landing page).
  late final TextEditingController _addrCtrl;
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _mapCtrl;

  /// Social accounts of the office being edited.
  List<SocialLink> _socialLinks = const [];
  bool _savingSocial = false;
  bool _savingContact = false;

  /// Whose contact details the card is editing: null = the subdivision
  /// (super admin only), otherwise a phase number. A phase officer is
  /// pinned to their own phase; the super admin picks with chips.
  String? _contactTarget;
  Map<String, PhaseContact> _phaseContacts = {};
  bool _contactTargetChosen = false;

  // Site-wide announcement banner.
  late final TextEditingController _bannerMsgCtrl;
  bool _bannerEnabled = false;
  String _bannerLevel = 'info';
  bool _savingBanner = false;

  // Community Rules / Bylaws page.
  late final TextEditingController _rulesTitleCtrl;
  late final TextEditingController _rulesContentCtrl;
  bool _savingRules = false;

  // Terms, privacy notice and browser-storage notice. Editable because they
  // are the association's own documents.
  late final TextEditingController _termsTitleCtrl;
  late final TextEditingController _termsContentCtrl;
  late final TextEditingController _privacyTitleCtrl;
  late final TextEditingController _privacyContentCtrl;
  late final TextEditingController _storageNoticeCtrl;
  bool _savingLegal = false;

  // Index of the CMS tab showing (see _tabLabels).
  int _tab = 0;

  /// Blank Complaint/Concern form (PDF or image) residents can download from
  /// File a Complaint. File is in the branding bucket; URL is in
  /// system_settings 'forms.complaint_form_url'.
  String? _complaintFormUrl;
  bool _uploadingForm = false;

  /// Other named forms residents can download. Stored as a JSON array in
  /// system_settings 'forms.official_forms' = [{name, url, path}].
  List<Map<String, dynamic>> _otherForms = [];
  bool _addingForm = false;

  bool _canEdit = false;
  bool _permsLoaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = AppBranding.instance;
    _nameCtrl = TextEditingController(text: b.communityName);
    _monogramCtrl = TextEditingController(text: b.logoMonogram);
    _primaryHexCtrl = TextEditingController(text: _toHex(b.primaryColor));
    _sidebarHexCtrl = TextEditingController(text: _toHex(b.sidebarColor));
    _taglineCtrl = TextEditingController(text: b.homeTagline);
    _aboutCtrl = TextEditingController(text: b.homeAbout);
    _contactCtrl = TextEditingController(text: b.homeContact);
    _addrCtrl = TextEditingController(text: b.contactAddress);
    _hoursCtrl = TextEditingController(text: b.contactHours);
    _emailCtrl = TextEditingController(text: b.contactEmail);
    _phoneCtrl = TextEditingController(text: b.contactPhone);
    _mapCtrl = TextEditingController(text: b.contactMapLink);
    _socialLinks = List<SocialLink>.from(b.socialLinks);
    _bannerMsgCtrl = TextEditingController(text: b.bannerMessage);
    _bannerEnabled = b.bannerEnabled;
    _bannerLevel = b.bannerLevel;
    // The dropdown fails an assertion if its value is not one of its items.
    if (!const ['info', 'warning', 'critical'].contains(_bannerLevel)) {
      _bannerLevel = 'info';
    }
    _rulesTitleCtrl = TextEditingController(text: b.rulesTitle);
    _rulesContentCtrl = TextEditingController(text: b.rulesContent);
    _termsTitleCtrl = TextEditingController(text: b.termsTitle);
    _termsContentCtrl = TextEditingController(text: b.termsContent);
    _privacyTitleCtrl = TextEditingController(text: b.privacyTitle);
    _privacyContentCtrl = TextEditingController(text: b.privacyContent);
    _storageNoticeCtrl = TextEditingController(text: b.storageNotice);
    _heroHexCtrl = TextEditingController(text: _toHex(b.heroColor));
    _heroImageUrl = b.heroImageUrl;
    _homeBodyImageUrl = b.homeBodyImageUrl;
    _homeBodyHexCtrl = TextEditingController(text: _toHex(b.homeBodyColor));
    _communityMapImageUrl = b.communityMapImageUrl;
    _portalBgImageUrl = b.portalBgImageUrl;
    _portalBgHexCtrl = TextEditingController(text: _toHex(b.portalBgColor));
    _logoImageUrl = b.logoImageUrl;
    _pinHexCtrl = TextEditingController(text: _toHex(b.pinColor));
    _pinVacantHexCtrl = TextEditingController(text: _toHex(b.pinColorVacant));
    _pinOccupiedHexCtrl = TextEditingController(text: _toHex(b.pinColorOccupied));
    _pinSize = b.pinSize;
    _heroMode = b.heroMode;
    _homeBodyMode = b.homeBodyMode;
    _portalBgMode = b.portalBgMode;
    _loadPerms();
    _loadPhaseMaps();
    // The super admin's phase switcher changes which phase this card edits.
    RefreshBus.bind(this, _loadPhaseMaps);
  }

  /// Loads each phase's map and contact details, then picks the phase the
  /// map card edits: the phase officer's own, or the one the super admin views.
  Future<void> _loadPhaseMaps() async {
    try {
      final client = SupabaseService.instance.client;
      final role = await SupabaseService.instance.getMyRole();
      final me = await client
          .from('users')
          .select('phase, viewing_phase')
          .eq('supabase_uid', client.auth.currentUser?.id ?? '')
          .maybeSingle();
      final rows = await client
          .from('phases')
          .select('code, number, map_image_url, is_active')
          .order('code');
      final codes = <String, List<String>>{};
      final urls = <String, String?>{};
      for (final r in sortPhaseRows(rows as List)) {
        if (r['is_active'] == false) continue;
        final n = r['number'].toString();
        codes.putIfAbsent(n, () => []).add(r['code'].toString());
        final u = (r['map_image_url'] ?? '').toString();
        if (u.isNotEmpty && (urls[n] ?? '').isEmpty) urls[n] = u;
        urls.putIfAbsent(n, () => null);
      }
      final superAdmin = role == 'super_admin';
      final own = (me?['phase'] ?? '').toString();
      final viewing = (me?['viewing_phase'] ?? '').toString();
      String? pick;
      if (superAdmin && viewing.isNotEmpty) {
        pick = phaseNumberOf(viewing);
      } else if (!superAdmin && own.isNotEmpty) {
        pick = phaseNumberOf(own);
      }
      if (pick == null || !codes.containsKey(pick)) {
        final nums = codes.keys.toList()..sort(_byNumber);
        pick = superAdmin && nums.isNotEmpty
            ? (codes.containsKey(_mapPhase) ? _mapPhase : nums.first)
            : null;
      }
      Map<String, PhaseContact> contacts = {};
      try {
        contacts = await loadPhaseContacts();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _isSuperAdmin = superAdmin;
        _phaseCodes = codes;
        _phaseMapUrls = urls;
        _mapPhase = pick;
        _communityMapImageUrl = pick == null ? null : urls[pick];
        _phaseContacts = contacts;
      });
      // First load only: a phase officer starts on their own phase, the super
      // admin on the subdivision. Reloads must not replace what is being edited.
      if (!_contactTargetChosen) {
        _contactTargetChosen = true;
        _selectContactTarget(
            superAdmin || own.isEmpty ? null : phaseNumberOf(own));
      }
    } catch (_) {
      // Leave the card on its "no phase" message rather than failing the CMS.
    }
  }

  /// Fills the contact fields and social list from the chosen target.
  void _selectContactTarget(String? number) {
    final b = AppBranding.instance;
    final c = number == null ? null : _phaseContacts[number];
    setState(() {
      _contactTarget = number;
      _addrCtrl.text = c?.address ?? (number == null ? b.contactAddress : '');
      _hoursCtrl.text = c?.hours ?? (number == null ? b.contactHours : '');
      _phoneCtrl.text = c?.phone ?? (number == null ? b.contactPhone : '');
      _emailCtrl.text = c?.email ?? (number == null ? b.contactEmail : '');
      _mapCtrl.text = c?.mapLink ?? (number == null ? b.contactMapLink : '');
      _socialLinks = List<SocialLink>.from(
          c?.socialLinks ?? (number == null ? b.socialLinks : const []));
    });
  }

  /// The subdivision's details are the super admin's alone (enforced by
  /// trg_protect_subdivision_contact); a phase's are its own officers'.
  bool get _canEditContact =>
      _canEdit && (_contactTarget != null || _isSuperAdmin);

  static int _byNumber(String a, String b) =>
      (int.tryParse(a) ?? 999).compareTo(int.tryParse(b) ?? 999);

  void _selectMapPhase(String n) {
    setState(() {
      _mapPhase = n;
      // Switching phase discards an unsaved upload for the previous one.
      _communityMapImageUrl = _phaseMapUrls[n];
    });
  }

  Future<void> _loadPerms() async {
    final perms = await SupabaseService.instance.getMyPermissions();
    if (!mounted) return;
    setState(() {
      _canEdit = canPerform(perms, 'system_settings', 'update');
      // Must match the database: facilities are written on reservations:update,
      // not system_settings, or Save buttons appear that the database refuses.
      _canManageFacilities = canPerform(perms, 'reservations', 'update');
      // Two separate permissions in the database (permits:update and
      // violations:update), so keep two flags even if the same roles hold both.
      _canManagePermitTypes = canPerform(perms, 'permits', 'update');
      _canManageViolationTypes = canPerform(perms, 'violations', 'update');
      _permsLoaded = true;
    });
    _loadFormUrl();
    _loadFacilities();
    _loadTypes();
  }

  // ---------------- Permit & violation categories ----------------

  /// The choices behind "Select Permit Type" and the violation types an
  /// officer picks when issuing one. Not phase-scoped: one set of categories
  /// for the whole subdivision.
  List<Map<String, dynamic>> _permitTypes = [];
  List<Map<String, dynamic>> _violationTypes = [];
  bool _typesLoading = true;
  bool _canManagePermitTypes = false;
  bool _canManageViolationTypes = false;

  Future<void> _loadTypes() async {
    try {
      final c = SupabaseService.instance.client;
      final results = await Future.wait<dynamic>([
        c.from('permit_types').select('*').order('name'),
        c.from('violation_types').select('*').order('name'),
      ]);
      if (!mounted) return;
      setState(() {
        _permitTypes = List<Map<String, dynamic>>.from(results[0] as List);
        _violationTypes = List<Map<String, dynamic>>.from(results[1] as List);
        _typesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _typesLoading = false);
    }
  }

  // ---------------- Facilities ----------------

  /// Amenities residents can reserve, and what each one costs.
  List<Map<String, dynamic>> _facilities = [];
  List<Map<String, dynamic>> _phases = [];
  String? _myPhase;
  bool _isSuperAdmin = false;
  bool _facLoading = true;
  bool _canManageFacilities = false;

  Future<void> _loadFacilities() async {
    try {
      final c = SupabaseService.instance.client;
      final uid = c.auth.currentUser?.id;
      final results = await Future.wait<dynamic>([
        // RLS already narrows this to what the caller may see: their own
        // phase's amenities plus every shared one.
        c.from('facilities').select('*').order('phase', ascending: true).order('name'),
        c.from('phases').select('code, name, number').eq('is_active', true).order('code'),
        if (uid != null)
          c.from('users').select('phase').eq('supabase_uid', uid).maybeSingle()
        else
          Future.value(null),
        SupabaseService.instance.getMyRole(),
      ]);
      if (!mounted) return;
      final me = results[2] as Map<String, dynamic>?;
      setState(() {
        _facilities = List<Map<String, dynamic>>.from(results[0] as List);
        _phases = sortPhaseRows(results[1] as List);
        _myPhase = (me?['phase'] as String?)?.trim();
        _isSuperAdmin = (results[3] as String?) == 'super_admin';
        _facLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _facLoading = false);
    }
  }

  /// The scopes this officer may save: shared, plus their own phase (all
  /// phases for the super admin). Must match the `phase_isolation` policy,
  /// or the save is refused.
  List<Map<String, dynamic>> get _writableScopes {
    // null code == shared with every phase.
    final out = <Map<String, dynamic>>[
      {'code': null, 'label': 'Shared — any phase can book'}
    ];
    final myNumber = (_myPhase ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    for (final p in _phases) {
      final code = (p['code'] ?? '').toString();
      final number = (p['number'] ?? '').toString();
      if (_isSuperAdmin || (myNumber.isNotEmpty && number == myNumber)) {
        out.add({'code': code, 'label': 'Phase $code only'});
      }
    }
    return out;
  }

  String _scopeLabel(Map<String, dynamic> f) {
    final p = (f['phase'] ?? '').toString().trim();
    return p.isEmpty ? 'Shared' : 'Phase $p';
  }

  /// Loads the complaint form URL and the list of other forms.
  Future<void> _loadFormUrl() async {
    try {
      final rows = await SupabaseService.instance.client
          .from('system_settings')
          .select('setting_key, value')
          .inFilter('setting_key', ['forms.complaint_form_url', 'forms.official_forms']);
      if (!mounted) return;
      String? complaintUrl;
      List<Map<String, dynamic>> others = [];
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final v = r['value'] as String?;
        if (r['setting_key'] == 'forms.complaint_form_url') {
          complaintUrl = (v == null || v.isEmpty) ? null : v;
        } else if (r['setting_key'] == 'forms.official_forms' && v != null && v.isNotEmpty) {
          try {
            others = List<Map<String, dynamic>>.from(jsonDecode(v) as List);
          } catch (_) {}
        }
      }
      setState(() {
        _complaintFormUrl = complaintUrl;
        _otherForms = others;
      });
    } catch (_) {
      // The section simply shows "no file uploaded".
    }
  }

  /// Writes the current list of other forms to system_settings.
  Future<void> _saveOtherForms() async {
    final updatedBy = await SupabaseService.instance.getMyUserId();
    await SupabaseService.instance.client.from('system_settings').upsert({
      'setting_key': 'forms.official_forms',
      'value': jsonEncode(_otherForms),
      'type': 'json',
      'category': 'forms',
      'is_public': true,
      if (updatedBy != null) 'updated_by': updatedBy,
    }, onConflict: 'setting_key');
  }

  /// Asks for a form name and a file, uploads it, and adds it to the list.
  Future<void> _addOtherForm() async {
    final nameCtrl = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Official Form'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Form name', hintText: 'e.g. Move-Out Clearance Form'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Choose File')),
        ],
      ),
    );
    if (proceed != true || nameCtrl.text.trim().isEmpty) return;
    final name = nameCtrl.text.trim();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
      withData: true,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      AppToast.error(context, message: 'Could not read that file.');
      return;
    }
    final ext = (file.extension ?? 'pdf').toLowerCase();
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final path = 'forms/$slug-${DateTime.now().millisecondsSinceEpoch}.$ext';
    setState(() => _addingForm = true);
    try {
      final client = SupabaseService.instance.client;
      await client.storage.from('branding').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
                upsert: true,
                contentType: ext == 'pdf' ? 'application/pdf' : _contentTypeFor(ext)),
          );
      final url = client.storage.from('branding').getPublicUrl(path);
      _otherForms.add({'name': name, 'url': url, 'path': path});
      await _saveOtherForms();
      if (!mounted) return;
      setState(() => _addingForm = false);
      AppToast.success(context, message: '"$name" added -- residents can download it.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingForm = false);
      AppToast.error(context, message: 'Upload failed. ${friendlyError(e)}');
    }
  }

  /// After confirming, deletes the form's file and removes it from the list.
  Future<void> _deleteOtherForm(int index) async {
    final form = _otherForms[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove form?'),
        content: Text('"${form['name']}" will no longer be available to residents.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final path = form['path'] as String?;
      if (path != null) {
        await SupabaseService.instance.client.storage.from('branding').remove([path]);
      }
      setState(() => _otherForms.removeAt(index));
      await _saveOtherForms();
      if (mounted) AppToast.success(context, message: 'Form removed.');
    } catch (e) {
      if (mounted) AppToast.error(context, message: 'Could not remove. ${friendlyError(e)}');
    }
  }

  /// Renames a form. Only the label changes; the file and its URL stay.
  Future<void> _renameOtherForm(int index) async {
    final form = _otherForms[index];
    final ctrl = TextEditingController(text: (form['name'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename form'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Form name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final newName = ctrl.text.trim();
    if (newName.isEmpty) return;
    try {
      setState(() => _otherForms[index] = {..._otherForms[index], 'name': newName});
      await _saveOtherForms();
      if (mounted) AppToast.success(context, message: 'Renamed to "$newName".');
    } catch (e) {
      if (mounted) AppToast.error(context, message: 'Could not rename. ${friendlyError(e)}');
    }
  }

  /// Swaps a form's file, keeping its name and position. The new file gets a
  /// timestamped path so nobody is served a cached copy; the old one is deleted.
  Future<void> _replaceOtherForm(int index) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
      withData: true,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      AppToast.error(context, message: 'Could not read that file.');
      return;
    }
    final form = _otherForms[index];
    final name = (form['name'] ?? 'form').toString();
    final oldPath = form['path'] as String?;
    final ext = (file.extension ?? 'pdf').toLowerCase();
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final path = 'forms/$slug-${DateTime.now().millisecondsSinceEpoch}.$ext';

    setState(() => _addingForm = true);
    try {
      final client = SupabaseService.instance.client;
      await client.storage.from('branding').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
                upsert: true,
                contentType: ext == 'pdf' ? 'application/pdf' : _contentTypeFor(ext)),
          );
      final url = client.storage.from('branding').getPublicUrl(path);
      _otherForms[index] = {'name': name, 'url': url, 'path': path};
      await _saveOtherForms();

      // Best effort: a leftover old file is harmless.
      if (oldPath != null && oldPath != path) {
        try {
          await client.storage.from('branding').remove([oldPath]);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _addingForm = false);
      AppToast.success(context, message: '"$name" updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingForm = false);
      AppToast.error(context, message: 'Upload failed. ${friendlyError(e)}');
    }
  }

  /// Opens a form so an officer can check they uploaded the right file.
  Future<void> _previewForm(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      await openStoredFile(context, publicUrl: url);
    } catch (e) {
      if (mounted) AppToast.error(context, message: 'Could not open. ${friendlyError(e)}');
    }
  }

  /// Removes the Complaint/Concern form. An empty setting means "no form
  /// available" to the resident screens.
  Future<void> _removeComplaintForm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove complaint form?'),
        content: const Text(
            'Residents will no longer see a printable form on the File a Complaint '
            'screen. Filing a complaint online is unaffected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _uploadingForm = true);
    try {
      final client = SupabaseService.instance.client;
      final updatedBy = await SupabaseService.instance.getMyUserId();
      await client.from('system_settings').upsert({
        'setting_key': 'forms.complaint_form_url',
        'value': '',
        'type': 'string',
        'category': 'forms',
        'is_public': true,
        if (updatedBy != null) 'updated_by': updatedBy,
      }, onConflict: 'setting_key');

      // The file lives at a fixed path per extension; clear the likely ones.
      try {
        await client.storage.from('branding').remove([
          'forms/complaint-form.pdf',
          'forms/complaint-form.png',
          'forms/complaint-form.jpg',
          'forms/complaint-form.jpeg',
        ]);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _complaintFormUrl = null;
        _uploadingForm = false;
      });
      AppToast.success(context, message: 'Complaint form removed.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingForm = false);
      AppToast.error(context, message: 'Could not remove. ${friendlyError(e)}');
    }
  }

  /// Uploads the complaint form to a fixed path per extension and saves its URL.
  Future<void> _uploadComplaintForm() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      AppToast.error(context, message: 'Could not read that file.');
      return;
    }
    final ext = (file.extension ?? 'pdf').toLowerCase();
    final path = 'forms/complaint-form.$ext';
    setState(() => _uploadingForm = true);
    try {
      final client = SupabaseService.instance.client;
      await client.storage.from('branding').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
                upsert: true,
                contentType: ext == 'pdf' ? 'application/pdf' : _contentTypeFor(ext)),
          );
      final url =
          '${client.storage.from('branding').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      final updatedBy = await SupabaseService.instance.getMyUserId();
      await client.from('system_settings').upsert({
        'setting_key': 'forms.complaint_form_url',
        'value': url,
        'type': 'string',
        'category': 'forms',
        'is_public': true,
        if (updatedBy != null) 'updated_by': updatedBy,
      }, onConflict: 'setting_key');
      if (!mounted) return;
      setState(() {
        _complaintFormUrl = url;
        _uploadingForm = false;
      });
      AppToast.success(context,
          message: 'Official form uploaded -- residents can now download it.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingForm = false);
      AppToast.error(context, message: 'Upload failed. ${friendlyError(e)}');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _monogramCtrl.dispose();
    _primaryHexCtrl.dispose();
    _sidebarHexCtrl.dispose();
    _taglineCtrl.dispose();
    _aboutCtrl.dispose();
    _contactCtrl.dispose();
    _addrCtrl.dispose();
    _hoursCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _mapCtrl.dispose();
    _bannerMsgCtrl.dispose();
    _rulesTitleCtrl.dispose();
    _rulesContentCtrl.dispose();
    _termsTitleCtrl.dispose();
    _termsContentCtrl.dispose();
    _privacyTitleCtrl.dispose();
    _privacyContentCtrl.dispose();
    _storageNoticeCtrl.dispose();
    _heroHexCtrl.dispose();
    _pinHexCtrl.dispose();
    _pinVacantHexCtrl.dispose();
    _pinOccupiedHexCtrl.dispose();
    _homeBodyHexCtrl.dispose();
    _portalBgHexCtrl.dispose();
    super.dispose();
  }

  static String _toHex(Color c) {
    int channel(double v) => (v * 255).round().clamp(0, 255).toInt();
    final r = channel(c.r).toRadixString(16).padLeft(2, '0');
    final g = channel(c.g).toRadixString(16).padLeft(2, '0');
    final b = channel(c.b).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b'.toUpperCase();
  }

  static Color? _parseHex(String hex) {
    final h = hex.replaceAll('#', '').trim();
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  /// Image content type for a file extension; anything unknown counts as PNG.
  static String _contentTypeFor(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'svg':
        return 'image/svg+xml';
      case 'png':
      default:
        return 'image/png';
    }
  }

  Color get _previewPrimary => _parseHex(_primaryHexCtrl.text) ?? AppBranding.instance.primaryColor;
  Color get _previewSidebar => _parseHex(_sidebarHexCtrl.text) ?? AppBranding.instance.sidebarColor;

  /// Picks and uploads the logo to a fixed path, so a new upload replaces the
  /// old file. The `?v=` on the URL makes the new image show instead of a cached one.
  Future<void> _pickAndUploadLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true, // required on web -- there's no filesystem path to read from
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      AppToast.error(context, message: 'Could not read that file -- try a different image.');
      return;
    }

    // A small cap is enough for a logo. Transparency is kept: compressImageBytes
    // writes PNG when the image has an alpha channel.
    final prepared = _prepareImage(bytes, file.name, maxEdge: kMaxAvatarEdge);
    final ext = prepared.ext;
    final path = 'logo/community-logo.$ext';

    setState(() => _uploadingLogo = true);
    try {
      final client = SupabaseService.instance.client;
      await client.storage.from('branding').uploadBinary(
            path,
            prepared.bytes,
            fileOptions: FileOptions(upsert: true, contentType: _contentTypeFor(ext)),
          );
      final publicUrl = client.storage.from('branding').getPublicUrl(path);
      final freshUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      if (!mounted) return;
      setState(() {
        _logoImageUrl = freshUrl;
        _uploadingLogo = false;
      });
      AppToast.success(context, message: 'Logo uploaded -- click Save Branding to apply it.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingLogo = false);
      AppToast.error(context, message: 'Upload failed. ${friendlyError(e)}');
    }
  }

  /// Switches back to the letter monogram. The uploaded file is not deleted.
  void _removeLogo() {
    setState(() => _logoImageUrl = null);
  }

  /// Checks and saves the branding fields; the app re-themes straight away.
  Future<void> _save() async {
    final primary = _parseHex(_primaryHexCtrl.text);
    final sidebar = _parseHex(_sidebarHexCtrl.text);
    final name = _nameCtrl.text.trim();
    final monogram = _monogramCtrl.text.trim();
    if (primary == null || sidebar == null) {
      AppToast.error(context, message: 'Colors must be a 6-digit hex code, e.g. #1A6B43.');
      return;
    }
    if (name.isEmpty || monogram.isEmpty) {
      AppToast.error(context, message: 'Community name and logo monogram can\'t be empty.');
      return;
    }
    setState(() => _saving = true);
    try {
      await AppBranding.instance.save(
        communityName: name,
        logoMonogram: monogram,
        primaryColor: primary,
        sidebarColor: sidebar,
        logoImageUrl: _logoImageUrl,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.success(context, message: 'Branding updated -- applied instantly across the app.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, message: 'Could not save. ${friendlyError(e)}');
    }
  }

  Future<void> _saveHomeContent() async {
    final tagline = _taglineCtrl.text.trim();
    final about = _aboutCtrl.text.trim();
    if (tagline.isEmpty || about.isEmpty) {
      AppToast.error(context, message: 'Tagline and About text can\'t be empty.');
      return;
    }
    setState(() => _savingHome = true);
    try {
      await AppBranding.instance.saveHomeContent(tagline: tagline, about: about);
      if (!mounted) return;
      setState(() => _savingHome = false);
      AppToast.success(context, message: 'Home page updated -- visible on the public front page.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingHome = false);
      AppToast.error(context, message: 'Could not save. ${friendlyError(e)}');
    }
  }

  /// Saves the contact fields to the subdivision or the selected phase.
  Future<void> _saveContact() async {
    setState(() => _savingContact = true);
    try {
      final target = _contactTarget;
      if (target == null) {
        await AppBranding.instance.saveContact(
          address: _addrCtrl.text.trim(),
          hours: _hoursCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          mapLink: _mapCtrl.text.trim(),
        );
      } else {
        // Social links go back unchanged; their own buttons save them.
        final next = PhaseContact(
          number: target,
          address: _addrCtrl.text.trim(),
          hours: _hoursCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          mapLink: _mapCtrl.text.trim(),
          socialLinks: _phaseContacts[target]?.socialLinks ?? const [],
        );
        await savePhaseContact(next);
        _phaseContacts = {..._phaseContacts, target: next};
      }
      if (!mounted) return;
      setState(() => _savingContact = false);
      AppToast.success(context,
          message: target == null
              ? 'Subdivision contact details saved.'
              : 'Phase $target contact details saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingContact = false);
      AppToast.error(context, message: 'Could not save. ${friendlyError(e)}');
    }
  }

  Future<void> _saveBanner() async {
    setState(() => _savingBanner = true);
    try {
      await AppBranding.instance.saveBanner(
        enabled: _bannerEnabled,
        message: _bannerMsgCtrl.text.trim(),
        level: _bannerLevel,
      );
      if (!mounted) return;
      setState(() => _savingBanner = false);
      AppToast.success(context,
          message: _bannerEnabled ? 'Banner is now live on every screen.' : 'Banner turned off.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingBanner = false);
      AppToast.error(context, message: 'Could not save. ${friendlyError(e)}');
    }
  }

  /// Shrinks a picked image and returns the bytes plus the extension to store
  /// them under. Re-encoding can change the format, so always use this
  /// extension or the file is served with the wrong content type.
  ({Uint8List bytes, String ext}) _prepareImage(
    Uint8List bytes,
    String filename, {
    int maxEdge = kMaxPhotoEdge,
  }) {
    final out = compressImageBytes(bytes, filename, maxEdge: maxEdge);
    final dot = out.filename.lastIndexOf('.');
    final ext =
        dot < 0 ? 'jpg' : out.filename.substring(dot + 1).toLowerCase();
    return (bytes: out.bytes, ext: ext);
  }

  /// Uploads the landing-page hero photo to a fixed path, so a new upload
  /// replaces the old file. Applied when Save Background is pressed.
  Future<void> _pickAndUploadHero() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      AppToast.error(context, message: 'Could not read that image -- try another one.');
      return;
    }
    final prepared = _prepareImage(bytes, file.name);
    final ext = prepared.ext;
    final path = 'hero/home-hero.$ext';
    setState(() => _uploadingHero = true);
    try {
      final client = SupabaseService.instance.client;
      await client.storage.from('branding').uploadBinary(
            path,
            prepared.bytes,
            fileOptions: FileOptions(upsert: true, contentType: _contentTypeFor(ext)),
          );
      final url =
          '${client.storage.from('branding').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      if (!mounted) return;
      setState(() {
        _heroImageUrl = url;
        _uploadingHero = false;
      });
      AppToast.success(context, message: 'Background uploaded -- click Save Background to apply.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingHero = false);
      AppToast.error(context, message: 'Upload failed. ${friendlyError(e)}');
    }
  }

  Future<void> _saveHero() async {
    final color = _parseHex(_heroHexCtrl.text);
    if (color == null) {
      AppToast.error(context, message: 'Background colour must be a 6-digit hex, e.g. #114D30.');
      return;
    }
    setState(() => _savingHero = true);
    try {
      await AppBranding.instance
          .saveHero(imageUrl: _heroImageUrl, color: color, mode: _heroMode);
      if (!mounted) return;
      setState(() => _savingHero = false);
      AppToast.success(context, message: 'Front page background updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingHero = false);
      AppToast.error(context, message: 'Could not save. ${friendlyError(e)}');
    }
  }

  Future<void> _pickAndUploadHomeBody() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      AppToast.error(context, message: 'Could not read that image -- try another one.');
      return;
    }
    final prepared = _prepareImage(bytes, file.name);
    final ext = prepared.ext;
    final path = 'home-body/home-body.$ext';
    setState(() => _uploadingHomeBody = true);
    try {
      final client = SupabaseService.instance.client;
      await client.storage.from('branding').uploadBinary(
            path,
            prepared.bytes,
            fileOptions: FileOptions(upsert: true, contentType: _contentTypeFor(ext)),
          );
      final url =
          '${client.storage.from('branding').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      if (!mounted) return;
      setState(() {
        _homeBodyImageUrl = url;
        _uploadingHomeBody = false;
      });
      AppToast.success(context, message: 'Body photo uploaded -- click Save to apply.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingHomeBody = false);
      AppToast.error(context, message: 'Upload failed. ${friendlyError(e)}');
    }
  }

  Future<void> _saveHomeBody() async {
    final color = _parseHex(_homeBodyHexCtrl.text);
    if (color == null) {
      AppToast.error(context, message: 'Body colour must be a 6-digit hex, e.g. #FFFFFF.');
      return;
    }
    setState(() => _savingHomeBody = true);
    try {
      await AppBranding.instance.saveHomeBody(
          imageUrl: _homeBodyImageUrl, color: color, mode: _homeBodyMode);
      if (!mounted) return;
      setState(() => _savingHomeBody = false);
      AppToast.success(context, message: 'Home page body background updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingHomeBody = false);
      AppToast.error(context, message: 'Could not save. ${friendlyError(e)}');
    }
  }

  Future<void> _saveRules() async {
    final title = _rulesTitleCtrl.text.trim();
    if (title.isEmpty) {
      AppToast.error(context, message: 'Give the rules page a title.');
      return;
    }
    setState(() => _savingRules = true);
    try {
      await AppBranding.instance.saveRules(title: title, content: _rulesContentCtrl.text.trim());
      if (!mounted) return;
      setState(() => _savingRules = false);
      AppToast.success(context, message: 'Community rules saved -- residents can read them.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingRules = false);
      AppToast.error(context, message: 'Could not save. ${friendlyError(e)}');
    }
  }

  Future<void> _saveLegal() async {
    // The register checkbox reads these titles ("I agree to the ___"), so
    // neither may be empty.
    if (_termsTitleCtrl.text.trim().isEmpty ||
        _privacyTitleCtrl.text.trim().isEmpty) {
      AppToast.error(context, message: 'Both documents need a title.');
      return;
    }
    setState(() => _savingLegal = true);
    try {
      await AppBranding.instance.saveLegal(
        termsTitle: _termsTitleCtrl.text.trim(),
        termsContent: _termsContentCtrl.text.trim(),
        privacyTitle: _privacyTitleCtrl.text.trim(),
        privacyContent: _privacyContentCtrl.text.trim(),
        storageNotice: _storageNoticeCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _savingLegal = false);
      AppToast.success(context,
          message: 'Saved as version ${AppBranding.instance.legalVersion}. '
              'People who sign up from now on agree to this version.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingLegal = false);
      AppToast.error(context, message: 'Could not save. ${friendlyError(e)}');
    }
  }

  void _resetToDefaults() {
    setState(() {
      _nameCtrl.text = AppBranding.defaultCommunityName;
      _monogramCtrl.text = AppBranding.defaultLogoMonogram;
      _primaryHexCtrl.text = _toHex(AppBranding.defaultPrimaryColor);
      _sidebarHexCtrl.text = _toHex(AppBranding.defaultSidebarColor);
      _logoImageUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveOfficerShell(
      title: 'CMS',
      activeItem: 'CMS',
      activeTab: 'Home',
      desktopChild: _body(),
    );
  }

  Widget _facilitiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Facilities & Rates',
          'Amenities residents can reserve, what each one costs, and whether it is '
          'shared with every phase or belongs to one. Changes apply to the booking '
          'screens immediately.',
        ),
        _cardBox([
        if (_permsLoaded && !_canManageFacilities)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.badgeAmberBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.lock_outline, size: 16, color: AppColors.badgeAmberText),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Read-only. Only the HOA President, Secretary or Super Admin can '
                  'add or change facilities.',
                  style: TextStyle(fontSize: 12, color: AppColors.badgeAmberText),
                ),
              ),
            ]),
          ),
        if (_facLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (_facilities.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'No facilities yet. Add one and residents will be able to reserve it.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            )
          else
            for (final f in _facilities) _facilityRow(f),
          const SizedBox(height: 14),
          if (_canManageFacilities)
            FilledButton.icon(
              onPressed: () => _facilityDialog(null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Facility'),
            ),
        ],
        ]),
      ],
    );
  }

  Widget _facilityRow(Map<String, dynamic> f) {
    final shared = (f['phase'] ?? '').toString().trim().isEmpty;
    final active = f['is_active'] != false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text((f['name'] ?? '').toString(),
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: active ? AppColors.textPrimary : AppColors.textMuted)),
                    _facChip(_scopeLabel(f),
                        shared ? AppColors.badgeBlueBg : AppColors.highlight,
                        shared ? AppColors.badgeBlueText : AppColors.textSecondary),
                    if (!active) _facChip('Hidden', AppColors.badgeGrayBg, AppColors.textSecondary),
                  ],
                ),
                const SizedBox(height: 6),
                for (final line in facilityRateLines(f))
                  Text(line,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  'Up to ${f['capacity'] ?? '—'} people'
                  '  ·  ${_timeText(f['open_time'])}–${_timeText(f['close_time'])}'
                  '${f['requires_approval'] == false ? '  ·  no approval needed' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
                if ((f['description'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text((f['description']).toString(),
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
          if (_canManageFacilities)
            TextButton(
              onPressed: () => _facilityDialog(f),
              child: const Text('Edit'),
            ),
        ],
      ),
    );
  }

  Widget _facChip(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
      );

  static String _timeText(Object? t) {
    final s = (t ?? '').toString();
    return s.length >= 5 ? s.substring(0, 5) : '—';
  }

  Widget _pair(Widget a, Widget b) => Row(children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ]);

  Widget _moneyField(TextEditingController c, String label, {String? hint}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: moneyInputFormatters,
        decoration: InputDecoration(labelText: label, hintText: hint),
      );

  Widget _numField(TextEditingController c, String label, {String? hint}) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, hintText: hint),
      );

  /// Add or edit one facility. [existing] null = create.
  Future<void> _facilityDialog(Map<String, dynamic>? existing) async {
    final isNew = existing == null;
    final name = TextEditingController(text: (existing?['name'] ?? '').toString());
    final desc = TextEditingController(text: (existing?['description'] ?? '').toString());
    final capacity =
        TextEditingController(text: (existing?['capacity'] ?? '').toString().replaceAll('null', ''));
    final fee = TextEditingController(
        text: ((existing?['fee'] as num?)?.toStringAsFixed(2) ?? '0.00'));
    TextEditingController money(String key) => TextEditingController(
        text: existing?[key] == null ? '' : (existing![key] as num).toStringAsFixed(2));
    final memberRate = money('member_rate');
    final memberWeekend = money('member_rate_weekend');
    final guestRate = money('guest_rate');
    final guestWeekend = money('guest_rate_weekend');
    final memberChild = money('member_child_rate');
    final guestChild = money('guest_child_rate');
    final bond = TextEditingController(
        text: ((existing?['cash_bond'] as num?) ?? 0) == 0
            ? ''
            : (existing!['cash_bond'] as num).toStringAsFixed(2));
    final includedHours = TextEditingController(
        text: existing?['included_hours'] == null
            ? ''
            : (existing!['included_hours'] as num).toString());
    final memberExt = money('member_extension_rate');
    final guestExt = money('guest_extension_rate');
    // 'simple' = one fee for everyone; the rest use homeowner / non-homeowner
    // rates (see core/facility_rates.dart).
    var pricing = (existing?['member_rate'] == null && existing?['guest_rate'] == null)
        ? 'simple'
        : (existing?['rate_type'] ?? 'flat').toString();
    final open = TextEditingController(text: _timeText(existing?['open_time'] ?? '06:00'));
    final close = TextEditingController(text: _timeText(existing?['close_time'] ?? '22:00'));
    final advance =
        TextEditingController(text: (existing?['max_advance_days'] ?? 90).toString());
    final notice =
        TextEditingController(text: (existing?['min_notice_hours'] ?? 24).toString());

    String? scope = isNew ? null : (existing['phase'] as String?)?.trim();
    if (scope != null && scope.isEmpty) scope = null;
    var requiresApproval = existing?['requires_approval'] != false;
    var isActive = existing?['is_active'] != false;
    var busy = false;
    String? error;

    final scopes = _writableScopes;
    // An officer may be editing a facility whose scope they cannot write --
    // keep the current value selectable so the dropdown is not blank.
    if (!scopes.any((s) => s['code'] == scope)) {
      scopes.add({'code': scope, 'label': scope == null ? 'Shared' : 'Phase $scope'});
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(isNew ? 'Add facility' : 'Edit facility'),
          content: SizedBox(
            width: dialogContentWidth(context, 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Name', hintText: 'e.g. Covered Court'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: desc,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'What it is and any house rules'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: scope,
                    decoration: const InputDecoration(labelText: 'Who can book it'),
                    items: [
                      for (final s in scopes)
                        DropdownMenuItem<String?>(
                            value: s['code'] as String?, child: Text(s['label'] as String)),
                    ],
                    onChanged: (v) => setLocal(() => scope = v),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'A shared facility appears for residents of every phase and its '
                    'bookings sit on one calendar, so two phases cannot double-book it.',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: pricing,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'How it is priced'),
                    items: const [
                      DropdownMenuItem(value: 'simple', child: Text('One price for everyone')),
                      DropdownMenuItem(value: 'flat', child: Text('Per booking (homeowner / non-homeowner)')),
                      DropdownMenuItem(value: 'per_hour', child: Text('Per hour (homeowner / non-homeowner)')),
                      DropdownMenuItem(value: 'per_head', child: Text('Per person (homeowner / non-homeowner)')),
                    ],
                    onChanged: (v) => setLocal(() => pricing = v ?? pricing),
                  ),
                  const SizedBox(height: 12),
                  if (pricing == 'simple')
                    _pair(_moneyField(fee, 'Rate (₱)', hint: '0.00 for free'),
                        _numField(capacity, 'Capacity'))
                  else ...[
                    _pair(_moneyField(memberRate, 'Homeowner, weekdays'),
                        _moneyField(memberWeekend, 'Homeowner, weekends', hint: 'Same as weekdays')),
                    const SizedBox(height: 12),
                    _pair(_moneyField(guestRate, 'Non-homeowner, weekdays'),
                        _moneyField(guestWeekend, 'Non-homeowner, weekends', hint: 'Same as weekdays')),
                    if (pricing == 'per_head') ...[
                      const SizedBox(height: 12),
                      _pair(_moneyField(memberChild, 'Homeowner, per kid'),
                          _moneyField(guestChild, 'Non-homeowner, per kid')),
                    ],
                    if (pricing == 'flat') ...[
                      const SizedBox(height: 12),
                      _pair(_numField(includedHours, 'Hours included', hint: 'Blank = no extension'),
                          const SizedBox.shrink()),
                      const SizedBox(height: 12),
                      _pair(_moneyField(memberExt, 'Extension / hr, homeowner'),
                          _moneyField(guestExt, 'Extension / hr, non-homeowner')),
                    ],
                    const SizedBox(height: 12),
                    _pair(_moneyField(bond, 'Cash bond (refundable)', hint: '0 for none'),
                        _numField(capacity, 'Capacity')),
                    const SizedBox(height: 6),
                    Text(
                      pricing == 'per_hour'
                          ? 'Rate × hours booked (rounded up).'
                          : pricing == 'per_head'
                              ? 'Rate per adult plus the kid rate per kid.'
                              : 'One rental per booking, plus the extension rate for each hour past the hours included.',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.45),
                    ),
                    const Text(
                      'Homeowner rate = has a home on record, is not a tenant, and has no overdue bills. '
                      'Everyone else pays the non-homeowner rate. The cash bond is added to the bill.',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.45),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: open,
                        decoration: const InputDecoration(
                            labelText: 'Opens', hintText: '06:00'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: close,
                        decoration: const InputDecoration(
                            labelText: 'Closes', hintText: '22:00'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: advance,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Book up to (days ahead)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: notice,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Min notice (hours)'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: requiresApproval,
                    onChanged: (v) => setLocal(() => requiresApproval = v),
                    title: const Text('Needs officer approval',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Off means a resident\'s booking is confirmed instantly.',
                        style: TextStyle(fontSize: 11)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isActive,
                    onChanged: (v) => setLocal(() => isActive = v),
                    title: const Text('Available for booking',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                        'Turn off to hide it without deleting past bookings.',
                        style: TextStyle(fontSize: 11)),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFA82F2F))),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        setLocal(() => error = 'Give the facility a name.');
                        return;
                      }
                      double? m(TextEditingController c) => double.tryParse(c.text.trim());
                      if (pricing != 'simple' && m(memberRate) == null && m(guestRate) == null) {
                        setLocal(() => error = 'Enter at least the weekday rate.');
                        return;
                      }
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      final payload = <String, dynamic>{
                        'name': name.text.trim(),
                        'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
                        'capacity': int.tryParse(capacity.text.trim()),
                        'fee': pricing == 'simple' ? (double.tryParse(fee.text.trim()) ?? 0) : 0,
                        'rate_type': pricing == 'simple' ? 'flat' : pricing,
                        'member_rate': pricing == 'simple' ? null : m(memberRate),
                        'member_rate_weekend': pricing == 'simple' ? null : m(memberWeekend),
                        'guest_rate': pricing == 'simple' ? null : m(guestRate),
                        'guest_rate_weekend': pricing == 'simple' ? null : m(guestWeekend),
                        'member_child_rate': pricing == 'per_head' ? m(memberChild) : null,
                        'guest_child_rate': pricing == 'per_head' ? m(guestChild) : null,
                        'included_hours': pricing == 'flat' ? m(includedHours) : null,
                        'member_extension_rate': pricing == 'flat' ? m(memberExt) : null,
                        'guest_extension_rate': pricing == 'flat' ? m(guestExt) : null,
                        'cash_bond': pricing == 'simple' ? 0 : (m(bond) ?? 0),
                        'open_time': _normalizeTime(open.text),
                        'close_time': _normalizeTime(close.text),
                        'max_advance_days': int.tryParse(advance.text.trim()) ?? 90,
                        'min_notice_hours': int.tryParse(notice.text.trim()) ?? 24,
                        'requires_approval': requiresApproval,
                        'is_active': isActive,
                        'phase': scope,
                      };
                      try {
                        final c = SupabaseService.instance.client;
                        if (isNew) {
                          await c.from('facilities').insert(payload);
                        } else {
                          await c
                              .from('facilities')
                              .update(payload)
                              .eq('id', existing['id']);
                        }
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        setLocal(() {
                          busy = false;
                          error = friendlyError(e);
                        });
                      }
                    },
              child: Text(busy ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );

    disposeAfterDialogCloses([
      name, desc, capacity, fee, open, close, advance, notice,
      memberRate, memberWeekend, guestRate, guestWeekend, memberChild, guestChild,
      bond, includedHours, memberExt, guestExt,
    ]);
    if (saved == true) {
      await _loadFacilities();
      if (mounted) AppToast.success(context, message: 'Facility saved.');
    }
  }

  /// Turns "7" or "7:00" into the HH:MM form a Postgres `time` column needs.
  /// Returns null if blank or not a valid time.
  static String? _normalizeTime(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{1,2})(?::(\d{1,2}))?').firstMatch(s);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!) ?? 0;
    final min = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (h > 23 || min > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  // ---------------- Categories tab ----------------

  Widget _categoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Permit & Violation Categories',
          'The choices residents pick from when applying for a permit, and the '
          'violations an officer can issue. Changes apply to those screens '
          'immediately.',
        ),
        _cardBox([
          if (_typesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _typeGroupHeader('Permit types',
                'Shown in "Select Permit Type" when a resident applies.'),
            if (_permsLoaded && !_canManagePermitTypes)
              _readOnlyNote('permit types'),
            if (_permitTypes.isEmpty)
              _emptyTypeBox(
                  'No permit types yet. Residents cannot apply until there is '
                  'at least one.')
            else
              for (final t in _permitTypes) _typeRow(t, isPermit: true),
            if (_canManagePermitTypes) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _typeDialog(null, isPermit: true),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Permit Type'),
              ),
            ],
            const SizedBox(height: 28),
            _typeGroupHeader('Violation types',
                'Offered when an officer issues a violation, with the penalty '
                'that goes with it.'),
            if (_permsLoaded && !_canManageViolationTypes)
              _readOnlyNote('violation types'),
            if (_violationTypes.isEmpty)
              _emptyTypeBox('No violation types yet.')
            else
              for (final t in _violationTypes) _typeRow(t, isPermit: false),
            if (_canManageViolationTypes) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _typeDialog(null, isPermit: false),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Violation Type'),
              ),
            ],
          ],
        ]),
      ],
    );
  }

  Widget _typeGroupHeader(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle,
                style:
                    const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ),
      );

  Widget _readOnlyNote(String what) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.badgeAmberBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.lock_outline, size: 15, color: AppColors.badgeAmberText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Read-only. Only the HOA President, Secretary or Super Admin can '
              'change $what.',
              style: const TextStyle(fontSize: 12, color: AppColors.badgeAmberText),
            ),
          ),
        ]),
      );

  Widget _emptyTypeBox(String message) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(message,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      );

  Widget _typeRow(Map<String, dynamic> t, {required bool isPermit}) {
    final active = t['is_active'] != false;
    final canManage = isPermit ? _canManagePermitTypes : _canManageViolationTypes;
    final amount =
        ((isPermit ? t['fee'] : t['penalty_amount']) as num?)?.toDouble() ?? 0;
    final detail = isPermit
        ? '${amount == 0 ? 'No fee' : '₱${amount.toStringAsFixed(2)}'}'
            '  ·  ${t['processing_days'] ?? 3}-day processing'
        : '${amount == 0 ? 'No penalty' : '₱${amount.toStringAsFixed(2)}'}'
            '${(t['category'] ?? '').toString().trim().isEmpty ? '' : '  ·  ${t['category']}'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text((t['name'] ?? '').toString(),
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? AppColors.textPrimary
                                : AppColors.textMuted)),
                    if (!isPermit)
                      _facChip(
                          (t['severity'] ?? 'minor').toString(),
                          (t['severity'] ?? '') == 'major'
                              ? AppColors.badgeAmberBg
                              : AppColors.badgeGrayBg,
                          (t['severity'] ?? '') == 'major'
                              ? AppColors.badgeAmberText
                              : AppColors.textSecondary),
                    if (!active)
                      _facChip('Hidden', AppColors.badgeGrayBg,
                          AppColors.textSecondary),
                  ],
                ),
                const SizedBox(height: 6),
                Text(detail,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary)),
                if ((t['description'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text((t['description']).toString(),
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
          if (canManage) ...[
            TextButton(
              onPressed: () => _typeDialog(t, isPermit: isPermit),
              child: const Text('Edit'),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              padding: EdgeInsets.zero,
              onSelected: (v) {
                if (v == 'toggle') {
                  _setTypeActive(t, isPermit: isPermit, active: !active);
                } else {
                  _deleteTypeDialog(t, isPermit: isPermit);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                    value: 'toggle',
                    child: Text(active ? 'Turn off' : 'Turn back on')),
                const PopupMenuItem(value: 'delete', child: Text('Delete…')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _typeTable(bool isPermit) =>
      isPermit ? 'permit_types' : 'violation_types';

  /// Turns a type off or back on. This is the normal way to retire one: the
  /// database refuses to delete a type that records still use.
  Future<void> _setTypeActive(Map<String, dynamic> t,
      {required bool isPermit, required bool active}) async {
    try {
      await SupabaseService.instance.client
          .from(_typeTable(isPermit))
          .update({'is_active': active}).eq('id', t['id']);
      await _loadTypes();
      if (mounted) {
        AppToast.success(context,
            message: active
                ? '${t['name']} is available again.'
                : '${t['name']} is hidden from new records.');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, message: friendlyError(e));
    }
  }

  Future<void> _deleteTypeDialog(Map<String, dynamic> t,
      {required bool isPermit}) async {
    final name = (t['name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: Text(
          'This only works if nothing uses it yet. Anything already filed '
          'under "$name" keeps it, and the delete will be refused — turn the '
          'category off instead to hide it from new records.',
          style: const TextStyle(fontSize: 12.5, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA82F2F)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.instance.client.rpc(
        isPermit ? 'delete_permit_type' : 'delete_violation_type',
        params: {'p_id': t['id']},
      );
      await _loadTypes();
      if (mounted) AppToast.success(context, message: '"$name" deleted.');
    } catch (e) {
      // Show the database's sentence naming what blocks the delete;
      // friendlyError alone would turn it into "Something went wrong".
      if (mounted) AppToast.error(context, message: _typeError(e));
    }
  }

  static String _typeError(Object e) {
    if (e is PostgrestException && e.message.trim().isNotEmpty) {
      return e.message.replaceFirst('BLOCKED: ', '');
    }
    return friendlyError(e);
  }

  /// Add or edit one category. [existing] null = create.
  Future<void> _typeDialog(Map<String, dynamic>? existing,
      {required bool isPermit}) async {
    final isNew = existing == null;
    final noun = isPermit ? 'permit type' : 'violation type';
    final name = TextEditingController(text: (existing?['name'] ?? '').toString());
    final desc =
        TextEditingController(text: (existing?['description'] ?? '').toString());
    // Keep this form: `isPermit ? existing?['fee'] : ...` does not compile,
    // because Dart reads the `?[` as a nested conditional.
    final num? existingAmount = existing == null
        ? null
        : (isPermit ? existing['fee'] : existing['penalty_amount']) as num?;
    final amount = TextEditingController(
        text: existingAmount?.toStringAsFixed(2) ?? '0.00');
    final days =
        TextEditingController(text: (existing?['processing_days'] ?? 3).toString());
    final category =
        TextEditingController(text: (existing?['category'] ?? '').toString());

    var severity = (existing?['severity'] ?? 'minor').toString();
    var isActive = existing?['is_active'] != false;
    var busy = false;
    String? error;

    final severities = ['minor', 'major'];
    if (!severities.contains(severity)) severities.add(severity);

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(isNew ? 'Add $noun' : 'Edit $noun'),
          content: SizedBox(
            width: dialogContentWidth(context, 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: isPermit ? 'e.g. Solar Panel Install' : 'e.g. Littering',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: desc,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'What it covers, and anything the applicant should know',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: isPermit ? 'Fee (₱)' : 'Penalty (₱)',
                      helperText: '0 for none',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isPermit)
                    TextField(
                      controller: days,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Processing days',
                        helperText: 'How long the office takes to decide',
                      ),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      initialValue: severity,
                      decoration: const InputDecoration(labelText: 'Severity'),
                      items: [
                        for (final s in severities)
                          DropdownMenuItem(value: s, child: Text(titleCase(s))),
                      ],
                      onChanged: (v) => setLocal(() => severity = v ?? severity),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: category,
                      decoration: const InputDecoration(
                        labelText: 'Category (optional)',
                        hintText: 'e.g. parking, conduct, construction',
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (v) => setLocal(() => isActive = v),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Available', style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                        'Turn off to hide it from new records without touching '
                        'anything already filed under it.',
                        style: TextStyle(fontSize: 11)),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFA82F2F))),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        setLocal(() => error = 'Give the $noun a name.');
                        return;
                      }
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      final payload = <String, dynamic>{
                        'name': name.text.trim(),
                        'description':
                            desc.text.trim().isEmpty ? null : desc.text.trim(),
                        'is_active': isActive,
                        if (isPermit) ...{
                          'fee': double.tryParse(amount.text.trim()) ?? 0,
                          'processing_days': int.tryParse(days.text.trim()) ?? 3,
                        } else ...{
                          'penalty_amount': double.tryParse(amount.text.trim()) ?? 0,
                          'severity': severity,
                          'category': category.text.trim().isEmpty
                              ? null
                              : category.text.trim(),
                        },
                      };
                      try {
                        final c = SupabaseService.instance.client;
                        final table = _typeTable(isPermit);
                        if (isNew) {
                          await c.from(table).insert(payload);
                        } else {
                          await c
                              .from(table)
                              .update(payload)
                              .eq('id', existing['id']);
                        }
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        setLocal(() {
                          busy = false;
                          error = _typeError(e);
                        });
                      }
                    },
              child: Text(busy ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );

    for (final ctl in [name, desc, amount, days, category]) {
      ctl.dispose();
    }
    if (saved == true) {
      await _loadTypes();
      if (mounted) AppToast.success(context, message: 'Saved.');
    }
  }

  static const _tabLabels = [
    'Branding',
    'Home Page',
    'Banner',
    'Community Rules',
    'Map Settings',
    'Official Forms',
    'Facilities',
    'Categories',
    'Legal',
  ];

  // One layout for all widths: sections stack on narrow screens and the tab
  // strip scrolls sideways.
  Widget _body() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CMS · Content Management',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onPortalPrimary)),
            const SizedBox(height: 4),
            Text(
              'Manage how this HOA\'s NeighborSync instance looks and what appears '
              'on the public front page. Pick a section below -- changes apply the '
              'moment you save.',
              style: TextStyle(fontSize: 12.5, color: AppColors.onPortalMuted, height: 1.5),
            ),
            const SizedBox(height: 18),
            if (_permsLoaded && !_canEdit)
              Container(
                margin: const EdgeInsets.only(bottom: 18),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.badgeAmberBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: AppColors.badgeAmberText),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You have read-only access to the CMS. Only the HOA President '
                        'or Super Admin can save changes.',
                        style: TextStyle(fontSize: 12, color: AppColors.badgeAmberText),
                      ),
                    ),
                  ],
                ),
              ),
            // Tab strip: one row that scrolls sideways, same as Settings.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _tabLabels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _tabChip(_tabLabels[i], i),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionFor(_tab),
          ],
        ),
      ),
    );
  }

  static const _tabIcons = [
    Icons.palette_outlined,
    Icons.home_outlined,
    Icons.campaign_outlined,
    Icons.gavel_outlined,
    Icons.map_outlined,
    Icons.description_outlined,
    Icons.meeting_room_outlined,
    Icons.category_outlined,
    Icons.policy_outlined,
  ];

  Widget _tabChip(String label, int index) {
    final selected = _tab == index;
    return ChoiceChip(
      avatar: Icon(_tabIcons[index],
          size: 16,
          color: selected ? AppColors.sidebarActiveText : AppColors.textMuted),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: const Color(0xFFEFF6F1),
      labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? AppColors.sidebarActiveText : AppColors.textPrimary),
      onSelected: (_) => setState(() => _tab = index),
    );
  }

  Widget _sectionFor(int i) {
    switch (i) {
      case 0:
        return _brandingSection();
      case 1:
        return _homeSection();
      case 2:
        return _bannerSection();
      case 3:
        return _rulesSection();
      case 4:
        return _mapSettingsSection();
      case 5:
        return _formsSection();
      case 6:
        return _facilitiesSection();
      case 7:
        return _categoriesSection();
      case 8:
        return _legalSection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _sectionHeader(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onPortalPrimary)),
        const SizedBox(height: 4),
        Text(description,
            style: TextStyle(fontSize: 12.5, color: AppColors.onPortalMuted, height: 1.5)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _brandingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Community Branding',
          'Customize how this HOA\'s NeighborSync instance looks -- community '
          'name, logo, and brand colors. Changes apply to every screen the '
          'moment you save, including the sign-in page.',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 700) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _formCard(),
                  const SizedBox(height: 20),
                  _previewCard(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _formCard()),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: _previewCard()),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        _sectionHeader(
          'Portal Background',
          'The background behind the cards on every signed-in screen — for '
          'officers and residents alike (Dashboard, Reports, Payments, etc.). '
          'Upload a photo, or pick a colour. Leave the colour as the default '
          'light grey for the standard look.',
        ),
        _portalBgCard(),
      ],
    );
  }

  /// Photo / Colour switch shared by the three background sections.
  /// Read-only officers can see the current choice but cannot change it.
  Widget _bgModeToggle(String mode, ValueChanged<String> onChanged) {
    return Row(
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'color',
              icon: Icon(Icons.format_color_fill, size: 16),
              label: Text('Colour'),
            ),
            ButtonSegment(
              value: 'photo',
              icon: Icon(Icons.image_outlined, size: 16),
              label: Text('Photo'),
            ),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged:
              _canEdit ? (s) => onChanged(s.first) : null,
        ),
      ],
    );
  }

  Widget _portalBgCard() {
    final hasPhoto = _portalBgImageUrl != null && _portalBgImageUrl!.isNotEmpty;
    final usePhoto = _portalBgMode == 'photo';
    final color = _parseHex(_portalBgHexCtrl.text) ?? AppBranding.defaultPortalBgColor;
    return _cardBox([
      _bgModeToggle(_portalBgMode, (v) => setState(() => _portalBgMode = v)),
      const SizedBox(height: 16),
      if (usePhoto && hasPhoto)
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          // Has a screen-reader label because here the picture is what is
          // being edited.
          child: Image.network(_portalBgImageUrl!,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              semanticLabel: 'Current portal background photo'),
        )
      else if (usePhoto)
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.contentBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: const Text('No photo uploaded yet — the colour below is used until you add one.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        )
      else
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: const Text('Portal background colour.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ),
      // Only the editor for the selected mode is shown; the other value is
      // still saved.
      if (usePhoto) ...[
        const SizedBox(height: 12),
        if (_canEdit)
          Row(children: [
            OutlinedButton.icon(
              onPressed: _uploadingPortalBg ? null : _pickAndUploadPortalBg,
              icon: _uploadingPortalBg
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.image_outlined, size: 16),
              label: Text(hasPhoto ? 'Change Photo' : 'Upload Photo'),
            ),
            if (hasPhoto) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: _uploadingPortalBg ? null : () => setState(() => _portalBgImageUrl = null),
                child: const Text('Remove Photo'),
              ),
            ],
          ]),
      ] else ...[
        const SizedBox(height: 16),
        _label('Background Colour'),
        const SizedBox(height: 6),
        _colorField(_portalBgHexCtrl),
        const SizedBox(height: 6),
        _presetRow(_portalBgHexCtrl),
      ],
      const SizedBox(height: 20),
      if (_canEdit)
        FilledButton(
          onPressed: _savingPortalBg ? null : _savePortalBg,
          child: _savingPortalBg ? _spinner : const Text('Save Portal Background'),
        ),
    ]);
  }

  Future<void> _pickAndUploadPortalBg() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      AppToast.error(context, message: 'Could not read that image -- try another one.');
      return;
    }
    final prepared = _prepareImage(bytes, file.name);
    final ext = prepared.ext;
    final path = 'portal/portal-bg.$ext';
    setState(() => _uploadingPortalBg = true);
    try {
      final client = SupabaseService.instance.client;
      await client.storage.from('branding').uploadBinary(
            path,
            prepared.bytes,
            fileOptions: FileOptions(upsert: true, contentType: _contentTypeFor(ext)),
          );
      final url =
          '${client.storage.from('branding').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      if (!mounted) return;
      setState(() {
        _portalBgImageUrl = url;
        _uploadingPortalBg = false;
      });
      AppToast.success(context, message: 'Photo uploaded -- click Save to apply.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingPortalBg = false);
      AppToast.error(context, message: 'Upload failed. ${friendlyError(e)}');
    }
  }

  Future<void> _savePortalBg() async {
    final color = _parseHex(_portalBgHexCtrl.text);
    if (color == null) {
      AppToast.error(context, message: 'Background colour must be a 6-digit hex, e.g. #F3F6F4.');
      return;
    }
    setState(() => _savingPortalBg = true);
    try {
      await AppBranding.instance.saveOfficerPortalBg(
          imageUrl: _portalBgImageUrl, color: color, mode: _portalBgMode);
      if (!mounted) return;
      setState(() => _savingPortalBg = false);
      AppToast.success(context, message: 'Portal background updated for all roles.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingPortalBg = false);
      AppToast.error(context, message: 'Could not save. ${friendlyError(e)}');
    }
  }

  Widget _homeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Home Page',
          'The content shown on the public home page (what visitors see before '
          'signing in) -- the tagline under the community name, the "About" '
          'paragraph, and the HOA office contact details.',
        ),
        _homeContentCard(),
        const SizedBox(height: 16),
        _contactCard(),
        const SizedBox(height: 28),
        _sectionHeader(
          'Home Page Background',
          'The big banner area at the top of the public home page. Upload a '
          'community photo, or pick a background colour if you\'d rather keep it '
          'plain. Photos get a dark tint automatically so the headline and '
          'buttons stay readable.',
        ),
        _heroCard(),
        const SizedBox(height: 28),
        _sectionHeader(
          'Home Page Body Background',
          'An optional photo behind the lower (white) part of the home page -- '
          'the About section down to the footer. A translucent white layer is '
          'placed over it so the text stays readable. Leave it empty for plain '
          'white.',
        ),
        _homeBodyCard(),
      ],
    );
  }

  Widget _homeBodyCard() {
    final hasPhoto = _homeBodyImageUrl != null && _homeBodyImageUrl!.isNotEmpty;
    final usePhoto = _homeBodyMode == 'photo';
    final bodyColor = _parseHex(_homeBodyHexCtrl.text) ?? const Color(0xFFFFFFFF);
    return _cardBox([
      _bgModeToggle(_homeBodyMode, (v) => setState(() => _homeBodyMode = v)),
      const SizedBox(height: 16),
      if (usePhoto && hasPhoto)
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(_homeBodyImageUrl!,
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
              semanticLabel: 'Current home page background photo'),
        )
      else if (usePhoto)
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.contentBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: const Text('No photo uploaded yet — the colour is used until you add one.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        )
      else
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: bodyColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: const Text('Background colour.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ),
      if (usePhoto) ...[
        const SizedBox(height: 12),
        if (_canEdit)
          Row(children: [
            OutlinedButton.icon(
              onPressed: _uploadingHomeBody ? null : _pickAndUploadHomeBody,
              icon: _uploadingHomeBody
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.image_outlined, size: 16),
              label: Text(hasPhoto ? 'Change Photo' : 'Upload Photo'),
            ),
            if (hasPhoto) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: _uploadingHomeBody ? null : () => setState(() => _homeBodyImageUrl = null),
                child: const Text('Remove Photo'),
              ),
            ],
          ]),
      ] else ...[
        const SizedBox(height: 16),
        _label('Background Colour'),
        const SizedBox(height: 6),
        _colorField(_homeBodyHexCtrl),
        const SizedBox(height: 6),
        _presetRow(_homeBodyHexCtrl),
      ],
      const SizedBox(height: 20),
      if (_canEdit)
        FilledButton(
          onPressed: _savingHomeBody ? null : _saveHomeBody,
          child: _savingHomeBody ? _spinner : const Text('Save Body Background'),
        ),
    ]);
  }

  Widget _bannerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Announcement Banner',
          'Show a coloured strip across the top of every screen -- for water '
          'interruptions, meetings, deadlines, etc. Turn it off when it no longer '
          'applies. Residents can dismiss it for their session.',
        ),
        _bannerCard(),
      ],
    );
  }

  Widget _rulesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Community Rules & Bylaws',
          'The house rules / bylaws residents can read in-app (Community Rules in '
          'their menu). Plain text -- use blank lines between paragraphs.',
        ),
        _rulesCard(),
      ],
    );
  }

  /// Terms, privacy notice and browser-storage notice. These are
  /// `system_settings` rows, so editing needs `system_settings:update`.
  Widget _legalSection() {
    final b = AppBranding.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Terms & Privacy',
          'What people agree to when they create an account, and what this site '
          'keeps in their browser. Write them in your own words — these are the '
          "association's documents, not the software's. Plain text; use blank "
          'lines between paragraphs.',
        ),
        // Shows the published version, which is what each account records
        // having agreed to.
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.badgeBlueBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.gavel_outlined, size: 16, color: AppColors.badgeBlueText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  b.legalVersion.isEmpty
                      ? 'Nothing published yet. Until you save, the registration '
                          'form still asks people to agree, but there is no '
                          'document for them to read.'
                      : 'Currently published: version ${b.legalVersion}. Saving '
                          'stamps a new version with today\'s date. Accounts keep '
                          'the version they actually agreed to — editing this text '
                          'never rewrites what someone already accepted.',
                  style: const TextStyle(
                      fontSize: 12, height: 1.5, color: AppColors.badgeBlueText),
                ),
              ),
            ],
          ),
        ),
        _cardBox([
          _fieldCol('Terms Title', _termsTitleCtrl, hint: 'Terms and Conditions'),
          const SizedBox(height: 14),
          _fieldCol('Terms Content', _termsContentCtrl,
              hint: 'What members agree to: use of the system, dues, house '
                  'rules, account suspension…',
              maxLines: 12),
          const SizedBox(height: 22),
          _fieldCol('Privacy Notice Title', _privacyTitleCtrl, hint: 'Privacy Notice'),
          const SizedBox(height: 14),
          _fieldCol('Privacy Notice Content', _privacyContentCtrl,
              hint: 'What personal information the association collects, why, '
                  'who can see it, and how long it is kept…',
              maxLines: 12),
          const SizedBox(height: 22),
          _fieldCol('Browser Storage Notice', _storageNoticeCtrl,
              hint: 'Shown once, at the bottom of the page, to anyone opening '
                  'the site in a browser.',
              maxLines: 4),
          const SizedBox(height: 6),
          const Text(
            'This site sets no advertising or analytics cookies — browser '
            'storage holds only the sign-in token and two display preferences. '
            'Say that plainly. A notice offering a "Reject" button that turns '
            'nothing off would be misleading, so there is deliberately only a '
            'dismiss button. Leave this blank and no notice appears at all.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.45),
          ),
          const SizedBox(height: 20),
          if (_canEdit)
            FilledButton(
              onPressed: _savingLegal ? null : _saveLegal,
              child: _savingLegal ? _spinner : const Text('Publish'),
            ),
        ]),
      ],
    );
  }

  Widget _mapSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          _mapPhase == null ? 'Community Map' : 'Community Map -- Phase $_mapPhase',
          'Each phase has its own map picture (aerial photo or site plan), shown '
          "on that phase's Community Map and on the visitor page, where lot pins "
          'are placed. Uploading here changes only the phase shown.',
        ),
        _communityMapCard(),
        const SizedBox(height: 28),
        _sectionHeader(
          'Map Pins',
          'Each lot status shows as a differently-coloured pin on the Community '
          'Map. Set a colour for each status and the pin size below.',
        ),
        _mapPinsCard(),
      ],
    );
  }

  Widget _pinColorField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        _colorField(ctrl),
        const SizedBox(height: 6),
        _presetRow(ctrl),
      ],
    );
  }

  Widget _pinPreview(String label, TextEditingController ctrl) {
    final c = _parseHex(ctrl.text) ?? AppColors.badgeGrayBg;
    final d = _pinSize.clamp(16.0, 48.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: (_pinSize / 10).clamp(2, 5)),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _mapPinsCard() {
    return _cardBox([
      _pinColorField('Owned Lot Pin Colour', _pinHexCtrl),
      const SizedBox(height: 18),
      _pinColorField('Vacant Lot Pin Colour', _pinVacantHexCtrl),
      const SizedBox(height: 18),
      _pinColorField('Occupied Lot Pin Colour', _pinOccupiedHexCtrl),
      const SizedBox(height: 22),
      _label('Pin Size'),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: Slider(
              value: _pinSize.clamp(16, 48),
              min: 16,
              max: 48,
              divisions: 16,
              label: '${_pinSize.round()} px',
              onChanged: _canEdit ? (v) => setState(() => _pinSize = v) : null,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text('${_pinSize.round()} px',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _label('Preview'),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.highlight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _pinPreview('Owned', _pinHexCtrl),
            _pinPreview('Vacant', _pinVacantHexCtrl),
            _pinPreview('Occupied', _pinOccupiedHexCtrl),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (_canEdit)
        FilledButton(
          onPressed: _savingPins ? null : _saveMapPins,
          child: _savingPins ? _spinner : const Text('Save Map Pins'),
        ),
    ]);
  }

  /// Saves the three pin colours and the pin size.
  Future<void> _saveMapPins() async {
    final owned = _parseHex(_pinHexCtrl.text);
    final vacant = _parseHex(_pinVacantHexCtrl.text);
    final occupied = _parseHex(_pinOccupiedHexCtrl.text);
    if (owned == null || vacant == null || occupied == null) {
      AppToast.error(context, message: 'Each pin colour must be a 6-digit hex, e.g. #1A6B43.');
      return;
    }
    setState(() => _savingPins = true);
    try {
      await AppBranding.instance.saveMapPins(
        owned: owned,
        vacant: vacant,
        occupied: occupied,
        pinSize: _pinSize,
      );
      if (!mounted) return;
      setState(() => _savingPins = false);
      AppToast.success(context, message: 'Map pin appearance saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingPins = false);
      AppToast.error(context, message: 'Could not save map pins. ${friendlyError(e)}');
    }
  }

  Widget _communityMapCard() {
    final hasMap = _communityMapImageUrl != null && _communityMapImageUrl!.isNotEmpty;
    if (_mapPhase == null) {
      return _cardBox([
        const Text(
          'Your account is not assigned to a phase, so there is no phase map to edit.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
      ]);
    }
    final nums = _phaseCodes.keys.toList()..sort(_byNumber);
    return _cardBox([
      if (_isSuperAdmin && nums.length > 1) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in nums)
              ChoiceChip(
                label: Text('Phase $n${(_phaseMapUrls[n] ?? '').isEmpty ? ' · no map' : ''}'),
                selected: n == _mapPhase,
                onSelected: (_) => _selectMapPhase(n),
              ),
          ],
        ),
        const SizedBox(height: 14),
      ],
      if (hasMap) ...[
        // Use contain, not cover: the officer must see the whole plan to check
        // it. Height follows the card width.
        LayoutBuilder(
          builder: (context, box) {
            final h = (box.maxWidth * 0.6).clamp(200.0, 460.0);
            return InkWell(
              onTap: () => _showMapFullScreen(_communityMapImageUrl!),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: h,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.highlight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.hardEdge,
                child: Image.network(_communityMapImageUrl!,
                    fit: BoxFit.contain,
                    semanticLabel: 'Current community survey plan'),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        const Row(
          children: [
            Icon(Icons.zoom_in, size: 13, color: AppColors.textMuted),
            SizedBox(width: 5),
            Expanded(
              child: Text(
                'Click the map to open it full size — worth doing before you '
                'save, since lot pins are placed relative to this exact picture.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ] else
        Container(
          height: 140,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.highlight,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text('Phase $_mapPhase has no map picture yet.',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ),
      const SizedBox(height: 12),
      if (_canEdit)
        Row(children: [
          OutlinedButton.icon(
            onPressed: _uploadingCommunityMap ? null : _pickAndUploadCommunityMap,
            icon: _uploadingCommunityMap
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_photo_alternate_outlined, size: 16),
            label: Text(hasMap ? 'Change Map Picture' : 'Upload Map Picture'),
          ),
          if (hasMap) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _uploadingCommunityMap ? null : () => setState(() => _communityMapImageUrl = null),
              child: const Text('Remove Picture'),
            ),
          ],
        ]),
      const SizedBox(height: 20),
      if (_canEdit)
        FilledButton(
          onPressed: _savingCommunityMap ? null : _saveCommunityMap,
          child: _savingCommunityMap ? _spinner : const Text('Save Map Picture'),
        ),
    ]);
  }

  /// Full-size, zoomable view of the map picture, so an officer can read the
  /// small lot numbers and confirm it is the right plan before saving.
  void _showMapFullScreen(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                    child: Image.network(url,
                        fit: BoxFit.contain,
                        semanticLabel: 'Community survey plan, full size')),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadCommunityMap() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      AppToast.error(context, message: 'Could not read that image -- try another one.');
      return;
    }
    // Higher size cap than a photo: a lower one makes the small block and lot
    // numbers unreadable when zoomed in.
    final prepared =
        _prepareImage(bytes, file.name, maxEdge: kMaxSurveyPlanEdge);
    final ext = prepared.ext;
    final path = 'map/phase-$_mapPhase.$ext';
    setState(() => _uploadingCommunityMap = true);
    try {
      final client = SupabaseService.instance.client;
      await client.storage.from('branding').uploadBinary(
            path,
            prepared.bytes,
            fileOptions: FileOptions(upsert: true, contentType: _contentTypeFor(ext)),
          );
      final url =
          '${client.storage.from('branding').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      if (!mounted) return;
      setState(() {
        _communityMapImageUrl = url;
        _uploadingCommunityMap = false;
      });
      AppToast.success(context, message: 'Map uploaded -- click Save to apply.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingCommunityMap = false);
      AppToast.error(context, message: 'Upload failed. ${friendlyError(e)}');
    }
  }

  /// Saves the selected phase's map through the set_phase_map function.
  Future<void> _saveCommunityMap() async {
    final phase = _mapPhase;
    if (phase == null) return;
    // Pins are fractions of the picture they sit on, so a new picture may
    // misplace them. If it changed, ask what to do with this phase's pins.
    final previous = _phaseMapUrls[phase] ?? '';
    final next = _communityMapImageUrl ?? '';
    final imageChanged = previous != next;
    var clearPins = false;

    if (imageChanged) {
      final pinned = await SupabaseService.instance.client
          .from('lots')
          .count()
          .not('map_x', 'is', null)
          .inFilter('phase', _phaseCodes[phase] ?? const []);
      if (!mounted) return;
      if (pinned > 0) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('What about the existing pins?'),
            content: Text(
                'Phase $phase has $pinned pin${pinned == 1 ? '' : 's'} placed on the '
                'current picture.\n\n'
                'Pins are stored as relative positions, so on a new picture '
                'with the same framing they will still line up. If the new '
                'one is cropped or a different shape, they will be off and '
                'you can move them individually from the Community Map '
                '(open a lot, then "Move Pin").\n\n'
                'Clearing them cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, 'clear'),
                  child: Text('Clear all $pinned pins')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, 'keep'),
                  child: const Text('Keep pins')),
            ],
          ),
        );
        if (choice == null || choice == 'cancel') return;
        clearPins = choice == 'clear';
      }
    }

    setState(() => _savingCommunityMap = true);
    try {
      await SupabaseService.instance.client.rpc('set_phase_map', params: {
        'p_number': phase,
        'p_url': next.isEmpty ? null : next,
        'p_clear_pins': clearPins,
      });
      if (!mounted) return;
      setState(() {
        _savingCommunityMap = false;
        _phaseMapUrls[phase] = next.isEmpty ? null : next;
      });
      AppToast.success(context,
          message: clearPins
              ? 'Phase $phase map updated. Its pins were cleared for re-pinning.'
              : imageChanged
                  ? 'Phase $phase map updated. Pins were kept -- check they still line up.'
                  : 'Phase $phase map saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingCommunityMap = false);
      final msg = e is PostgrestException ? e.message : friendlyError(e);
      AppToast.error(context, message: 'Could not save. $msg');
    }
  }

  Widget _formsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Official Forms',
          'Upload the HOA\'s official blank forms so residents can download them. '
          'The Complaint/Concern process itself is already digital -- this is for '
          'anyone who needs the printable original.',
        ),
        _officialFormsCard(),
        const SizedBox(height: 16),
        _otherFormsCard(),
        const SizedBox(height: 16),
        // Per-role guides, kept apart from the forms every resident sees.
        UserGuidesCard(canEdit: _canEdit),
      ],
    );
  }

  Widget _officialFormsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: AppColors.badgeGreenBg, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Icon(Icons.description_outlined,
                size: 20, color: AppColors.sidebarActiveText),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Complaint / Concern Form',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  _complaintFormUrl == null
                      ? 'No file uploaded yet.'
                      : 'Uploaded -- residents see a download link on File a Complaint.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (_canEdit) ...[
            OutlinedButton.icon(
              onPressed: _uploadingForm ? null : _uploadComplaintForm,
              icon: _uploadingForm
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_outlined, size: 16),
              label: Text(_complaintFormUrl == null ? 'Upload' : 'Replace'),
            ),
            if (_complaintFormUrl != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Preview',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_new, size: 18, color: AppColors.textMuted),
                onPressed: () => _previewForm(_complaintFormUrl),
              ),
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                onPressed: _uploadingForm ? null : _removeComplaintForm,
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// List of other official forms. Officers manage them; residents download.
  Widget _otherFormsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Other Official Forms',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              if (_canEdit)
                FilledButton.icon(
                  onPressed: _addingForm ? null : _addOtherForm,
                  icon: _addingForm
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add, size: 16),
                  label: const Text('Add Form'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_otherForms.isEmpty)
            // Mentions the row menu, which cannot be seen while the list is empty.
            const Text(
                'No additional forms yet. Once you add one you can rename it, '
                'replace the file or remove it from the ⋮ menu on its row.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.45))
          else
            for (var i = 0; i < _otherForms.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text((_otherForms[i]['name'] ?? '').toString(),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ),
                    IconButton(
                      tooltip: 'Preview',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.open_in_new, size: 18, color: AppColors.textMuted),
                      onPressed: () => _previewForm(_otherForms[i]['url'] as String?),
                    ),
                    // Rename, Replace and Remove share one menu to keep the row short.
                    if (_canEdit)
                      PopupMenuButton<String>(
                        tooltip: 'Manage',
                        icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
                        onSelected: (v) {
                          if (v == 'rename') _renameOtherForm(i);
                          if (v == 'replace') _replaceOtherForm(i);
                          if (v == 'remove') _deleteOtherForm(i);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.edit_outlined, size: 18),
                              title: Text('Rename'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'replace',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.upload_outlined, size: 18),
                              title: Text('Replace file'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              title: Text('Remove', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _homeContentCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Tagline'),
          const SizedBox(height: 6),
          TextField(
            controller: _taglineCtrl,
            enabled: _canEdit,
            decoration: const InputDecoration(
                hintText: 'e.g. A connected community, managed in one place.'),
          ),
          const SizedBox(height: 18),
          _label('About the Community'),
          const SizedBox(height: 6),
          TextField(
            controller: _aboutCtrl,
            enabled: _canEdit,
            maxLines: 5,
            decoration: const InputDecoration(
                hintText: 'A short paragraph about the community, shown on the front page.'),
          ),
          const SizedBox(height: 20),
          if (_canEdit)
            FilledButton(
              onPressed: _savingHome ? null : _saveHomeContent,
              child: _savingHome
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Home Page'),
            ),
        ],
      ),
    );
  }

  Widget _cardBox(List<Widget> children) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget get _spinner => const SizedBox(
      height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));

  Widget _fieldCol(String label, TextEditingController ctrl,
      {String? hint,
      int maxLines = 1,
      List<TextInputFormatter>? inputFormatters,
      bool? enabled}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          enabled: enabled ?? _canEdit,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }

  /// Shows which office the card is editing. The super admin picks from
  /// Subdivision and every phase; a phase officer just sees their own.
  Widget _contactTargetPicker() {
    final nums = _phaseCodes.keys.toList()..sort(_byNumber);
    final heading = _contactTarget == null
        ? 'Subdivision office (the whole subdivision)'
        : 'Phase $_contactTarget office';
    final help = _contactTarget == null
        ? 'Shown on the landing page by default. Each phase can add its own '
            'office below; anything a phase leaves blank falls back to these.'
        : 'Shown when a visitor picks Phase $_contactTarget on the landing '
            'page, and to this phase\'s residents. Leave a box blank to show '
            'the subdivision\'s instead. Social pages are this phase\'s own.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_isSuperAdmin && nums.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
            label: const Text('Subdivision'),
            selected: _contactTarget == null,
            onSelected: (_) => _selectContactTarget(null),
          ),
          for (final n in nums)
            ChoiceChip(
              label: Text('Phase $n'),
              selected: _contactTarget == n,
              onSelected: (_) => _selectContactTarget(n),
            ),
        ]),
        const SizedBox(height: 14),
      ],
      Text(heading,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 4),
      Text(help,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.45)),
      if (!_canEditContact && _canEdit) ...[
        const SizedBox(height: 6),
        const Text(
            'Only the system administrator can change the subdivision\'s '
            'details.',
            style: TextStyle(fontSize: 11.5, color: AppColors.badgeAmberText)),
      ],
      const SizedBox(height: 16),
    ]);
  }

  Widget _contactCard() {
    return _cardBox([
      _contactTargetPicker(),
      _fieldCol('Office Address', _addrCtrl, hint: "e.g. HOA Office, Clubhouse Bldg.", enabled: _canEditContact),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Office Hours'),
              const SizedBox(height: 6),
              // Keyed on the target: the field parses its controller once,
              // so switching phase must rebuild it to show that phase's hours.
              OfficeHoursField(
                  key: ValueKey('hours-${_contactTarget ?? 'sub'}'),
                  controller: _hoursCtrl,
                  enabled: _canEditContact),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: _fieldCol('Phone', _phoneCtrl, hint: '09170000000', inputFormatters: phoneInputFormatters, enabled: _canEditContact)),
      ]),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _fieldCol('Email', _emailCtrl, hint: 'office@community.org', enabled: _canEditContact)),
        const SizedBox(width: 14),
        Expanded(child: _fieldCol('Map Link (optional)', _mapCtrl, hint: 'https://maps.google.com/...', enabled: _canEditContact)),
      ]),
      const SizedBox(height: 20),
      if (_canEditContact)
        FilledButton(
          onPressed: _savingContact ? null : _saveContact,
          child: _savingContact ? _spinner : const Text('Save Contact Details'),
        ),
      const Divider(height: 34),
      _socialLinksSection(),
    ]);
  }

  // ---------------- Social links ----------------

  /// Social links list. Each change saves at once, separately from Save
  /// Contact Details.
  Widget _socialLinksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Social Media'),
        const SizedBox(height: 4),
        Text(
          _contactTarget == null
              ? 'The subdivision\'s own pages, shown on the public landing '
                  'page. Add only the ones actually in use.'
              : 'Phase $_contactTarget\'s own pages. These are not borrowed '
                  'from the subdivision -- if this list is empty, the phase '
                  'simply shows none of its own.',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.45),
        ),
        const SizedBox(height: 12),
        if (_socialLinks.isEmpty)
          const Text('No social accounts added yet.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted))
        else
          for (var i = 0; i < _socialLinks.length; i++) _socialRow(i),
        if (_canEditContact) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _savingSocial ? null : () => _socialDialog(null),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Link'),
          ),
        ],
      ],
    );
  }

  Widget _socialRow(int i) {
    final link = _socialLinks[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(link.icon, size: 18, color: AppColors.sidebarActiveText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(link.label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text(link.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (_canEditContact) ...[
            TextButton(
              onPressed: _savingSocial ? null : () => _socialDialog(i),
              child: const Text('Edit'),
            ),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Colors.redAccent),
              onPressed: _savingSocial ? null : () => _removeSocial(i),
            ),
          ],
        ],
      ),
    );
  }

  /// Add ([index] null) or edit one link.
  Future<void> _socialDialog(int? index) async {
    final existing = index == null ? null : _socialLinks[index];
    var platform = existing?.platform ?? SocialLink.platforms.keys.first;
    if (!SocialLink.platforms.containsKey(platform)) platform = 'website';
    final urlCtrl = TextEditingController(text: existing?.url ?? '');
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(index == null ? 'Add social link' : 'Edit social link'),
          content: SizedBox(
            width: _contentWidthFor(context, 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('social-platform-$platform'),
                  initialValue: platform,
                  decoration: const InputDecoration(labelText: 'Platform'),
                  items: [
                    for (final e in SocialLink.platforms.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setLocal(() => platform = v ?? platform),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Link',
                    hintText: 'facebook.com/yourcommunity',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFA82F2F))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                // Normalize first: a link with no scheme would resolve against
                // our own site and 404.
                final url = SocialLink.normalize(urlCtrl.text);
                if (url == null) {
                  setLocal(() => error = 'Enter a valid link, e.g. '
                      'facebook.com/yourcommunity');
                  return;
                }
                urlCtrl.text = url;
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final url = urlCtrl.text;
    disposeAfterDialogCloses([urlCtrl]);
    if (saved != true) return;

    final next = List<SocialLink>.from(_socialLinks);
    final link = SocialLink(platform: platform, url: url);
    if (index == null) {
      next.add(link);
    } else {
      next[index] = link;
    }
    await _persistSocial(next);
  }

  Future<void> _removeSocial(int index) async {
    final next = List<SocialLink>.from(_socialLinks)..removeAt(index);
    await _persistSocial(next);
  }

  /// Saves the social links to the subdivision or the selected phase.
  Future<void> _persistSocial(List<SocialLink> next) async {
    setState(() => _savingSocial = true);
    try {
      final target = _contactTarget;
      if (target == null) {
        await AppBranding.instance.saveSocialLinks(next);
      } else {
        // Uses the phase's last saved contact fields, so half-typed boxes above
        // are not saved along with the link.
        final saved = _phaseContacts[target] ?? PhaseContact(number: target);
        final updated = PhaseContact(
          number: target,
          address: saved.address,
          hours: saved.hours,
          phone: saved.phone,
          email: saved.email,
          mapLink: saved.mapLink,
          socialLinks: next,
        );
        await savePhaseContact(updated);
        _phaseContacts = {..._phaseContacts, target: updated};
      }
      if (!mounted) return;
      setState(() {
        _socialLinks = next;
        _savingSocial = false;
      });
      AppToast.success(context, message: 'Social links saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingSocial = false);
      AppToast.error(context, message: 'Could not save. ${friendlyError(e)}');
    }
  }

  /// Dialog content width that fits the screen. AlertDialog uses 128px for its
  /// own inset and padding, so a fixed width overflows a phone.
  static double _contentWidthFor(BuildContext context, double preferred) {
    final available = MediaQuery.of(context).size.width - 128;
    if (available <= 0) return preferred;
    return available < preferred ? available : preferred;
  }

  Widget _bannerCard() {
    return _cardBox([
      Row(children: [
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Show banner',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            SizedBox(height: 2),
            Text('When on, the message below appears on every screen.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        Switch(
          value: _bannerEnabled,
          onChanged: _canEdit ? (v) => setState(() => _bannerEnabled = v) : null,
        ),
      ]),
      const SizedBox(height: 14),
      _fieldCol('Message', _bannerMsgCtrl,
          hint: 'e.g. Water interruption Saturday 8am-12nn.', maxLines: 2),
      const SizedBox(height: 14),
      _label('Style'),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: _bannerLevel,
        decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
        items: const [
          DropdownMenuItem(value: 'info', child: Text('Info (blue)')),
          DropdownMenuItem(value: 'warning', child: Text('Warning (amber)')),
          DropdownMenuItem(value: 'critical', child: Text('Critical (red)')),
        ],
        onChanged: _canEdit ? (v) => setState(() => _bannerLevel = v ?? 'info') : null,
      ),
      const SizedBox(height: 20),
      if (_canEdit)
        FilledButton(
          onPressed: _savingBanner ? null : _saveBanner,
          child: _savingBanner ? _spinner : const Text('Save Banner'),
        ),
    ]);
  }

  Widget _heroCard() {
    final hasPhoto = _heroImageUrl != null && _heroImageUrl!.isNotEmpty;
    final usePhoto = _heroMode == 'photo';
    final color = _parseHex(_heroHexCtrl.text) ?? AppBranding.instance.heroColor;
    return _cardBox([
      _bgModeToggle(_heroMode, (v) => setState(() => _heroMode = v)),
      const SizedBox(height: 16),
      _label('Preview'),
      const SizedBox(height: 6),
      Semantics(
        image: usePhoto && hasPhoto,
        label: (usePhoto && hasPhoto)
            ? 'Preview of the landing page banner, using the uploaded photo'
            : 'Preview of the landing page banner, using a colour gradient',
        child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 120,
          width: double.infinity,
          decoration: (usePhoto && hasPhoto)
              ? BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(_heroImageUrl!),
                    fit: BoxFit.cover,
                    colorFilter:
                        ColorFilter.mode(Colors.black.withValues(alpha: 0.45), BlendMode.darken),
                  ),
                )
              : BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, Color.lerp(color, Colors.black, 0.45) ?? color],
                  ),
                ),
          alignment: Alignment.center,
          child: Text(_nameCtrl.text.isEmpty ? 'Community Name' : _nameCtrl.text,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ),
      ),
      const SizedBox(height: 14),
      if (!usePhoto)
        const SizedBox.shrink()
      else if (_canEdit)
        Row(children: [
          OutlinedButton.icon(
            onPressed: _uploadingHero ? null : _pickAndUploadHero,
            icon: _uploadingHero
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.image_outlined, size: 16),
            label: Text(hasPhoto ? 'Change Photo' : 'Upload Photo'),
          ),
          if (hasPhoto) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _uploadingHero ? null : () => setState(() => _heroImageUrl = null),
              child: const Text('Remove Photo'),
            ),
          ],
        ])
      else
        Text(hasPhoto ? 'Custom background photo.' : 'No photo uploaded yet.',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      if (!usePhoto) ...[
        const SizedBox(height: 16),
        _label('Background Colour'),
        const SizedBox(height: 6),
        _colorField(_heroHexCtrl),
        const SizedBox(height: 6),
        _presetRow(_heroHexCtrl),
      ],
      const SizedBox(height: 20),
      if (_canEdit)
        FilledButton(
          onPressed: _savingHero ? null : _saveHero,
          child: _savingHero ? _spinner : const Text('Save Background'),
        ),
    ]);
  }

  Widget _rulesCard() {
    return _cardBox([
      _fieldCol('Page Title', _rulesTitleCtrl, hint: 'Community Rules & Guidelines'),
      const SizedBox(height: 14),
      _fieldCol('Content', _rulesContentCtrl,
          hint: 'Type the community rules / bylaws here…', maxLines: 12),
      const SizedBox(height: 20),
      if (_canEdit)
        FilledButton(
          onPressed: _savingRules ? null : _saveRules,
          child: _savingRules ? _spinner : const Text('Save Rules'),
        ),
    ]);
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Community Name'),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            enabled: _canEdit,
            decoration: const InputDecoration(hintText: "e.g. Sunrise Heights"),
          ),
          const SizedBox(height: 18),
          _label('Community Logo'),
          const SizedBox(height: 6),
          _logoUploadRow(),
          const SizedBox(height: 10),
          _label('Letter Monogram (used when no image is set)'),
          const SizedBox(height: 6),
          TextField(
            controller: _monogramCtrl,
            enabled: _canEdit,
            maxLength: 3,
            decoration: const InputDecoration(hintText: 'e.g. GH'),
          ),
          const SizedBox(height: 10),
          _label('Accent / Primary Color'),
          const SizedBox(height: 6),
          _colorField(_primaryHexCtrl),
          const SizedBox(height: 6),
          _presetRow(_primaryHexCtrl),
          const SizedBox(height: 18),
          _label('Sidebar Background Color'),
          const SizedBox(height: 6),
          _colorField(_sidebarHexCtrl),
          const SizedBox(height: 6),
          _presetRow(_sidebarHexCtrl),
          const SizedBox(height: 24),
          if (_canEdit)
            Row(
              children: [
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Branding'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _saving ? null : _resetToDefaults,
                  child: const Text('Reset to Defaults'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary));

  Widget _logoUploadRow() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.badgeGrayBg,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: _logoImageUrl == null
              ? Text(_monogramCtrl.text.isEmpty ? '?' : _monogramCtrl.text,
                  style: TextStyle(fontWeight: FontWeight.w700, color: _previewPrimary))
              : Image.network(
                  _logoImageUrl!,
                  fit: BoxFit.cover,
                  semanticLabel: 'Current community logo',
                  errorBuilder: (context, error, stack) =>
                      const Icon(Icons.broken_image_outlined, size: 18, color: AppColors.textMuted),
                ),
        ),
        const SizedBox(width: 12),
        if (_canEdit) ...[
          OutlinedButton.icon(
            onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
            icon: _uploadingLogo
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_outlined, size: 16),
            label: Text(_logoImageUrl == null ? 'Upload Image' : 'Change Image'),
          ),
          if (_logoImageUrl != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: _uploadingLogo ? null : _removeLogo,
              child: const Text('Remove'),
            ),
          ],
        ] else
          Text(
            _logoImageUrl == null ? 'No image set -- using letter monogram.' : 'Custom image logo.',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
      ],
    );
  }

  Widget _colorField(TextEditingController ctrl) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: ctrl,
          builder: (context, _) {
            final c = _parseHex(ctrl.text);
            return Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c ?? AppColors.badgeGrayBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: c == null
                  ? const Icon(Icons.question_mark, size: 16, color: AppColors.textMuted)
                  : null,
            );
          },
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: ctrl,
            enabled: _canEdit,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: '#1A6B43'),
          ),
        ),
        if (_canEdit) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Pick any colour from the wheel',
            onPressed: () => _openColorWheel(ctrl),
            icon: const Icon(Icons.palette_outlined),
          ),
        ],
      ],
    );
  }

  /// Opens the colour wheel and writes the chosen hex into [ctrl].
  Future<void> _openColorWheel(TextEditingController ctrl) async {
    final start = _parseHex(ctrl.text) ?? AppBranding.instance.primaryColor;
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorWheelDialog(initial: start),
    );
    if (picked != null && mounted) setState(() => ctrl.text = _toHex(picked));
  }

  Widget _presetRow(TextEditingController ctrl) {
    if (!_canEdit) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in _presetColors)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => ctrl.text = _toHex(c)),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
            ),
          ),
      ],
    );
  }

  Widget _previewCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Live Preview'),
        const SizedBox(height: 6),
        const Text('Not saved yet -- this reflects the fields to the left.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: Listenable.merge([_nameCtrl, _monogramCtrl, _primaryHexCtrl, _sidebarHexCtrl]),
          builder: (context, _) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_previewSidebar, const Color(0xFF0C3620)],
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: _logoImageUrl == null
                          ? Text(
                              _monogramCtrl.text.isEmpty ? '?' : _monogramCtrl.text,
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700, color: _previewPrimary),
                            )
                          : Image.network(_logoImageUrl!,
                              fit: BoxFit.cover,
                              semanticLabel: 'Logo preview'),
                    ),
                    const SizedBox(height: 14),
                    Text(_nameCtrl.text.isEmpty ? 'Community Name' : _nameCtrl.text,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('NeighborSync HOA Platform',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _previewPrimary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Log In',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// HSV colour wheel dialog. Hue is the angle around the wheel, saturation is
/// the distance from the centre, and a slider sets brightness.
/// Pops with the chosen [Color], or null if cancelled.
class _ColorWheelDialog extends StatefulWidget {
  final Color initial;
  const _ColorWheelDialog({required this.initial});

  @override
  State<_ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<_ColorWheelDialog> with SafeSetState<_ColorWheelDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    if (_hsv.saturation == 0) _hsv = _hsv.withHue(0); // keep a stable angle for greys
    _hexCtrl = TextEditingController(text: _hex(_hsv.toColor()));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  static String _hex(Color c) {
    int ch(double v) => (v * 255).round().clamp(0, 255);
    final r = ch(c.r).toRadixString(16).padLeft(2, '0');
    final g = ch(c.g).toRadixString(16).padLeft(2, '0');
    final b = ch(c.b).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b'.toUpperCase();
  }

  static Color? _parse(String hex) {
    final h = hex.replaceAll('#', '').trim();
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  /// Sets hue and saturation from a touch point on the wheel.
  void _setFromWheel(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final v = local - center;
    final radius = size.width / 2;
    final dist = v.distance;
    final sat = (dist / radius).clamp(0.0, 1.0);
    var hue = math.atan2(v.dy, v.dx) * 180 / math.pi;
    if (hue < 0) hue += 360;
    setState(() {
      _hsv = _hsv.withHue(hue).withSaturation(sat);
      _hexCtrl.text = _hex(_hsv.toColor());
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    const wheelSize = 220.0;
    return AlertDialog(
      title: const Text('Pick a colour'),
      content: SizedBox(
        width: dialogContentWidth(context, 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: wheelSize,
              height: wheelSize,
              child: GestureDetector(
                onPanDown: (d) => _setFromWheel(d.localPosition, const Size(wheelSize, wheelSize)),
                onPanUpdate: (d) => _setFromWheel(d.localPosition, const Size(wheelSize, wheelSize)),
                child: CustomPaint(
                  painter: _ColorWheelPainter(_hsv),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Brightness', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _hsv.value,
                    onChanged: (v) => setState(() {
                      _hsv = _hsv.withValue(v);
                      _hexCtrl.text = _hex(_hsv.toColor());
                    }),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD8DED9)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _hexCtrl,
                    decoration: const InputDecoration(hintText: '#1A6B43', isDense: true),
                    onChanged: (t) {
                      final c = _parse(t);
                      if (c != null) setState(() => _hsv = HSVColor.fromColor(c));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _hsv.toColor()),
          child: const Text('Use this colour'),
        ),
      ],
    );
  }
}

/// Paints the colour wheel and a ring marking the [selected] colour.
class _ColorWheelPainter extends CustomPainter {
  final HSVColor selected;
  const _ColorWheelPainter(this.selected);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Hue around the circle...
    final hueShader = const SweepGradient(
      colors: [
        Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
        Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, Paint()..shader = hueShader);

    // ...faded to white in the middle for saturation.
    final satShader = RadialGradient(
      colors: [Colors.white, Colors.white.withValues(alpha: 0)],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, Paint()..shader = satShader);

    // Darken the whole wheel to reflect the chosen brightness.
    if (selected.value < 1) {
      canvas.drawCircle(center, radius,
          Paint()..color = Colors.black.withValues(alpha: 1 - selected.value));
    }

    // Selection indicator.
    final ang = selected.hue * math.pi / 180;
    final pos = center + Offset(math.cos(ang), math.sin(ang)) * (selected.saturation * radius);
    canvas.drawCircle(pos, 8, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    canvas.drawCircle(pos, 8, Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_ColorWheelPainter old) => old.selected != selected;
}
