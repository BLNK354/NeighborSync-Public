/// Short tips shown the first time someone opens a screen.
///
/// Tips are chosen per role, and each names only controls that role has.
/// Tips never carry a `route`; a tip whose control is not on screen
/// highlights the page instead.
library;

import 'tour_anchors.dart';
import 'tour_steps.dart';

/// The key a screen's tips are stored under once seen.
///
/// Routes that open the same screen share one key (`/admin/approvals` is
/// the Accounts screen), so the "seen" flag is not split between them.
String? tipKeyFor(String location) {
  final uri = Uri.tryParse(location);
  final path = uri?.path ?? location;
  if (path == '/admin/approvals') return '/admin/accounts';
  // A later tab (?tab=payments) gets its own key, matching the screen.
  final tab = uri?.queryParameters['tab']?.toLowerCase();
  if (tab != null && tab.isNotEmpty && tab != 'billing') return '$path#$tab';
  return path;
}

/// The tips for [key] as seen by [role], or empty when there are none.
List<TourStep> screenTipsFor({required String key, required String role}) {
  final bool readOnly = role == 'audit_officer';
  final bool admin = role == 'super_admin';
  // The HOA president and secretary also have the "All phases" switch.
  final bool president = role == 'hoa_president' || role == 'secretary';
  final bool deskOfficer =
      role == 'secretary' || role == 'hoa_president' || admin;

  switch (key) {
    // ---------------------------------------------------------------
    // Residents and tenants
    // ---------------------------------------------------------------
    case '/me/billing':
      return const [
        TourStep(
          title: 'Your bills',
          body: 'Every bill is listed with what is owed and when it is due. '
              'Pull down on any screen to reload the latest.',
          anchor: TourAnchorId.page,
        ),
        TourStep(
          title: 'Where to send the money',
          body: 'On an unpaid bill, tap the QR icon for the association\'s '
              'GCash, Maya or bank details. Pay with your own app, outside '
              'NeighborSync.',
          anchor: TourAnchorId.payQr,
        ),
        TourStep(
          title: 'Then send proof',
          body: 'Come back, tap Send Proof on that bill, choose which account '
              'you paid into and attach a photo of the receipt. The treasurer '
              'checks it and your bill updates -- you will be notified.',
          anchor: TourAnchorId.sendProof,
        ),
        TourStep(
          title: 'Receipts',
          body: 'The download button gives a Statement of Account before a '
              'payment is verified, and an Official Receipt with its own '
              'number once it is. A copy also lands in My Files.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/how-to-pay':
      return const [
        TourStep(
          title: 'The association\'s accounts',
          body: 'These are the only accounts dues should go to. Scan the QR '
              'code or copy the number into your own banking or e-wallet '
              'app. Afterwards, go to My Payments and tap Send Proof.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/visitors':
      return const [
        TourStep(
          title: 'Register visitors ahead of time',
          body: 'Enter the visitor\'s name, contact, why they are coming and '
              'when. A pass with a QR code is created. It goes to the '
              'guardhouse for approval first, so do it before your guest is '
              'waiting at the gate.',
          anchor: TourAnchorId.registerVisitor,
        ),
        TourStep(
          title: 'Send the pass as a picture',
          body: 'Save the pass as an image and send it to your visitor. '
              'Treat it like a ticket -- whoever holds it can present it, so '
              'send it to them and nobody else.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/complaints':
      return const [
        TourStep(
          title: 'Reporting a problem',
          body: 'Your details fill in automatically. Choose a category, say '
              'what happened, where and when, and attach a photo if you have '
              'one.',
          anchor: TourAnchorId.fileComplaint,
        ),
        TourStep(
          title: 'You can correct it -- for a while',
          body: 'While a complaint still says Submitted you can edit it and '
              'add evidence. Once an officer picks it up, your account of '
              'events becomes the record.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/waste-schedule':
      return const [
        TourStep(
          title: 'Your collection days',
          body: 'This shows your own phase\'s schedule -- the chip at the top '
              'says which. Collection days are shaded on the calendar in the '
              'colour of the waste type. "Show all phases" shows the rest.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/permits':
      return const [
        TourStep(
          title: 'Permits',
          body: 'Apply for construction, renovation or works here and follow '
              'its progress. You can correct an application while it is '
              'still waiting for the office.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/vehicles':
      return const [
        TourStep(
          title: 'Your vehicles',
          body: 'Register each car or motorcycle here. It is filed to your '
              'address and starts as pending until an officer registers it '
              'and issues the sticker.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/move-requests':
      return const [
        TourStep(
          title: 'Moving in or out',
          body: 'Tell the office the date you are moving so the guardhouse '
              'expects the truck.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/reservations':
      return const [
        TourStep(
          title: 'Booking a facility',
          body: 'Book the function hall, court or another shared facility. '
              'A slot that is already taken is refused straight away rather '
              'than letting two people book it.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/violations':
      return const [
        TourStep(
          title: 'Cases on your household',
          body: 'Any case filed against your household is listed here. You '
              'can read them; only the office can change them.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/household':
      return const [
        TourStep(
          title: 'Your household',
          body: 'List the people living with you, so the office knows who '
              'lives at your address.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/files':
      return const [
        TourStep(
          title: 'Your own documents',
          body: 'Sorted into folders. Receipts and proofs of payment are '
              'filed here automatically, and only you and the office can see '
              'them.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/profile':
      return const [
        TourStep(
          title: 'Your address',
          body: 'Choose your block and lot here. Until an officer approves '
              'it, this is what they check your application against.',
          anchor: TourAnchorId.selectAddress,
        ),
        TourStep(
          title: 'Proof of ownership',
          body: 'A land title, tax declaration, deed of sale, lease or utility '
              'bill -- JPG, PNG or PDF, up to 8 MB. Only officers can open '
              'it. Renting? Upload your lease.',
          anchor: TourAnchorId.ownershipProof,
        ),
        TourStep(
          title: 'Keeping your account safe',
          body: 'Change Password asks for your current one first. "Sign out '
              'other devices" ends every other session within the hour. '
              'Recent Sign-ins is a record, not a switch.',
          anchor: TourAnchorId.page,
        ),
      ];

    // ---------------------------------------------------------------
    // Officers
    // ---------------------------------------------------------------
    case '/admin/accounts':
      if (!deskOfficer) return const [];
      return const [
        TourStep(
          title: 'Pending approvals',
          body: 'Nobody can use NeighborSync until they are approved here. '
              'Each card shows the address claimed and any proof of '
              'ownership.',
          anchor: TourAnchorId.pendingTab,
        ),
        TourStep(
          title: 'Read the address colour',
          body: 'Green: the lot is free. Red: someone is already recorded '
              'there. Amber: no address claimed. Correct a wrong lot from the '
              'dropdown rather than rejecting them.',
          anchor: TourAnchorId.page,
        ),
        TourStep(
          title: 'Role, phase, approve',
          body: 'Choose the role. For an officer, set the phase too -- an '
              'officer with no phase signs in to an empty system. Approving '
              'is what gives them their lot. A member\'s row also has a '
              'password-reset action; you never see their password.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/community-concern':
      if (readOnly) {
        return const [
          TourStep(
            title: 'Complaints and cases',
            body: 'Both share this screen as two tabs. An amber chip beside a '
                'category means the system read the complaint and disagrees '
                'with it. Filters narrow the list.',
            anchor: TourAnchorId.page,
          ),
        ];
      }
      return const [
        TourStep(
          title: 'The amber chip',
          body: 'If an amber chip sits beside a category, the system read the '
              'complaint and disagrees with what the resident chose. Tap it '
              'to refile.',
          anchor: TourAnchorId.page,
        ),
        TourStep(
          title: 'Assign and close',
          body: 'The assignee list only offers officers whose job covers that '
              'category. To close a complaint, set it Resolved and write what '
              'was done -- an empty resolution is refused.',
          anchor: TourAnchorId.page,
        ),
        TourStep(
          title: 'Whose words are whose',
          body: 'The resident\'s subject, description, location and date are '
              'theirs. You own category, priority, status, assignment and '
              'resolution. Fields you cannot change say why.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/announcements':
      if (readOnly) return const [];
      if (admin) {
        return const [
          TourStep(
            title: 'The "All phases" switch',
            body: 'You, the HOA presidents and the secretaries have it. A notice goes to the phase you are '
                'viewing unless you tick All phases on the form -- leave it '
                'off unless you mean the whole subdivision.',
            anchor: TourAnchorId.page,
          ),
        ];
      }
      if (president) {
        return const [
          TourStep(
            title: 'The "All phases" switch',
            body: 'A notice goes to your own phase unless you tick All '
                'phases on the form -- leave it off unless you mean the whole '
                'subdivision. You can edit or delete only the all-phase '
                'posts you made yourself.',
            anchor: TourAnchorId.page,
          ),
        ];
      }
      return const [
        TourStep(
          title: 'Posting to your phase',
          body: 'Everything you post here reaches your own phase\'s '
              'residents. A notice for the whole subdivision comes from the '
              'system administrator.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/waste-schedule':
      if (!deskOfficer) return const [];
      return const [
        TourStep(
          title: 'Your phase\'s schedule',
          body: 'Set the collection day for each waste type. Residents see '
              'only their own phase\'s schedule. A rest day has no time.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/reservations':
      if (!deskOfficer) return const [];
      return const [
        TourStep(
          title: 'Taking a booking at the desk',
          body: 'Approve bookings here, or use Book for a Resident when '
              'someone phones or walks in -- that saves as approved '
              'immediately. A taken slot is refused automatically.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/documents':
      if (readOnly) return const [];
      return const [
        TourStep(
          title: 'The shared folders',
          body: 'This is the office\'s shared folder tree. To file something '
              'for one household, use Files on their row in Residents -- it '
              'lands in their own My Files.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/finance':
      return [
        const TourStep(
          title: 'Billing: the totals cover everything',
          body: 'Total Billed, Outstanding, Overdue and Collected are counted '
              'across every bill, even when the list below shows only the '
              'newest 300.',
          anchor: TourAnchorId.page,
        ),
        if (!readOnly)
          const TourStep(
            title: 'You do not set a bill\'s status',
            body: 'It moves itself as payments are verified, and overdue '
                'bills are marked overnight. Cancel and Waive are named '
                'actions on the bill itself, and both ask for a reason.',
            anchor: TourAnchorId.page,
          ),
        if (!readOnly)
          const TourStep(
            title: 'First job: payment channels',
            body: 'Until the association\'s GCash, Maya or bank accounts are '
                'added under Channels, residents cannot find out where to pay.',
            anchor: TourAnchorId.channelsTab,
          ),
      ];

    case '/admin/finance#payments':
      return [
        TourStep(
          title: 'Payments',
          body: readOnly
              ? 'Every payment recorded against a bill, with who verified it.'
              : 'Residents\' receipts wait in an amber queue above the table. '
                  'Verify shows the receipt beside the bill total, what is '
                  'paid and the balance -- approve, or reject with a reason.',
          anchor: TourAnchorId.page,
        ),
        if (!readOnly)
          const TourStep(
            title: 'Only a verified payment counts',
            body: 'A payment left at Pending changes nothing on the bill. A '
                'verified payment on a bill with nothing left to pay is '
                'refused.',
            anchor: TourAnchorId.page,
          ),
      ];

    case '/admin/finance#budget':
      return [
        TourStep(
          title: 'Budget',
          body: readOnly
              ? 'Each category\'s allocation against what has been spent, '
                  'for the fiscal year shown at the top.'
              : 'Add Category sets an allocation for the year, and a card '
                  'shows the year\'s running total. The year button at the '
                  'top switches fiscal year.',
          anchor: TourAnchorId.page,
        ),
        if (!readOnly)
          const TourStep(
            title: 'Recording an expense',
            body: 'Record Expense, or + Expense on a category row. The date is '
                'yours to set, so a receipt entered late is still filed on '
                'the right day.',
            anchor: TourAnchorId.page,
          ),
      ];

    case '/admin/finance#channels':
      return [
        TourStep(
          title: 'Where dues are sent',
          body: readOnly
              ? 'The association\'s GCash, Maya and bank accounts, exactly as '
                  'residents see them under How to Pay.'
              : 'Add Channel for each account, with its name, number and QR '
                  'image. Residents see these under How to Pay and on every '
                  'unpaid bill, so check the numbers carefully.',
          anchor: TourAnchorId.page,
        ),
        if (!readOnly)
          const TourStep(
            title: 'Scope and the QR image',
            body: 'A channel defaults to your own phase. Upload the original '
                'QR image -- one re-saved through an editor can stop scanning.',
            anchor: TourAnchorId.page,
          ),
      ];

    case '/admin/gate_passes':
      return [
        const TourStep(
          title: 'Scanning a pass',
          body: 'Tap Scan Pass and point the camera at the visitor\'s QR '
              'code. You get their name, the address they are visiting, the '
              'host\'s phone number and a plain verdict.',
          anchor: TourAnchorId.scanPass,
        ),
        const TourStep(
          title: 'Trust the verdict, not the status word',
          body: 'A pass can still say Pending months after it expired. The '
              'scanner checks the real dates. Scanning changes nothing -- it '
              'is a lookup, not an approval; you still act through Review.',
          anchor: TourAnchorId.page,
        ),
        if (!readOnly)
          const TourStep(
            title: 'Facts you learn at the gate',
            body: 'You can issue a pass for a resident at the desk, and '
                'correct the plate or extend the validity on an existing '
                'one.',
            anchor: TourAnchorId.page,
          ),
      ];

    case '/admin/visitors':
      return [
        const TourStep(
          title: 'The purpose is the clock',
          body: 'You do not set how long a visitor may stay -- the purpose '
              'does. A delivery gets 30 minutes, a contractor 8 hours, a '
              'guest 12. Anyone still inside past that is flagged.',
          anchor: TourAnchorId.page,
        ),
        if (!readOnly)
          const TourStep(
            title: 'Logging someone in and out',
            body: 'Pick the host -- the list shows name and phone together. '
                'Time in defaults to now, and the resident is notified. '
                'Recording the time out is what closes the entry.',
            anchor: TourAnchorId.page,
          ),
      ];

    case '/admin/security':
      if (readOnly) return const [];
      return const [
        TourStep(
          title: 'Incidents you log are yours',
          body: 'Only you can rewrite what you wrote. Other officers can '
              'change severity, status and assignment. A case cannot be '
              'closed without saying what was done.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/assigned':
      return const [
        TourStep(
          title: 'Work handed to you',
          body: 'Complaints assigned to you land here. You can close one and '
              'write what you did yourself, without going through the '
              'secretary.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/audit_logs':
      return const [
        TourStep(
          title: 'Every change, recorded',
          body: 'Who, when, which record, and which fields moved from what to '
              'what. Nothing in the app can write to this table -- including '
              'the administrator.',
          anchor: TourAnchorId.page,
        ),
        TourStep(
          title: 'Reading the trail',
          body: 'Filter by module or action. Critical marks role, permission '
              'and settings changes; warning marks deletions and money. '
              '"System" means a scheduled job. Opening a household\'s file, '
              'exports and backup downloads are logged too.',
          anchor: TourAnchorId.page,
        ),
      ];

    // ---------------------------------------------------------------
    // System administrator
    // ---------------------------------------------------------------
    case '/admin/system_settings':
      if (!admin) return const [];
      return const [
        TourStep(
          title: 'Phases live here',
          body: 'A phase is one association: its own officers, dues and '
              'records. Create one by number only -- if it is divided, say how '
              'many parts and the letters (4A, 4B) are generated for you.',
          anchor: TourAnchorId.phasesTab,
        ),
        TourStep(
          title: 'The three-dot menu on a phase',
          body: 'Deactivate hides it and keeps everything. Delete only works '
              'on an empty phase. Community map uploads its survey plan. Move '
              'a Household moves a family between phases -- switch to All '
              'phases first.',
          anchor: TourAnchorId.phasesTab,
        ),
      ];

    case '/admin/branding':
      if (!admin && !deskOfficer) return const [];
      return const [
        TourStep(
          title: 'How the community looks',
          body: 'Branding, the home page, the Terms and Privacy text, '
              'facilities and categories. A save reaches every signed-in '
              'device and the public page within seconds.',
          anchor: TourAnchorId.page,
        ),
        TourStep(
          title: 'The legal text is a draft',
          body: 'The starter Terms and Privacy Notice are a first version. '
              'Have the board read them -- every new member agrees to them, '
              'and that agreement is recorded.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/backup':
      return const [
        TourStep(
          title: 'A backup contains everything',
          body: 'Every payment, complaint and resident\'s details, with none '
              'of the usual protections. Take one before real data goes in, '
              'and treat a downloaded file like the filing cabinet keys.',
          anchor: TourAnchorId.page,
        ),
      ];
    // ---------------------------------------------------------------
    // More officer tabs and screens
    // ---------------------------------------------------------------
    case '/admin/community-concern#cases':
      return [
        TourStep(
          title: 'Cases',
          body: readOnly
              ? 'Violation cases filed against households, with their '
                  'status. The cards at the top count open, resolved and '
                  'repeat offenders.'
              : 'Issue Violation files a case. Choosing the person fills in '
                  'their address; choosing an address fills in the person '
                  'only if it is still blank.',
          anchor: TourAnchorId.page,
        ),
        if (!readOnly)
          const TourStep(
            title: 'The status track',
            body: 'Reported, Noticed, Upheld, Penalty Imposed, Resolved. '
                'Contested and Dismissed are off the track. Closing a case '
                'needs a note saying what was done.',
            anchor: TourAnchorId.page,
          ),
      ];

    case '/admin/announcements#events':
      return [
        TourStep(
          title: 'Events',
          body: readOnly
              ? 'The community calendar. Upcoming events are listed beside it.'
              : 'New Event adds one to the calendar; List View shows them as '
                  'a list. Open an event to edit it or cancel it -- a '
                  'cancelled event stays on record.',
          anchor: TourAnchorId.page,
        ),
        if (!readOnly)
          TourStep(
            title: 'Who sees it',
            body: admin || president
                ? 'Public puts it on the visitor page too. All phases sends '
                    'it to every phase.'
                : 'It reaches your own phase\'s residents. Public also puts '
                    'it on the visitor page.',
            anchor: TourAnchorId.page,
          ),
      ];

    case '/admin/residents':
      return const [
        TourStep(
          title: 'The residents of your phase',
          body: 'What you can do on a row depends on your role -- Edit, Files '
              'and Reset password appear only for those who can use them. '
              'Filter narrows the list.',
          anchor: TourAnchorId.page,
        ),
        TourStep(
          title: 'Names open the whole file',
          body: 'Where the name is a link, it opens one household\'s bills, '
              'complaints, permits, vehicles and more on one page. A '
              'requested address shows a tick to approve it or a cross to '
              'refuse it.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/tenants':
      return const [
        TourStep(
          title: 'Tenants',
          body: 'Each tenant with their landlord and lease end date. Edit, '
              'Files and Reset password appear only for roles that can use '
              'them.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/permits':
      return [
        TourStep(
          title: 'Permits',
          body: readOnly
              ? 'Every permit application in your phase and where it stands.'
              : 'Review opens an application: set the fee and payment '
                  'status, add notes, and move it through Submitted, Under '
                  'Review, Approved.',
          anchor: TourAnchorId.page,
        ),
        if (!readOnly)
          const TourStep(
            title: 'Filing at the desk',
            body: 'Apply for Permit lets you file one for a resident -- choose '
                'the applicant and the lot fills in. The permit number is '
                'issued by the system.',
            anchor: TourAnchorId.page,
          ),
      ];

    case '/admin/vehicles':
      return const [
        TourStep(
          title: 'Vehicles',
          body: 'Tap a row to read it; Edit is a separate action for those who '
              'can change it. Residents register their own cars, which '
              'arrive as Pending.',
          anchor: TourAnchorId.page,
        ),
        TourStep(
          title: 'Stickers',
          body: 'Registering a vehicle and issuing its sticker is the '
              'office\'s job. A vehicle\'s card says so once its sticker has expired.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/move-requests':
      return [
        TourStep(
          title: 'Move In/Out',
          body: readOnly
              ? 'Every move request and its date.'
              : 'Move a request along Pending, Approved, Scheduled, '
                  'Completed. New Request files one for a resident at the '
                  'desk.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/household_members':
      return const [
        TourStep(
          title: 'Household members',
          body: 'Grouped by household, with the owner\'s name as the heading. '
              'Residents add their own members from their side.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/community':
      return const [
        TourStep(
          title: 'The community map',
          body: 'Your phase\'s survey plan with each lot pinned. Open a lot or '
              'a block for its details.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/admin/reports':
      return const [
        TourStep(
          title: 'Reports',
          body: 'Financial, community and occupancy summaries with charts. '
              'Exporting one is recorded on the audit trail.',
          anchor: TourAnchorId.page,
        ),
      ];

    // ---- resident side ----
    case '/me/announcements':
      return const [
        TourStep(
          title: 'Announcements',
          body: 'Notices for your phase plus anything posted to the whole '
              'subdivision, newest first.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/events':
      return const [
        TourStep(
          title: 'Events',
          body: 'Upcoming community events for your phase and the whole '
              'subdivision.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/community':
      return const [
        TourStep(
          title: 'Your address on the map',
          body: 'Your own lot is marked, with the address written underneath. '
              'Other households are not shown.',
          anchor: TourAnchorId.page,
        ),
      ];

    case '/me/documents':
      return const [
        TourStep(
          title: 'Documents',
          body: 'Files the office has shared with residents. Your own files '
              'are under My Files.',
          anchor: TourAnchorId.page,
        ),
      ];
  }
  return const [];
}
