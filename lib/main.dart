import 'core/app_locale.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, AuthChangeEvent;
import 'package:flutter/material.dart';
import 'core/app_config.dart';
import 'package:go_router/go_router.dart';
import 'core/auth_link_error.dart';
import 'core/branding.dart';
import 'core/url_strategy.dart';
import 'core/module_registry.dart';
import 'core/permissions.dart';
import 'core/roles.dart';
import 'offline/sync_engine.dart';
import 'services/supabase_service.dart';
import 'core/ui_prefs.dart';
import 'theme/app_theme.dart';
import 'widgets/responsive_officer_shell.dart' show kMobileBreakpoint;
import 'widgets/guided_tour.dart';
import 'widgets/legal_documents.dart';
import 'widgets/site_banner.dart';
import 'widgets/storage_notice.dart';
import 'screens/home_screen.dart';
import 'screens/visitor_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/verify_email_screen.dart';
import 'widgets/app_error_panel.dart';
import 'screens/mfa_setup_screen.dart';
import 'screens/mfa_challenge_screen.dart';
import 'screens/mfa_email_screen.dart';
import 'screens/member_dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/treasurer_dashboard_screen.dart';
import 'screens/secretary_dashboard_screen.dart';
import 'screens/security_dashboard_screen.dart';
import 'screens/module_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/error_screen.dart';
import 'screens/member_waste_schedule_screen.dart';
import 'screens/member_visitors_screen.dart';
import 'screens/member_move_requests_screen.dart';
import 'screens/member_how_to_pay_screen.dart';
import 'screens/member_payments_screen.dart';
import 'screens/member_settings_screen.dart';
import 'screens/member_complaints_screen.dart';
import 'screens/member_permits_screen.dart';
import 'screens/member_documents_screen.dart';
import 'screens/member_my_files_screen.dart';
import 'screens/community_rules_screen.dart';
import 'screens/branding_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/community_directory_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/announcements_board_screen.dart';
import 'screens/announcements_events_screen.dart';
import 'screens/services_hub_screen.dart';
import 'screens/events_calendar_screen.dart';
import 'screens/billing_screen.dart';
import 'screens/finance_screen.dart';
import 'screens/community_concern_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/waste_schedule_screen.dart';
import 'screens/permits_screen.dart';
import 'screens/vehicles_screen.dart';
import 'screens/visitors_screen.dart';
import 'screens/move_requests_screen.dart';
import 'screens/gate_passes_screen.dart';
import 'screens/residents_screen.dart';
import 'screens/tenants_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/person_detail_screen.dart';
import 'screens/security_screen.dart';
import 'screens/assigned_concerns_screen.dart';
import 'screens/documents_screen.dart';
import 'screens/member_reservations_screen.dart';
import 'screens/reservations_screen.dart';
import 'screens/audit_logs_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/idle_timeout.dart';

