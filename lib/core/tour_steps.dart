/// The text of the first-run tour, per role.
///
/// Each role gets only the steps for screens it can reach. Every step must
/// describe a screen or feature that really exists.
library;

import 'tour_anchors.dart';
import 'roles.dart';

/// One card of the tour.
class TourStep {
  final String title;
  final String body;

  /// Region to spotlight, or null for a plain centred card. If the anchor
  /// is not on screen the step still shows, centred.
  final String? anchor;

  /// Screen opened while this step is shown; null for steps about the
  /// menu, search box or bell. Must match a route in `main.dart` that the
  /// role is allowed to open, or the router bounces them mid-tour.
  final String? route;

  /// Shows an "Open my guide (PDF)" button, linking the role guide
  /// uploaded in CMS -> Official Forms.
  final bool offersGuide;

  const TourStep({
    required this.title,
    required this.body,
    this.anchor,
    this.route,
    this.offersGuide = false,
  });
}

/// The tour steps for this person.
///
/// [narrow] picks the phone tab bar instead of the desktop sidebar as the
/// "where things live" anchor.
List<TourStep> tourFor({
  required String role,
  required String status,
  required bool narrow,
  required String communityName,
}) {
  // Pending accounts only reach the community page and their profile
  // (pendingAllowedPaths in main.dart), so they get a short tour.
  if (status == 'pending_verification') {
    return const [
      TourStep(
        title: 'Your account is waiting for approval',
        body:
            'An officer of the association still has to confirm that you '
            'live here. Until then you can see the community map and your '
            'own profile, and not much else. That is expected.',
      ),
      TourStep(
        title: 'Help them approve you faster',
        body:
            'Open your profile and add two things: the address you are '
            'claiming, and a proof of ownership or your lease. The officer '
            'reviewing your application sees both on their screen, and an '
            'application with no proof attached is the one that sits '
            'longest.',
        anchor: TourAnchorId.page,
        route: '/me/profile',
      ),
      TourStep(
        title: 'You will be told',
        body:
            'When you are approved, a notification arrives here and the '
            'rest of the app opens up. You do not need to keep checking.',
        anchor: TourAnchorId.bell,
      ),
    ];
  }

  if (officerRoles.contains(role)) {
    return _officerTour(role: role, narrow: narrow, communityName: communityName);
  }
  if (outsiderRoles.contains(role)) {
    return _outsiderTour(role: role, narrow: narrow);
  }
  return _residentTour(role: role, narrow: narrow, communityName: communityName);
}

// ---------------------------------------------------------------------
// Residents and tenants
// ---------------------------------------------------------------------

/// Tour for homeowners and tenants; tenants skip the permit wording.
List<TourStep> _residentTour({
  required String role,
  required bool narrow,
  required String communityName,
}) {
  final whereThingsLive = narrow ? TourAnchorId.tabs : TourAnchorId.nav;

  return [
    TourStep(
      title: 'Welcome to $communityName',
      body:
          // Tenants have no permits permission, so permits are left out.
          role == 'tenant'
              ? 'This is the homeowners association portal. Dues, complaints '
                  'and visitors all happen here instead of at the office. '
                  'This will take about a minute.'
              : 'This is the homeowners association portal. Dues, complaints, '
                  'visitors and permits all happen here instead of at the office. '
                  'This will take about a minute.',
    ),
    TourStep(
      title: narrow ? 'Everything is down here' : 'Everything is in this menu',
      body: narrow
          ? 'The tabs along the bottom are the four things you will use '
              'most. Tap the menu button for the rest -- documents, the '
              'waste collection schedule, the community rules.'
          : 'The menu is grouped: My Finances, Community, My Requests. '
              'Tap a heading to fold it away if you never use it.',
      anchor: whereThingsLive,
    ),
    const TourStep(
      title: 'Paying your dues',
      body:
          'My Payments lists every bill. Open "How to Pay" to see the '
          'association\'s GCash, Maya and bank details -- then pay, and '
          'come back and tap Send Proof with a photo of the receipt. The '
          'treasurer checks it and your bill updates.',
      anchor: TourAnchorId.page,
      route: '/me/billing',
    ),
    TourStep(
      title: 'Asking the association for something',
      body: role == 'tenant'
          ? 'Under My Requests: file a complaint, request a gate pass so the '
              'guardhouse expects them, or book the function hall. You can '
              'correct anything you send while it is still pending.'
          : 'Under My Requests: file a complaint, request a gate pass so the '
              'guardhouse expects them, apply for a construction permit, or '
              'book the function hall. You can correct anything you send while '
              'it is still pending.',
      anchor: TourAnchorId.page,
      route: '/me/complaints',
    ),
    const TourStep(
      title: 'Their reply comes here',
      body:
          'When an officer approves a request, answers a complaint or '
          'confirms a payment, the bell tells you. It updates on its own '
          '-- you do not have to reload the page.',
      anchor: TourAnchorId.bell,
    ),
    TourStep(
      title: role == 'tenant' ? 'Your details' : 'Your home on record',
      body: role == 'tenant'
          ? 'Your profile holds your contact details and your lease. Keep '
              'the phone number current -- it is what the guardhouse reads '
              'off a gate pass when a visitor arrives for you.'
          : 'Your profile holds your address, your household members and '
              'your proof of ownership. Keep the phone number current -- it '
              'is what the guardhouse calls when someone arrives for you.',
      anchor: TourAnchorId.page,
      route: '/me/profile',
    ),
    const TourStep(
      title: 'Stuck? Tap the ?',
      body:
          'The ? beside the bell opens "How do I…?" guides -- paying dues, '
          'registering a visitor, filing a complaint and more -- each shown '
          'on the real screen. Replay this tour from Settings.',
      anchor: TourAnchorId.help,
      offersGuide: true,
    ),
  ];
}