/// Starts the app: connects Supabase, loads branding and language, then
/// runs [NeighborSyncApp].
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real paths instead of /#/... on web. Must run before the router is built;
  // Supabase recovery links need it. Does nothing off the web.
  useCleanUrls();

  // Must run before Supabase starts, and only reads the URL: the same
  // fragment carries a good recovery link's tokens, which Supabase parses.
  authLinkError = AuthLinkError.capture();

  // Compiled in with --dart-define (see core/app_config.dart). Stop here
  // rather than show a blank page.
  if (kSupabaseUrl.isEmpty || kSupabaseAnonKey.isEmpty) {
    throw StateError('SUPABASE_URL / SUPABASE_ANON_KEY were not set at build '
        'time. Run with --dart-define-from-file=.env');
  }
  await SupabaseService.init(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);

  // Loads the saved community name, logo and colors before the first frame,
  // so default branding never flashes. Keeps the built-in defaults on failure.
  await AppBranding.instance.load();

  // Re-themes this device when any officer changes the CMS. Started after
  // the first load so startup never waits on a websocket.
  AppBranding.instance.startLiveUpdates();

  // Each person's display language: loaded on sign-in or a restored session,
  // reset on sign-out so a shared device never shows the last person's choice.
  if (Supabase.instance.client.auth.currentSession != null) {
    await AppLocale.instance.loadForCurrentUser();
  }
  // The cached role, user id and permissions belong to one login. Clear them
  // when the account changes, or saves get filed under the wrong person.
  String? identityOwner = Supabase.instance.client.auth.currentUser?.id;
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final uid = data.session?.user.id;
    if (uid != identityOwner) {
      final switched = identityOwner != null && uid != null;
      SupabaseService.instance.clearIdentityCache();
      identityOwner = uid;
      // Remembered sessions are shared by all tabs, so a sign-in in another
      // tab replaces this one's. Reload, or the screen shows the old person
      // while every save runs as the new one.
      if (switched) reloadPage();
    }
    if (data.event == AuthChangeEvent.signedIn) {
      AppLocale.instance.loadForCurrentUser();
    } else if (data.event == AuthChangeEvent.signedOut) {
      AppLocale.instance.reset();
    }
  }, onError: (_) {});

  // Sends writes queued while offline to Supabase once the app is back online.
  SyncEngine.instance.start();

  // Release builds show a plain sentence where a widget failed to build,
  // instead of Flutter's unlabelled grey box.
  installAppErrorPanel();

  runApp(const NeighborSyncApp());
}

/// Modules with their own screen instead of the generic table. The route loop
/// at the end of [_router] skips these, so no route is registered twice.
const _bespokeModuleScreens = {
  'announcements', 'events', 'billing', 'payments', //
  'complaints', 'cases', 'permits', 'vehicles', 'visitors', //
  'security', 'documents', 'residents', 'tenants', //
  'gate_passes', 'audit_logs', 'system_settings',
};

/// Pages for signed-out people. A signed-in person who lands on one is sent
/// to their dashboard (except '/reset-password'; see the redirect).
const _publicPaths = {
  // The landing page.
  '/',
  // Read-only "Browse as Visitor" page; no account needed.
  '/visitor',
  '/login',
  '/register',
  '/forgot-password',
  '/reset-password',
  '/verify-email',
  // Email sign-in code: the person is signed out while they type it.
  '/mfa-email',
};

/// The terms, privacy notice and error page: open to everyone, signed in or
/// not. Keep them out of [_publicPaths], or signed-in people get bounced away.
const _legalPaths = {'/terms', '/privacy', '/error'};

/// The permission an officer needs to open each route. Holding any one of
/// [modules] is enough; [action] narrows it to one action. An empty list means
/// any officer. A route with no entry is open to every signed-in officer
/// (e.g. the dashboard, Community Map, Waste Schedule).
final Map<String, ({List<String> modules, String? action})>
    _officerRouteGuards = {
  '/admin/reports': (modules: ['audit_logs', 'bills'], action: null),
  '/admin/accounts': (modules: ['accounts'], action: null),
  // One person's whole file. Each section on the page also checks its own
  // module's permission.
  '/admin/people': (modules: ['accounts'], action: null),
  '/admin/approvals': (modules: ['users'], action: 'approve'),
  '/admin/branding': (modules: ['system_settings'], action: null),
  // One screen with Billing, Payments, Budget and other tabs.
  '/admin/finance': (modules: ['bills', 'payments', 'budget'], action: null),
  // One screen with Complaints and Cases tabs. audit_logs is left out on
  // purpose: that permission alone cannot read this screen's data.
  '/admin/community-concern': (
    modules: ['complaints', 'violations'],
    action: null
  ),
  '/admin/move-requests': (modules: ['move_requests'], action: null),
  '/admin/backup': (modules: ['backup'], action: null),
  // Read is enough to view; approving is checked inside the screen.
  '/admin/reservations': (modules: ['reservations'], action: null),
  for (final m in moduleRegistry)
    m.route: (modules: [m.permissionModule], action: null),
  // Must stay AFTER the registry loop: later entries overwrite earlier ones.
  // Both paths open the merged screen, so either permission is enough.
  '/admin/announcements': (modules: ['announcements', 'events'], action: null),
  '/admin/events': (modules: ['announcements', 'events'], action: null),
  // Every officer may open Settings (Replay the tutorial is there). The screen
  // shows association-wide settings only to holders of system_settings.
  '/admin/system_settings': (modules: const <String>[], action: null),
  // Tiles inside are filtered by permission; the hub itself is open.
  '/admin/services': (modules: const <String>[], action: null),
  // Each officer's own private files.
  '/admin/my-files': (modules: const <String>[], action: null),
};