// ---------------------------------------------------------------------
// Guests
// ---------------------------------------------------------------------

/// Short tour for guests with a temporary account.
List<TourStep> _outsiderTour({required String role, required bool narrow}) {
  final whereThingsLive = narrow ? TourAnchorId.tabs : TourAnchorId.nav;

  return [
    const TourStep(
      title: 'Welcome',
      body:
          'You have a temporary account. It expires on the date the '
          'association set, and then stops working -- that is normal, not '
          'a fault.',
    ),
    const TourStep(
      title: 'What you can see',
      body:
          'The community map, the announcements and the events calendar. '
          'Billing, complaints and permits belong to residents, so they '
          'are not shown.',
      anchor: TourAnchorId.page,
      route: '/me/community',
    ),
    TourStep(
      title: 'Finding your way',
      body: 'Everything you can open is in this menu. Tap the ? at the top '
          'any time for step-by-step help.',
      anchor: whereThingsLive,
    ),
  ];
}

// ---------------------------------------------------------------------
// Officers
// ---------------------------------------------------------------------

/// Tour for officers: menu, search, role-specific work, bell, phase scope.
List<TourStep> _officerTour({
  required String role,
  required bool narrow,
  required String communityName,
}) {
  final steps = <TourStep>[
    TourStep(
      title: 'Welcome to the $communityName officers\' portal',
      body: _officerOpening(role),
    ),
    TourStep(
      title: narrow ? 'Your screens are in the menu' : 'Your screens are in this menu',
      body: narrow
          ? 'Tap the menu button for everything you have access to. What '
              'appears depends on your role -- you will not see screens you '
              'cannot act on.'
          : 'Grouped by area, and foldable. What appears depends on your '
              'role -- you will not see screens you cannot act on. The '
              'toggle in the top bar shrinks this to icons when you need '
              'the width.',
      anchor: TourAnchorId.nav,
    ),
  ];

  // Desktop only; the search box is the only search, so officers must
  // be told about it.
  if (!narrow) {
    steps.add(const TourStep(
      title: 'One search box for everything',
      body:
          'Type a name, a bill number, a plate or a reference here and it '
          'looks across the whole system at once. The individual screens '
          'deliberately have no search box of their own -- this is it.',
      anchor: TourAnchorId.search,
    ));
  }

  // Each work step opens the screen it describes and lights that page.
  steps.addAll(_officerWork(role));

  steps.add(const TourStep(
    title: 'New work arrives here',
    body:
        'When a resident files something that belongs to you, the bell '
        'tells you and tapping it opens the right queue. It updates by '
        'itself.',
    anchor: TourAnchorId.bell,
  ));

  // Phase officers are told why their lists are smaller; only the
  // super admin can switch phases.
  steps.add(TourStep(
    title: role == 'super_admin' ? 'You are viewing one phase' : 'You see your own phase',
    body: role == 'super_admin'
        ? 'Each phase is a separate association with its own officers and '
            'its own dues. This control switches which one you are looking '
            'at, or shows all of them at once. Every screen follows it.'
        : 'Each phase is a separate association. Every list you open is '
            'already limited to yours -- so a smaller number than you '
            'expected is the scope working, not data missing.',
    anchor: TourAnchorId.phase,
  ));

  steps.add(const TourStep(
    title: 'Stuck? Tap the ?',
    body:
        'The ? beside the bell opens "How do I…?" guides for everything '
        'your role can do, each shown on the real screen. Replay this tour '
        'from Settings.',
    anchor: TourAnchorId.help,
    offersGuide: true,
  ));

  return steps;
}

/// Opening line of the officer tour, by role.
String _officerOpening(String role) => switch (role) {
      'security' =>
        'You are signed in as security. This portal is the gate log, the '
            'visitor records and the incident reports.',
      'treasurer' =>
        'You are signed in as treasurer. This portal is billing, payments '
            'and the budget.',
      'audit_officer' =>
        'You are signed in as audit officer. Your account is read-only by '
            'design -- you can see the association\'s records but not '
            'change them, which is what makes the oversight independent.',
      'super_admin' =>
        'You are signed in as the system administrator. You are not an HOA '
            'officer -- you can see every phase, which no association '
            'officer can.',
      _ =>
        'This portal is where the association\'s work happens: approvals, '
            'complaints, announcements and records.',
    };