/// Scroll rules for the whole app: one scrollbar and one overscroll setting,
/// so no screen has to add its own.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  /// Adds an auto-hiding scrollbar to vertical scroll views on every platform,
  /// and none to horizontal ones. Touch needs it too: the app draws to a canvas,
  /// so the phone's own indicator never shows. Looks: `scrollbarTheme` in
  /// `app_theme.dart`.
  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    final isVertical = details.direction == AxisDirection.down ||
        details.direction == AxisDirection.up;
    if (!isVertical) return child;

    return Scrollbar(controller: details.controller, child: child);
  }

  /// Lets every scroll view take a drag even when its content is short.
  /// Without this, pull-to-refresh does nothing on empty screens. Scroll views
  /// that set their own `physics:` are not affected.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const AlwaysScrollableScrollPhysics()
          .applyTo(super.getScrollPhysics(context));
}

/// Every page in the app, plus the [GoRouter.redirect] rules that decide who
/// may open which page. The redirect is the real access control for navigation;
/// hiding a menu item is not.
final _router = GoRouter(
  initialLocation: '/',
  // Required: the server sends every path to index.html, so a bad URL reaches
  // the router. Without this, go_router shows a raw stack trace.
  errorBuilder: (context, state) =>
      NotFoundScreen(attemptedPath: state.uri.toString()),
  redirect: (context, state) async {
    final session = SupabaseService.instance.client.auth.currentSession;
    final path = state.matchedLocation;

    // A failed email link (expired or already used) can land on '/', where
    // nothing explains it, so send the person to the screen that does.
    // `consumed` makes this happen once, not on every later visit to '/'.
    if (authLinkError != null && !authLinkError!.consumed && path == '/') {
      authLinkError!.consumed = true;
      return '/forgot-password';
    }

    // Checked first so no later rule can block these pages from anyone.
    if (_legalPaths.contains(path)) return null;

    if (session == null) {
      // Not signed in: only the landing page and public auth screens are
      // reachable; anything else lands on the front page.
      return _publicPaths.contains(path) ? null : '/';
    }

    // A recovery link signs the browser in, so this page has a session.
    // Treating it like the other public pages would make the link unusable.
    if (path == '/reset-password') return null;

    // Email not confirmed yet: keep them on '/verify-email'. '/' and '/login'
    // stay open so they can back out or sign in as someone else. This check
    // must stay above the public-paths rule, which would send them away.
    if (!SupabaseService.instance.isEmailVerified) {
      const allowedWhileUnverified = {'/verify-email', '/', '/login'};
      return allowedWhileUnverified.contains(path) ? null : '/verify-email';
    }

    if (_publicPaths.contains(path)) {
      // Signed in but on an auth screen: send them to their home page.
      final info = await SupabaseService.instance.getRoleAndStatus();
      if (info == null) return null;
      if (officerRoles.contains(info.role)) return '/admin';
      // Residents not yet approved have no dashboard, so they land on Profile.
      return info.status == 'pending_verification'
          ? '/me/profile'
          : '/dashboard';
    }

    if (path.startsWith('/admin')) {
      // Officer area: must be an officer and hold the route's permission,
      // which also stops someone typing the address directly.
      final role = await SupabaseService.instance.getMyRole();
      if (role == null || !officerRoles.contains(role)) return '/dashboard';
      // Exact match first, then prefix, so '/admin/people/42' uses the guard
      // of '/admin/people'.
      var guard = _officerRouteGuards[path];
      if (guard == null) {
        for (final entry in _officerRouteGuards.entries) {
          if (path.startsWith('${entry.key}/')) {
            guard = entry.value;
            break;
          }
        }
      }
      if (guard != null) {
        // A local copy, so the closure below can read it as non-null.
        final g = guard;
        final perms = await SupabaseService.instance.getMyPermissions();
        final allowed = g.modules.isEmpty ||
            g.modules.any((m) => g.action == null
                ? canAccessModule(perms, m)
                : canPerform(perms, m, g.action!));
        if (!allowed) return '/admin';
      }
      return null;
    }

    // Resident area: an account awaiting approval gets only Community Map and
    // Profile; anything else goes to Profile. The shells only hide the links.
    const pendingAllowedPaths = {'/me/community', '/me/profile'};
    final info = await SupabaseService.instance.getRoleAndStatus();
    if (info != null &&
        info.status == 'pending_verification' &&
        !pendingAllowedPaths.contains(path)) {
      return '/me/profile';
    }

    // Permission check for resident pages, so a link or typed address cannot
    // open a page the menu hides. Keep in step with member_shell's menu gates.
    const memberRouteModules = <String, String>{
      '/me/billing': 'bills',
      '/me/how-to-pay': 'bills',
      '/me/announcements': 'announcements',
      '/me/events': 'events',
      '/me/complaints': 'complaints',
      '/me/permits': 'permits',
      '/me/visitors': 'gate_passes',
      '/me/vehicles': 'vehicles',
      '/me/move-requests': 'move_requests',
      '/me/violations': 'violations',
      '/me/household': 'household_members',
    };
    String? memberModule = memberRouteModules[path];
    if (memberModule == null) {
      for (final e in memberRouteModules.entries) {
        if (path.startsWith('${e.key}/')) {
          memberModule = e.value;
          break;
        }
      }
    }
    if (memberModule != null && info != null && !officerRoles.contains(info.role)) {
      final perms = await SupabaseService.instance.getMyPermissions();
      if (!canAccessModule(perms, memberModule)) return '/dashboard';
    }

    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
        path: '/visitor', builder: (context, state) => const VisitorScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
        path: '/register', builder: (context, state) => const RegisterScreen()),
    GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen()),
    GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen()),
    GoRoute(
        path: '/verify-email',
        builder: (context, state) => const VerifyEmailScreen()),
    GoRoute(
        path: '/mfa-setup',
        builder: (context, state) => const MfaSetupScreen()),
    GoRoute(
        path: '/mfa-challenge',
        builder: (context, state) => const MfaChallengeScreen()),
    GoRoute(
        path: '/mfa-email',
        builder: (context, state) => const MfaEmailScreen()),
    // Public legal documents; see _legalPaths.
    GoRoute(
        path: '/terms',
        builder: (context, state) => const LegalPage(doc: LegalDoc.terms)),
    GoRoute(
        path: '/privacy',
        builder: (context, state) => const LegalPage(doc: LegalDoc.privacy)),
    // Shown when the server refuses a request or the app is offline.
    GoRoute(
        path: '/error',
        builder: (context, state) => ErrorScreen(
            code: state.uri.queryParameters['code'],
            from: state.uri.queryParameters['from'])),

    // --- Resident / tenant (MemberShell) ---
    GoRoute(
        path: '/dashboard',
        builder: (context, state) => const MemberDashboardScreen()),
    GoRoute(
        path: '/me/announcements',
        builder: (context, state) => const MemberAnnouncementsScreen()),
    GoRoute(
        path: '/me/events',
        builder: (context, state) => const MemberEventsScreen()),
    // My Payments (tabbed: My Bills / Payment History).
    GoRoute(
        path: '/me/billing',
        builder: (context, state) => const MemberPaymentsScreen()),
    // Pay a Bill form. `extra` is the tapped bill, and may be null.
    GoRoute(
      path: '/me/billing/pay',
      builder: (context, state) =>
          MemberPayBillScreen(bill: state.extra as Map<String, dynamic>?),
    ),
    // The association's GCash, Maya and bank accounts, with no bill attached.
    GoRoute(
        path: '/me/how-to-pay',
        builder: (context, state) => const MemberHowToPayScreen()),
    GoRoute(
        path: '/me/reservations',
        builder: (context, state) => const MemberReservationsScreen()),
    // My Permits: list, apply, view details.
    GoRoute(
        path: '/me/permits',
        builder: (context, state) => const MemberPermitsScreen()),
    GoRoute(
      path: '/me/permits/:id',
      builder: (context, state) => MemberPermitDetailScreen(
          permitId: int.parse(state.pathParameters['id']!)),
    ),
    // My Complaints: list + file a new one.
    GoRoute(
        path: '/me/complaints',
        builder: (context, state) => const MemberComplaintsScreen()),
    GoRoute(
        path: '/me/services',
        builder: (context, state) => const MemberServicesScreen()),
    // `extra` carries a saved draft to continue editing; null = new.
    GoRoute(
        path: '/me/complaints/new',
        builder: (context, state) => MemberFileComplaintScreen(
            draft: state.extra is Map<String, dynamic>
                ? state.extra as Map<String, dynamic>
                : null)),
    // My Visitors: active gate pass + visitor log + register a visitor.
    GoRoute(
        path: '/me/visitors',
        builder: (context, state) => const MemberVisitorsScreen()),
    GoRoute(
        path: '/me/visitors/new',
        builder: (context, state) => const MemberRegisterVisitorScreen()),
    // Move In/Out requests. The form opens as a dialog from this screen.
    GoRoute(
        path: '/me/move-requests',
        builder: (context, state) => const MemberMoveRequestsScreen()),
    GoRoute(
      path: '/me/violations',
      // Read-only for residents; only staff can update a violation.
      builder: (context, state) => const MemberModuleScreen(
        config: cases,
        navLabel: 'My Violations',
        selfFilterField: 'reported_against',
      ),
    ),
    // Documents shared with residents, with a working "View" button.
    GoRoute(
        path: '/me/documents',
        builder: (context, state) => const MemberDocumentsScreen()),
    GoRoute(
        path: '/me/files',
        builder: (context, state) => const MemberMyFilesScreen()),
    GoRoute(
        path: '/me/waste-schedule',
        builder: (context, state) => const MemberWasteScheduleScreen()),
    GoRoute(
        path: '/me/rules',
        builder: (context, state) => const MemberRulesScreen()),
    // My Vehicles: residents register their own cars. The shared form hides
    // the office's fields from them. No delete here; a car holding a sticker
    // is for the office to remove.
    GoRoute(
      path: '/me/vehicles',
      builder: (context, state) => const MemberModuleScreen(
        config: vehicles,
        navLabel: 'My Vehicles',
        selfFilterField: 'user_id',
        allowCreate: true,
        allowEdit: true,
      ),
    ),
    // My Household: residents add, edit and remove their own members.
    GoRoute(
      path: '/me/household',
      builder: (context, state) => const MemberModuleScreen(
        config: householdMembers,
        navLabel: 'My Household',
        selfFilterField: 'resident_id',
        allowCreate: true,
        allowEdit: true,
        allowDelete: true,
      ),
    ),
    GoRoute(
        path: '/me/settings',
        builder: (context, state) => const MemberSettingsScreen()),
    GoRoute(
        path: '/me/community',
        builder: (context, state) => const MemberCommunityScreen()),
    GoRoute(
        path: '/me/profile',
        builder: (context, state) => const MemberProfileScreen()),

    // --- Officer (AdminShell) ---
    GoRoute(
        path: '/admin',
        builder: (context, state) => const _OfficerDashboardRouter()),
    // Opens All Accounts on its Pending Approvals tab.
    GoRoute(
        path: '/admin/approvals',
        builder: (context, state) => const AllAccountsScreen(initialTab: 1)),
    GoRoute(
        path: '/admin/community',
        builder: (context, state) => const AdminCommunityScreen()),
    GoRoute(
        path: '/admin/reports',
        builder: (context, state) => const ReportsScreen()),
    GoRoute(
        path: '/admin/branding',
        builder: (context, state) => const BrandingScreen()),
    GoRoute(
        path: '/admin/profile',
        builder: (context, state) => const AdminProfileScreen()),
    // Both paths open the one tabbed Announcements & Events screen.
    GoRoute(
        path: '/admin/announcements',
        builder: (context, state) => const AnnouncementsEventsScreen()),
    GoRoute(
        path: '/admin/events',
        builder: (context, state) => const AnnouncementsEventsScreen()),
    // Tabbed Finance screen; `?tab=` picks the tab to open on.
    GoRoute(
        path: '/admin/finance',
        builder: (context, state) =>
            FinanceScreen(initialTab: state.uri.queryParameters['tab'])),
    // One bill's detail page.
    GoRoute(
      path: '/admin/billing/:id',
      builder: (context, state) =>
          BillDetailScreen(billId: int.parse(state.pathParameters['id']!)),
    ),
    // Tabbed Complaints and Cases screen.
    GoRoute(
        path: '/admin/community-concern',
        builder: (context, state) => const CommunityConcernScreen()),
    GoRoute(
        path: '/admin/waste-schedule',
        builder: (context, state) => const AdminWasteScheduleScreen()),
    GoRoute(
        path: '/admin/permits',
        builder: (context, state) => const AdminPermitsScreen()),
    GoRoute(
        path: '/admin/vehicles',
        builder: (context, state) => const AdminVehiclesScreen()),
    GoRoute(
        path: '/admin/visitors',
        builder: (context, state) => const AdminVisitorsScreen()),
    GoRoute(
        path: '/admin/move-requests',
        builder: (context, state) => const AdminMoveRequestsScreen()),
    GoRoute(
        path: '/admin/gate_passes',
        builder: (context, state) => const AdminGatePassesScreen()),
    GoRoute(
        path: '/admin/reservations',
        builder: (context, state) => const AdminReservationsScreen()),
    GoRoute(
        path: '/admin/accounts',
        builder: (context, state) => const AllAccountsScreen()),
    GoRoute(
      path: '/admin/people/:id',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        // A bad id shows the directory instead of a broken page.
        if (id == null) return const AllAccountsScreen();
        return PersonDetailScreen(userId: id);
      },
    ),
    GoRoute(
        path: '/admin/residents',
        builder: (context, state) => const AdminResidentsScreen()),
    GoRoute(
        path: '/admin/tenants',
        builder: (context, state) => const AdminTenantsScreen()),
    GoRoute(
        path: '/admin/security',
        builder: (context, state) => const AdminSecurityScreen()),
    GoRoute(
        path: '/admin/assigned',
        builder: (context, state) => const AssignedConcernsScreen()),
    GoRoute(
        path: '/admin/documents',
        builder: (context, state) => const AdminDocumentsScreen()),
    GoRoute(
        path: '/admin/my-files',
        builder: (context, state) => const MemberMyFilesScreen(officer: true)),
    GoRoute(
        path: '/admin/audit_logs',
        builder: (context, state) => const AdminAuditLogsScreen()),
    GoRoute(
        path: '/admin/backup',
        builder: (context, state) => const BackupScreen()),
    GoRoute(
        path: '/admin/system_settings',
        builder: (context, state) => const AdminSettingsScreen()),
    // The phone's middle tab: a grid of icons for the request screens.
    GoRoute(
        path: '/admin/services',
        builder: (context, state) => const OfficerServicesScreen()),
    // One generic-table route per registry module, so a new ModuleConfig gets
    // a route automatically. Modules in `_bespokeModuleScreens` are skipped.
    for (final module in moduleRegistry)
      if (!_bespokeModuleScreens.contains(module.key))
        GoRoute(
          path: module.route,
          builder: (context, state) => ModuleScreen(config: module),
        ),
  ],
);