/// The role-specific work steps of the officer tour.
List<TourStep> _officerWork(String role) => switch (role) {
      'security' => [
          const TourStep(
            anchor: TourAnchorId.page,
            route: '/admin/visitors',
            title: 'The gate',
            body:
                'Visitors is the log: record someone in when they arrive '
                'and out when they leave. The time allowed comes from what '
                'they are here for -- a delivery gets 30 minutes, a guest '
                'gets the day -- and anyone still inside past that is '
                'flagged for you.',
          ),
          const TourStep(
            anchor: TourAnchorId.page,
            route: '/admin/gate_passes',
            title: 'Scanning a gate pass',
            body:
                'A resident expecting someone registers them and the '
                'visitor arrives with a QR code. Scan it and you get the '
                'visitor\'s name, whether the pass is still valid, and the '
                'host\'s phone number. Check the name against the person '
                'in front of you.',
          ),
          const TourStep(
            anchor: TourAnchorId.page,
            route: '/admin/security',
            title: 'Incidents and complaints',
            body:
                'Log an incident and it is yours -- only you can rewrite '
                'what you wrote, though any officer can change its status. '
                'Complaints assigned to you appear under Assigned to Me, '
                'and you can close them yourself.',
          ),
        ],
      'treasurer' => [
          const TourStep(
            anchor: TourAnchorId.page,
            route: '/admin/finance',
            title: 'Billing',
            body:
                'Generate bills and watch the totals at the top: billed, '
                'collected, outstanding, overdue. Those totals cover every '
                'bill, not just the page you are looking at.',
          ),
          const TourStep(
            anchor: TourAnchorId.page,
            // Opens the Payments tab.
            route: '/admin/finance?tab=payments',
            title: 'Proof of payment',
            body:
                'Residents send a photo of their receipt. Open it before '
                'you verify -- the review screen puts the receipt, the '
                'amount and what the bill still owes side by side. If it '
                'is wrong, reject it with a reason. Verifying is what makes '
                'the bill move.',
          ),
          const TourStep(
            anchor: TourAnchorId.page,
            // Must match a tab name in FinanceScreen._tabs.
            route: '/admin/finance?tab=channels',
            title: 'Where dues are sent',
            body:
                'Payment Channels holds the association\'s GCash, Maya and '
                'bank accounts with their QR codes. What you put there is '
                'what residents see under "How to Pay", so check the '
                'account numbers carefully.',
          ),
        ],
      'audit_officer' => [
          const TourStep(
            anchor: TourAnchorId.page,
            route: '/admin/finance',
            title: 'What you can see',
            body:
                'Finance, complaints, incidents, permits, violations -- the '
                'association\'s operational record. Household members are '
                'deliberately excluded, and so are private messages.',
          ),
          const TourStep(
            anchor: TourAnchorId.page,
            route: '/admin/audit_logs',
            title: 'The audit trail',
            body:
                'Audit Logs records every change to every record: who, '
                'when, and what the value was before and after. It is '
                'written by the database itself, so nothing can be done '
                'without leaving a row -- including by an administrator.',
          ),
        ],
      _ => [
          const TourStep(
            anchor: TourAnchorId.page,
            // All Accounts, opened on its Pending Approvals tab.
            route: '/admin/approvals',
            title: 'Approving new homeowners',
            body:
                'All Accounts has a Pending Approvals tab. Each application '
                'shows the address being claimed and whether it is already '
                'on record to somebody, plus any proof they uploaded. '
                'Approving is what assigns them their lot.',
          ),
          const TourStep(
            anchor: TourAnchorId.page,
            route: '/admin/community-concern',
            title: 'Complaints and requests',
            body:
                'Community Concerns is the queue. Assign a complaint to the '
                'officer whose job it is and the system suggests a category '
                'for you -- if it disagrees with what the resident picked, '
                'it says so and you can refile it in one tap.',
          ),
          TourStep(
            anchor: TourAnchorId.page,
            route: '/admin/announcements',
            title: 'Telling everyone something',
            // Only the super admin, HOA president and secretary have the
            // "All phases" switch.
            body: role == 'super_admin'
                ? 'Announcements and Events reach residents\' phones. Each '
                    'one goes to the phase you are viewing unless you tick '
                    '"All phases", so check that switch before a notice '
                    'goes to the whole subdivision.'
                : role == 'hoa_president' || role == 'secretary'
                ? 'Announcements and Events reach residents\' phones. They '
                    'go to your own phase unless you tick "All phases" on '
                    'the form, which sends them to the whole subdivision. '
                    'You can edit or delete only the all-phase posts you made.'
                : 'Announcements and Events reach residents\' phones. '
                    'Everything you post goes to your own phase\'s '
                    'residents only.',
          ),
        ],
    };