/// Shows the right dashboard for `/admin`. Treasurer, secretary and security
/// have their own; every other officer gets [AdminDashboardScreen].
class _OfficerDashboardRouter extends StatelessWidget {
  const _OfficerDashboardRouter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: SupabaseService.instance.getMyRole(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        switch (snapshot.data) {
          case 'treasurer':
            return const TreasurerDashboardScreen();
          case 'secretary':
            return const SecretaryDashboardScreen();
          case 'security':
            return const SecurityDashboardScreen();
          default:
            return const AdminDashboardScreen();
        }
      },
    );
  }
}

/// Makes a desktop window shorter than [_minHeight] scroll instead of
/// overflowing off the bottom. Width is never locked, and phone widths pass
/// straight through.
class _ResponsiveCanvas extends StatelessWidget {
  final Widget child;
  const _ResponsiveCanvas({required this.child});

  static const _minHeight = 560.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;

      if (w < kMobileBreakpoint) return child;

      if (h >= _minHeight) return child;

      final mq = MediaQuery.of(context);
      // Do not add a `Scrollbar` here: AppScrollBehavior already gives this
      // scroll view one, and a second would stack on top.
      return SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SizedBox(
          width: w,
          height: _minHeight,
          child: MediaQuery(
            data: mq.copyWith(size: Size(w, _minHeight)),
            child: child,
          ),
        ),
      );
    });
  }
}

/// The root widget: theme, router, and the layers wrapped around every page
/// (idle timeout, guided tour, site banner, storage notice).
class NeighborSyncApp extends StatelessWidget {
  const NeighborSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app when branding or language changes, with no reload.
    return AnimatedBuilder(
      animation: Listenable.merge([AppBranding.instance, AppLocale.instance]),
      builder: (context, _) {
        return MaterialApp.router(
          // The browser tab title is the community's name.
          title: AppBranding.instance.communityName,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          // Scrollbar and overscroll rules for the whole app. Do NOT add a
          // `Scrollbar` on a screen; it would nest inside this one.
          scrollBehavior: const AppScrollBehavior(),
          routerConfig: _router,
          // IdleTimeout sits outside everything, so one timer covers every
          // screen. This builder is above the Navigator, so `context.go`
          // and `context.push` throw here; use `_router` directly.
          builder: (context, child) => IdleTimeout(
            onTimeout: (reason) {
              // The flag (?timeout=1) lets the login screen explain why.
              _router.go('/login?$reason=1');
            },
            // The tutorial and first-visit tips. Must stay OUTSIDE
            // _ResponsiveCanvas: that canvas scrolls, and the spotlight would
            // drift off the control it points at.
            child: GuidedTourHost(
              // Lets a tutorial step open the screen it describes.
              onNavigate: (route) => _router.go(route),
              currentLocation: () =>
                  _router.routerDelegate.currentConfiguration.uri.toString(),
              // A screen change triggers that screen's first-visit tips.
              locationChanges: _router.routerDelegate,
              child: _ResponsiveCanvas(
                child: Column(
                  children: [
                    const SiteBanner(),
                    Expanded(child: child ?? const SizedBox.shrink()),
                    // Below the content, so it never pushes the page down.
                    StorageNotice(onReadMore: () => _router.push('/privacy')),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
