/// "How do I...?" guides shown from the ? button beside the bell.
///
/// Each guide is a short walkthrough on the real screen: the first step opens
/// the screen, the rest point at what to press.
///
/// A guide is shown only if it fits the reader: the right portal (resident
/// `/me/...` or officer `/admin/...`) and the permission its task needs,
/// checked against the live permission set. Every guide must name a control
/// that exists for the role reading it.
library;

import 'permissions.dart';
import 'tour_anchors.dart';
import 'tour_steps.dart';

class HelpGuide {
  /// The question, exactly as the reader would ask it.
  final String question;

  /// Grouping heading in the help menu.
  final String section;

  /// True for officer-portal guides (`/admin/...`), false for the resident
  /// portal (`/me/...`). An officer also holds `complaints:create`, but a
  /// resident's "file a complaint" guide opens a screen they never use.
  final bool officer;

  /// The permission the task needs, as `module:action`, or `module` for
  /// "any access to it". Null means everyone in that portal.
  final String? needs;

  /// Extra role restriction where a permission does not capture it (a
  /// tenant holds `permits` read but files no permits; the phase tools are
  /// the administrator's). Null means any role that passes [needs].
  final Set<String>? roles;

  /// The walkthrough steps; the first one names the screen to open.
  final List<TourStep> steps;

  const HelpGuide({
    required this.question,
    required this.section,
    required this.officer,
    required this.steps,
    this.needs,
    this.roles,
  });

  /// The screen this guide is about, for "On this screen" in the menu.
  String? get route => steps.first.route;
}

/// The guides this person can use.
List<HelpGuide> helpGuidesFor({
  required String role,
  required bool isOfficer,
  required Map<String, Set<String>> perms,
}) {
  bool allowed(HelpGuide g) {
    if (g.officer != isOfficer) return false;
    if (g.roles != null && !g.roles!.contains(role)) return false;
    final n = g.needs;
    if (n == null) return true;
    final parts = n.split(':');
    return parts.length == 1
        ? canAccessModule(perms, parts[0])
        : canPerform(perms, parts[0], parts[1]);
  }

  return _allGuides.where(allowed).toList();
}

/// Roles that count as residents.
const _residents = {'member_resident', 'tenant'};

/// Every guide, grouped by who it is for; [helpGuidesFor] filters this list.
const List<HelpGuide> _allGuides = [
  // =================================================================
  // RESIDENTS AND TENANTS
  // =================================================================

  // ---- Money ----
  HelpGuide(
    question: 'How do I see what I owe?',
    section: 'Money',
    officer: false,
    needs: 'bills',
    steps: [
      TourStep(
        route: '/me/billing',
        anchor: TourAnchorId.page,
        title: 'My Payments',
        body: 'Every bill is listed with its amount, due date and status.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'What the status means',
        body: 'Pending: issued, not paid. Partial: some received. Paid: '
            'settled. Overdue: past due and unpaid. Waived: forgiven by the '
            'association. Cancelled: should not have been issued.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I find out where to send my payment?',
    section: 'Money',
    officer: false,
    needs: 'bills',
    steps: [
      TourStep(
        route: '/me/how-to-pay',
        anchor: TourAnchorId.page,
        title: 'How to Pay',
        body: 'Each account shows its name, number and a QR code to scan with '
            'your banking or e-wallet app. The QR icon on any unpaid bill in '
            'My Payments shows the same thing.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I pay my dues?',
    section: 'Money',
    officer: false,
    needs: 'bills',
    steps: [
      TourStep(
        route: '/me/billing',
        anchor: TourAnchorId.payQr,
        title: '1. See where to send it',
        body: 'Tap the QR icon on the bill you want to settle.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: '2. Pay outside the app',
        body: 'Pay with your own banking or e-wallet app. NeighborSync does '
            'not take the money itself.',
      ),
      TourStep(
        anchor: TourAnchorId.sendProof,
        title: '3. Send proof',
        body: 'Come back and tap Send Proof on that bill. Enter the amount, '
            'choose which account you paid into, and upload a photo of the '
            'receipt. The treasurer is notified.',
      ),
    ],
  ),
  HelpGuide(
    question: 'I sent proof but my bill still says unpaid. Why?',
    section: 'Money',
    officer: false,
    needs: 'bills',
    steps: [
      TourStep(
        route: '/me/billing',
        anchor: TourAnchorId.page,
        title: 'Waiting for the treasurer',
        body: 'The treasurer checks your receipt against the bill before it '
            'counts. The bill updates and you are notified when they do. If '
            'it has been several days, contact the office.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I get a receipt?',
    section: 'Money',
    officer: false,
    needs: 'bills',
    steps: [
      TourStep(
        route: '/me/billing',
        anchor: TourAnchorId.page,
        title: 'The download button',
        body: 'Unpaid, or proof not yet checked: a Statement of Account, '
            'which is not proof of payment. Paid and verified: an Official '
            'Receipt with its own number.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Also here',
        body: 'Each verified payment under Payment History has a receipt '
            'button, and your proof of payment is filed into the Payment '
            'Proof folder in My Files.',
      ),
    ],
  ),

  // ---- Visitors ----
  HelpGuide(
    question: 'How do I get a gate pass for my visitor?',
    section: 'Visitors',
    officer: false,
    needs: 'gate_passes:create',
    steps: [
      TourStep(
        route: '/me/visitors',
        anchor: TourAnchorId.registerVisitor,
        title: 'New Gate Pass',
        body: 'Enter the visitor\'s name and contact number, why they are '
            'coming, the date and how long they will stay. Save and a pass '
            'with a QR code is created.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Do it before they arrive',
        body: 'The pass goes to the guardhouse for approval -- creating it '
            'does not admit anyone by itself.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I send the pass to my visitor?',
    section: 'Visitors',
    officer: false,
    needs: 'gate_passes:create',
    steps: [
      TourStep(
        route: '/me/visitors',
        anchor: TourAnchorId.page,
        title: 'Save it as a picture',
        body: 'Use the save-as-picture button on the pass and send the image '
            'by message. It shows the visitor\'s name, address, date and QR '
            'code. Available on a computer or the installed app; otherwise '
            'show the QR code on screen.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Treat it like a ticket',
        body: 'Anyone holding the image can present it. The guard checks the '
            'name against the person, but send it only to your visitor.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Can I change a pass after I have made it?',
    section: 'Visitors',
    officer: false,
    needs: 'gate_passes:create',
    steps: [
      TourStep(
        route: '/me/visitors',
        anchor: TourAnchorId.page,
        title: 'While it is pending',
        body: 'You can correct the visitor\'s name, contact, purpose and '
            'dates. The guardhouse can change the plate and extend the time '
            'afterwards -- things they only learn when your guest arrives.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I see who has visited me?',
    section: 'Visitors',
    officer: false,
    needs: 'gate_passes',
    steps: [
      TourStep(
        route: '/me/visitors',
        anchor: TourAnchorId.page,
        title: 'Recent visitors',
        body: 'Further down My Visitors. The guardhouse fills it in as people '
            'arrive, and you are notified the moment your visitor is checked '
            'in.',
      ),
    ],
  ),

  HelpGuide(
    question: 'How do I register my car?',
    section: 'Visitors',
    officer: false,
    needs: 'vehicles:create',
    steps: [
      TourStep(
        route: '/me/vehicles',
        anchor: TourAnchorId.page,
        title: 'My Vehicles',
        body: 'Add the plate, type, make, model, colour and year. It is filed '
            'to your address automatically.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'The office issues the sticker',
        body: 'A new vehicle starts as pending. An officer registers it and '
            'issues the sticker -- you cannot set the status or the sticker '
            'yourself. You can correct the details any time.',
      ),
    ],
  ),

  // ---- Complaints ----
  HelpGuide(
    question: 'How do I file a complaint?',
    section: 'Reporting problems',
    officer: false,
    needs: 'complaints:create',
    steps: [
      TourStep(
        route: '/me/complaints',
        anchor: TourAnchorId.fileComplaint,
        title: 'File a Complaint',
        body: 'Your name and address fill in automatically. Choose the '
            'closest category, describe what happened, where and when, and '
            'attach a photo under Evidence if you have one.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Certify and submit',
        body: 'Tick the box confirming the report is true, then submit. Not '
            'sure of the category? The system flags it for the office if a '
            'different one fits better.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Can I edit my complaint after sending it?',
    section: 'Reporting problems',
    officer: false,
    needs: 'complaints',
    steps: [
      TourStep(
        route: '/me/complaints',
        anchor: TourAnchorId.page,
        title: 'While it says Submitted',
        body: 'Open it and tap Edit to change the description, location or '
            'date, or add evidence. Once an officer starts on it, your account '
            'of events becomes the record and Edit is replaced by a note.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I follow what is happening with my complaint?',
    section: 'Reporting problems',
    officer: false,
    needs: 'complaints',
    steps: [
      TourStep(
        route: '/me/complaints',
        anchor: TourAnchorId.page,
        title: 'Open it',
        body: 'The status shows as a track: Submitted, Under Review, In '
            'Progress, Resolved. You can read the category, priority and '
            'resolution the office set, but not change them.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Who can see my evidence photos?',
    section: 'Reporting problems',
    officer: false,
    needs: 'complaints',
    steps: [
      TourStep(
        route: '/me/complaints',
        anchor: TourAnchorId.page,
        title: 'Only the people handling it',
        body: 'You, the officers who handle complaints, and the officer it is '
            'assigned to. Not other residents, and not the person you '
            'complained about.',
      ),
    ],
  ),
  HelpGuide(
    question: 'What is My Violations?',
    section: 'Reporting problems',
    officer: false,
    needs: 'violations',
    steps: [
      TourStep(
        route: '/me/violations',
        anchor: TourAnchorId.page,
        title: 'Cases on your household',
        body: 'Cases the association has filed against your household. You '
            'can read them; only the office can change them. If you '
            'disagree, contact the office -- there is a Contested status for '
            'exactly that.',
      ),
    ],
  ),

  // ---- Permits, moving, bookings ----
  HelpGuide(
    question: 'How do I apply for a permit?',
    section: 'Permits, moving and bookings',
    officer: false,
    needs: 'permits:create',
    // Extra guard: keeps tenants out even if they are ever granted permits:create.
    roles: {'member_resident'},
    steps: [
      TourStep(
        route: '/me/permits',
        anchor: TourAnchorId.page,
        title: 'Start an application',
        body: 'Choose the permit type, give it a title, describe the work and '
            'set the start and end dates. Submit.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'The office fills in the rest',
        body: 'The permit number is issued by the system. The fee, payment '
            'status and review notes are set by the office.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I tell the office I am moving?',
    section: 'Permits, moving and bookings',
    officer: false,
    needs: 'move_requests:create',
    steps: [
      TourStep(
        route: '/me/move-requests',
        anchor: TourAnchorId.page,
        title: 'New request',
        body: 'Choose move in or move out, pick the date and add notes. The '
            'guardhouse then expects the truck. The date must be in the '
            'future -- for a move that already happened, contact the office.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I book the function hall or the court?',
    section: 'Permits, moving and bookings',
    officer: false,
    roles: _residents,
    steps: [
      TourStep(
        route: '/me/reservations',
        anchor: TourAnchorId.page,
        title: 'Choose the facility and time',
        body: 'Names starting with "Community" are shared with the whole '
            'subdivision; the rest belong to your phase. Pick a date and '
            'time and submit -- it stays pending until an officer approves.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'No double-booking',
        body: 'A slot someone already holds, even a pending one, is refused '
            'straight away. You can see when a facility is busy, never who '
            'booked it.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I add the people living with me?',
    section: 'Permits, moving and bookings',
    officer: false,
    needs: 'household_members:create',
    steps: [
      TourStep(
        route: '/me/household',
        anchor: TourAnchorId.page,
        title: 'My Household',
        body: 'Add each member with their name and relationship. You can '
            'edit your own household\'s entries.',
      ),
    ],
  ),

  // ---- Community ----
  HelpGuide(
    question: 'When is my rubbish collected?',
    section: 'Community',
    officer: false,
    roles: _residents,
    steps: [
      TourStep(
        route: '/me/waste-schedule',
        anchor: TourAnchorId.page,
        title: 'Waste Schedule',
        body: 'The chip at the top says which phase you are seeing, and the '
            'calendar shades your collection days in the waste type\'s '
            'colour. "Show all phases" shows the rest. A wrong phase means '
            'your address on file is wrong -- contact the office.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Where do I find announcements and events?',
    section: 'Community',
    officer: false,
    needs: 'announcements',
    steps: [
      TourStep(
        route: '/me/announcements',
        anchor: TourAnchorId.nav,
        title: 'Announcements and Events',
        body: 'Both are in the menu. You see notices for your own phase plus '
            'anything posted to the whole subdivision.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Where is my address on the map?',
    section: 'Community',
    officer: false,
    roles: _residents,
    steps: [
      TourStep(
        route: '/me/community',
        anchor: TourAnchorId.page,
        title: 'Community Map',
        body: 'Your own lot is marked, with the address written underneath. '
            'Other households are not marked -- where your neighbours live '
            'is not shown to other residents.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Where are the community rules?',
    section: 'Community',
    officer: false,
    steps: [
      TourStep(
        route: '/me/rules',
        anchor: TourAnchorId.page,
        title: 'Community Rules',
        body: 'The association\'s rules. Files the office has shared with '
            'residents are under Documents.',
      ),
    ],
  ),

  // ---- Account ----
  HelpGuide(
    question: 'What is in My Files?',
    section: 'Your account',
    officer: false,
    roles: _residents,
    steps: [
      TourStep(
        route: '/me/files',
        anchor: TourAnchorId.page,
        title: 'Your folders',
        body: 'Permit, Government ID, Contract, Receipt, Insurance, Payment '
            'Proof and Other. Upload a file, open a folder, or move a file '
            'between folders. When the office files something for you, it '
            'shows who added it.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I change my password?',
    section: 'Your account',
    officer: false,
    steps: [
      TourStep(
        route: '/me/profile',
        anchor: TourAnchorId.page,
        title: 'Profile, then Change Password',
        body: 'You type your current password first -- that stops someone who '
            'picks up your unlocked phone from locking you out.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I sign out a phone I no longer have?',
    section: 'Your account',
    officer: false,
    steps: [
      TourStep(
        route: '/me/profile',
        anchor: TourAnchorId.page,
        title: 'Profile, then Sign out other devices',
        body: 'Ends every session except this one, within about an hour. '
            'Recent Sign-ins is a list, not a switch -- removing a line does '
            'not sign that device out.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I update my phone number or photo?',
    section: 'Your account',
    officer: false,
    steps: [
      TourStep(
        route: '/me/profile',
        anchor: TourAnchorId.page,
        title: 'On your profile',
        body: 'Edit your phone number and photo here. Once you are approved '
            'your address is set by the office -- contact them if it is '
            'wrong.',
      ),
    ],
  ),

  // =================================================================
  // EVERY OFFICER
  // =================================================================
  HelpGuide(
    question: 'How do I change my password?',
    section: 'Your account',
    officer: true,
    steps: [
      TourStep(
        route: '/admin/profile',
        anchor: TourAnchorId.page,
        title: 'Profile, then Change Password',
        body: 'You enter your current password first, so someone who finds '
            'your screen unlocked cannot lock you out.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I sign out a device I no longer use?',
    section: 'Your account',
    officer: true,
    steps: [
      TourStep(
        route: '/admin/profile',
        anchor: TourAnchorId.page,
        title: 'Profile, then Sign out other devices',
        body: 'Ends every session except this one, within about an hour. '
            'Recent Sign-ins is a record, not a switch.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Why can I not find a resident I know exists?',
    section: 'Your phase',
    officer: true,
    steps: [
      TourStep(
        anchor: TourAnchorId.phase,
        title: 'They are in another phase',
        body: 'Every screen is already filtered to your own association. '
            'Phases are separate associations with separate officers and '
            'dues. Divisions like 4A and 4B are all yours -- you cover the '
            'whole number.',
      ),
    ],
  ),
  HelpGuide(
    question: 'A resident moved phase and their old bills stayed. Is that a bug?',
    section: 'Your phase',
    officer: true,
    steps: [
      TourStep(
        anchor: TourAnchorId.phase,
        title: 'No, it is the rule',
        body: 'A record belongs to the phase that created it; a person '
            'belongs to the phase they live in now. Unpaid dues stay the old '
            'association\'s receivable. The household still sees its own '
            'history.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I search for a person or a bill?',
    section: 'Finding things',
    officer: true,
    steps: [
      TourStep(
        anchor: TourAnchorId.search,
        title: 'The search box beside the bell',
        body: 'Covers people, bills, complaints, permits and more at once. '
            'Individual screens use filters rather than their own search '
            'boxes.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Why is a field greyed out?',
    section: 'Finding things',
    officer: true,
    steps: [
      TourStep(
        title: 'It belongs to someone else',
        body: 'Records have two halves: what the resident wrote, and what '
            'the office decides. Neither side can overwrite the other, and '
            'the reason is shown beside the field.',
      ),
    ],
  ),

  // =================================================================
  // PRESIDENT AND SECRETARY (and the administrator)
  // =================================================================
  HelpGuide(
    question: 'How do I approve a new member?',
    section: 'Members',
    officer: true,
    needs: 'users:approve',
    steps: [
      TourStep(
        route: '/admin/approvals',
        anchor: TourAnchorId.pendingTab,
        title: 'Pending Approvals',
        body: 'Each card shows the claimed address and the proof-of-ownership '
            'chip -- green links to the file, amber means none uploaded.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Check the address colour',
        body: 'Green: the lot is free. Red: someone is on record there. '
            'Amber: nothing claimed. Correct a wrong lot from the dropdown '
            'instead of rejecting them.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Role, then Approve',
        body: 'Set the role, and for an officer the phase too. Approving '
            'writes the lot onto their account -- their billing address, '
            'waste day and ability to register visitors.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I change someone\'s role or suspend them?',
    section: 'Members',
    officer: true,
    needs: 'users:update',
    steps: [
      TourStep(
        route: '/admin/accounts',
        anchor: TourAnchorId.page,
        title: 'Open the row and edit',
        body: 'Change the role or status in the edit dialog. Both changes are '
            'recorded on the audit trail as critical.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I see everything on file for one household?',
    section: 'Members',
    officer: true,
    needs: 'accounts',
    steps: [
      TourStep(
        route: '/admin/residents',
        anchor: TourAnchorId.page,
        title: 'Click their name',
        body: 'Click a name in any list, or search for it. The person page '
            'gathers their bills, payments, complaints, permits, vehicles, '
            'passes, moves, household and reservations. Opening it is '
            'recorded on the audit trail.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I send someone a password reset?',
    section: 'Members',
    officer: true,
    needs: 'users:update',
    steps: [
      TourStep(
        route: '/admin/accounts',
        anchor: TourAnchorId.page,
        title: 'The reset action on their row',
        body: 'They get an email and choose their own password -- you never '
            'see it. The dialog names the exact address before sending, so '
            'check it.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I import a list of homeowners?',
    section: 'Members',
    officer: true,
    needs: 'users:create',
    steps: [
      TourStep(
        route: '/admin/accounts',
        anchor: TourAnchorId.page,
        title: 'Import Roster',
        body: 'Download the template, fill it in (name and email required), '
            'and upload -- CSV or Excel. Every row is previewed with a '
            'verdict before anything is written.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Rows are records, not logins',
        body: 'When that homeowner registers with the same email, they are '
            'linked to their row and keep the address. Refused: missing or '
            'bad email, duplicates, unknown or taken lots, officer roles.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I remove an account?',
    section: 'Members',
    officer: true,
    needs: 'users:delete',
    steps: [
      TourStep(
        route: '/admin/accounts',
        anchor: TourAnchorId.page,
        title: 'Delete, then read the preview',
        body: 'The dialog lists what will be erased, kept and detached. '
            'Retire stops the sign-in and keeps their bills and history -- '
            'almost always the right choice.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Hard delete',
        body: 'Only for a duplicate or test account with nothing worth '
            'keeping. You type the person\'s name to confirm.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I file a document into one household\'s folder?',
    section: 'Members',
    officer: true,
    needs: 'documents:update',
    steps: [
      TourStep(
        route: '/admin/residents',
        anchor: TourAnchorId.page,
        title: 'Files, then Add a file',
        body: 'Use Files on their row and Add a file. It appears in their My '
            'Files, and the record shows you filed it -- they are not '
            'credited with an upload they never made.',
      ),
    ],
  ),

  // ---- Complaints and cases ----
  HelpGuide(
    question: 'How do I work a complaint?',
    section: 'Complaints and cases',
    officer: true,
    needs: 'complaints:update',
    steps: [
      TourStep(
        route: '/admin/community-concern',
        anchor: TourAnchorId.page,
        title: 'Open it, set category and priority',
        body: 'Then assign it. The list only offers officers whose job covers '
            'that category, and the officer you choose is notified.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Move it along the track',
        body: 'Submitted, Under Review, In Progress, Resolved. Resolved or '
            'Dismissed needs a resolution note -- the system refuses an empty '
            'one. Escalating does not.',
      ),
    ],
  ),
  HelpGuide(
    question: 'What is the amber chip next to a category?',
    section: 'Complaints and cases',
    officer: true,
    needs: 'complaints',
    steps: [
      TourStep(
        route: '/admin/community-concern',
        anchor: TourAnchorId.page,
        title: 'The system disagrees',
        body: 'It read the complaint and thinks a different category fits '
            'better (shown only above 55% confidence). Tap it to refile. '
            'Refiling does not reassign -- that is left to you.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Why can I not edit the resident\'s description?',
    section: 'Complaints and cases',
    officer: true,
    needs: 'complaints',
    steps: [
      TourStep(
        route: '/admin/community-concern',
        anchor: TourAnchorId.page,
        title: 'Their words are theirs',
        body: 'Subject, description, location, date and evidence belong to '
            'the resident, while it is Submitted. You own category, '
            'priority, status, assignment and resolution.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I issue a violation?',
    section: 'Complaints and cases',
    officer: true,
    needs: 'violations:create',
    steps: [
      TourStep(
        route: '/admin/community-concern',
        anchor: TourAnchorId.page,
        title: 'The Cases tab',
        body: 'Choosing the person fills in their address. Choosing an '
            'address fills in the person only if it is still blank, so '
            'correcting an address never changes who the case names.',
      ),
    ],
  ),

  // ---- Announcements, events, waste ----
  HelpGuide(
    question: 'How do I post an announcement?',
    section: 'Community',
    officer: true,
    needs: 'announcements:create',
    steps: [
      TourStep(
        route: '/admin/announcements',
        anchor: TourAnchorId.page,
        title: 'New Announcement',
        body: 'Set the category, priority, audience and publish date. It goes '
            'to your own phase; the HOA president, the secretary and the '
            'system administrator can tick All phases to send it to everyone.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I set the rubbish collection days?',
    section: 'Community',
    officer: true,
    needs: 'waste_schedules:update',
    steps: [
      TourStep(
        route: '/admin/waste-schedule',
        anchor: TourAnchorId.page,
        title: 'Tick what is collected each day',
        body: 'Press Edit Schedule. Tick one, two or all three waste types for '
            'a day and tap each time to set it on the clock (AM or PM). A day '
            'with nothing ticked is a rest day.',
      ),
    ],
  ),

  // ---- Requests ----
  HelpGuide(
    question: 'How do I approve a permit?',
    section: 'Requests',
    officer: true,
    needs: 'permits:update',
    steps: [
      TourStep(
        route: '/admin/permits',
        anchor: TourAnchorId.page,
        title: 'Open the application',
        body: 'Set the fee and payment status, add review notes, then move '
            'the status: Submitted, Under Review, Approved. Rejected, '
            'Cancelled and Expired are off-ramps.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I file a permit for a resident at the desk?',
    section: 'Requests',
    officer: true,
    needs: 'permits:update',
    steps: [
      TourStep(
        route: '/admin/permits',
        anchor: TourAnchorId.page,
        title: 'New permit',
        body: 'Choose the applicant; the lot fills in from their record. The '
            'permit number is issued by the system.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I handle a move in or out?',
    section: 'Requests',
    officer: true,
    needs: 'move_requests:update',
    steps: [
      TourStep(
        route: '/admin/move-requests',
        anchor: TourAnchorId.page,
        title: 'Move In/Out',
        body: 'Move the status along Pending, Approved, Scheduled, Completed. '
            'Rejected is off the track.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I take a booking at the desk?',
    section: 'Requests',
    officer: true,
    needs: 'reservations:create',
    steps: [
      TourStep(
        route: '/admin/reservations',
        anchor: TourAnchorId.page,
        title: 'Book for a Resident',
        body: 'A desk booking saves as approved immediately. A slot that is '
            'already taken is refused, in plain English.',
      ),
    ],
  ),

  // =================================================================
  // FINANCE (treasurer, president, secretary, administrator)
  // =================================================================
  HelpGuide(
    question: 'How do I generate a bill?',
    section: 'Finance',
    officer: true,
    needs: 'bills:create',
    steps: [
      TourStep(
        route: '/admin/finance',
        anchor: TourAnchorId.page,
        title: 'Billing, then new',
        body: 'Choose the resident; a card shows their address and how many '
            'unpaid bills they already have, and the lot fills in. Penalty, '
            'discount and notes are behind a link.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'You do not choose the status',
        body: 'It moves itself as payments are verified, and overdue bills '
            'are marked overnight.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I cancel or waive a bill?',
    section: 'Finance',
    officer: true,
    needs: 'bills:update',
    steps: [
      TourStep(
        route: '/admin/finance',
        anchor: TourAnchorId.page,
        title: 'Open the bill',
        body: 'Use Cancel or Waive; both need a reason. Cancelled: it should '
            'never have been issued. Waived: the charge was real and has been '
            'forgiven. Neither appears on a paid bill, and Reopen undoes it.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I verify proof of payment?',
    section: 'Finance',
    officer: true,
    needs: 'payments:update',
    steps: [
      TourStep(
        route: '/admin/finance?tab=payments',
        anchor: TourAnchorId.paymentsTab,
        title: 'The Payments tab',
        body: 'Waiting submissions sit in an amber queue above the table.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Verify or reject',
        body: 'Verify opens the receipt beside the bill total, what is paid '
            'and the balance. Approve, or reject with a reason. You can also '
            'do this from the bill itself.',
      ),
    ],
  ),
  HelpGuide(
    question: 'I recorded a payment but the bill still says Pending.',
    section: 'Finance',
    officer: true,
    needs: 'payments:update',
    steps: [
      TourStep(
        route: '/admin/finance?tab=payments',
        anchor: TourAnchorId.paymentsTab,
        title: 'Only a verified payment counts',
        body: 'A payment left at Pending changes nothing. Verify it and the '
            'bill moves.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Why was my payment refused?',
    section: 'Finance',
    officer: true,
    needs: 'payments:update',
    steps: [
      TourStep(
        route: '/admin/finance?tab=payments',
        anchor: TourAnchorId.page,
        title: 'The bill is already settled',
        body: 'A verified payment on a bill with nothing left to pay is '
            'refused, and the message names the amounts. Overpaying a bill '
            'that is still open is allowed.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do residents find out where to pay?',
    section: 'Finance',
    officer: true,
    needs: 'payments:update',
    steps: [
      TourStep(
        route: '/admin/finance?tab=channels',
        anchor: TourAnchorId.channelsTab,
        title: 'Payment Channels',
        body: 'Add each account with its name, number and QR image. Residents '
            'see them on How to Pay and on each unpaid bill.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Scope and the QR image',
        body: 'Scope defaults to your phase -- leave it shared only for an '
            'account that collects for every phase. Upload the original QR '
            'image; a re-saved one can stop scanning.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I add a budget category or record an expense?',
    section: 'Finance',
    officer: true,
    needs: 'budget:create',
    steps: [
      TourStep(
        route: '/admin/finance?tab=budget',
        anchor: TourAnchorId.page,
        title: 'Budget',
        body: 'Add a category with its year and allocation -- a card shows '
            'the year\'s running total. Record an expense against a category; '
            'the date is yours to set, so a late receipt is filed on the '
            'right day.',
      ),
    ],
  ),

  // =================================================================
  // THE GATE (security, president, secretary, administrator)
  // =================================================================
  HelpGuide(
    question: 'How do I check a gate pass?',
    section: 'The gate',
    officer: true,
    needs: 'gate_passes:read_all',
    steps: [
      TourStep(
        route: '/admin/gate_passes',
        anchor: TourAnchorId.scanPass,
        title: 'Scan Pass',
        body: 'Point the camera at the visitor\'s QR code. You get their '
            'name, the address being visited, the host\'s phone number and a '
            'verdict.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Read the verdict, not the badge',
        body: 'A pass can still say Pending months after it expired; the '
            'scanner checks the real dates. Scanning writes nothing -- act '
            'through Review on the list. Another phase\'s pass reads "No '
            'pass found".',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I issue a pass for a resident at the desk?',
    section: 'The gate',
    officer: true,
    needs: 'gate_passes:update',
    steps: [
      TourStep(
        route: '/admin/gate_passes',
        anchor: TourAnchorId.page,
        title: 'New pass',
        body: 'Choose the host; a card shows their address and phone. Fill in '
            'the visitor and the validity.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Can I change a pass a resident created?',
    section: 'The gate',
    officer: true,
    needs: 'gate_passes:update',
    steps: [
      TourStep(
        route: '/admin/gate_passes',
        anchor: TourAnchorId.page,
        title: 'The plate and the end time',
        body: 'Both are things you learn at the gate. The visitor\'s name, '
            'contact, purpose and start time stay the resident\'s.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I log a visitor in and out?',
    section: 'The gate',
    officer: true,
    needs: 'visitor_logs:create',
    steps: [
      TourStep(
        route: '/admin/visitors',
        anchor: TourAnchorId.page,
        title: 'New entry',
        body: 'Choose the purpose and the host -- the picker shows name and '
            'phone together. Time in defaults to now. The resident is '
            'notified as soon as you save.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Closing it',
        body: 'Open the entry and record the time out. Until then the visitor '
            'counts as inside.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How does overstaying work?',
    section: 'The gate',
    officer: true,
    needs: 'visitor_logs',
    steps: [
      TourStep(
        route: '/admin/visitors',
        anchor: TourAnchorId.page,
        title: 'The purpose sets the clock',
        body: 'A delivery gets 30 minutes, a contractor 8 hours, a guest 12. '
            'Anyone inside past that is flagged. You never enter a duration.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I log an incident?',
    section: 'The gate',
    officer: true,
    needs: 'security_incidents:create',
    steps: [
      TourStep(
        route: '/admin/security',
        anchor: TourAnchorId.page,
        title: 'New incident',
        body: 'Enter the type, title, description, location and date. '
            'Severity defaults to medium and the reference number is issued '
            'for you.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Your account of events is yours',
        body: 'While it is Open or Investigating, nobody else can rewrite '
            'what you wrote -- not even the President. Others can change '
            'severity, status, assignment and resolution.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I close an incident?',
    section: 'The gate',
    officer: true,
    needs: 'security_incidents:update',
    steps: [
      TourStep(
        route: '/admin/security',
        anchor: TourAnchorId.page,
        title: 'Resolved or Closed, with a resolution',
        body: 'Write what was done. Assigning an incident moves it to '
            'Investigating on its own. Escalated is an off-ramp and needs no '
            'resolution.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I handle a complaint assigned to me?',
    section: 'The gate',
    officer: true,
    roles: {'security', 'treasurer', 'secretary', 'hoa_president', 'super_admin'},
    steps: [
      TourStep(
        route: '/admin/assigned',
        anchor: TourAnchorId.page,
        title: 'Assigned to Me',
        body: 'Set the status and write the resolution yourself -- you do not '
            'need to go through the Secretary.',
      ),
    ],
  ),

  // =================================================================
  // OVERSIGHT
  // =================================================================
  HelpGuide(
    question: 'How do I read the audit trail?',
    section: 'Oversight',
    officer: true,
    needs: 'audit_logs',
    steps: [
      TourStep(
        route: '/admin/audit_logs',
        anchor: TourAnchorId.page,
        title: 'Every change, automatically',
        body: 'Who, when, which record (by reference number) and only the '
            'fields that moved, before and after. Filter by module or action.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Severity and "System"',
        body: 'Critical: roles, permissions, settings, account role or '
            'status. Warning: deletions and money. "System" is a scheduled '
            'job. Codes and file paths show as [redacted].',
      ),
    ],
  ),
  HelpGuide(
    question: 'Are reads recorded, or only changes?',
    section: 'Oversight',
    officer: true,
    needs: 'audit_logs',
    steps: [
      TourStep(
        route: '/admin/audit_logs',
        anchor: TourAnchorId.page,
        title: 'Sensitive reads are',
        body: 'Opening a household\'s file, downloading a backup, exporting a '
            'report, opening a private file, scanning a pass, and every '
            'sign-in and password change. Ordinary page views are not.',
      ),
    ],
  ),
  HelpGuide(
    question: 'Can anyone edit the audit trail?',
    section: 'Oversight',
    officer: true,
    needs: 'audit_logs',
    steps: [
      TourStep(
        route: '/admin/audit_logs',
        anchor: TourAnchorId.page,
        title: 'No',
        body: 'Nothing in the app can write to it -- including the '
            'administrator. The Secretary and Treasurer cannot read it, so '
            'it is not reviewed by the people it most often describes.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I generate a report?',
    section: 'Oversight',
    officer: true,
    needs: 'audit_logs',
    steps: [
      TourStep(
        route: '/admin/reports',
        anchor: TourAnchorId.page,
        title: 'Reports',
        body: 'Financial, community and occupancy summaries with charts. '
            'Exporting one is recorded on the audit trail.',
      ),
    ],
  ),

  // =================================================================
  // THE SYSTEM (administrator, and the office where noted)
  // =================================================================
  HelpGuide(
    question: 'How do I create a phase?',
    section: 'Phases',
    officer: true,
    roles: {'super_admin'},
    steps: [
      TourStep(
        route: '/admin/system_settings',
        anchor: TourAnchorId.phasesTab,
        title: 'Settings, Phases tab',
        body: 'Only your account sees this tab.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Number only',
        body: 'Add a phase and enter just the number, e.g. 4. If it is '
            'divided, say how many parts and 4A, 4B are generated for you -- '
            'which stops "4" and "4A" existing together.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I divide, retire or delete a phase?',
    section: 'Phases',
    officer: true,
    roles: {'super_admin'},
    steps: [
      TourStep(
        route: '/admin/system_settings',
        anchor: TourAnchorId.phasesTab,
        title: 'On the phase card',
        body: 'Divide renames 4 to 4A and carries every lot, account and '
            'record with it.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'The three-dot menu',
        body: 'Deactivate hides it but keeps everything -- right for a phase '
            'with history. Delete only works on an empty phase, removes all '
            'its divisions, and names what is in the way if refused.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I upload a phase\'s map?',
    section: 'Phases',
    officer: true,
    roles: {'super_admin'},
    steps: [
      TourStep(
        route: '/admin/system_settings',
        anchor: TourAnchorId.phasesTab,
        title: 'Three-dot menu, then Community map',
        body: 'Upload that phase\'s survey plan. Replacing a map strands the '
            'existing pins -- re-place them with Adjust Pins on the '
            'Community Map.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I move a household to another phase?',
    section: 'Phases',
    officer: true,
    roles: {'super_admin'},
    steps: [
      TourStep(
        anchor: TourAnchorId.phase,
        title: 'First: All phases',
        body: 'Switch the phase selector to All phases, or both pickers list '
            'only one phase and the move looks impossible.',
      ),
      TourStep(
        route: '/admin/system_settings',
        anchor: TourAnchorId.phasesTab,
        title: 'Move Household',
        body: 'The button on the Phases tab. Pick the resident or tenant and '
            'their new address, then confirm.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'What moves',
        body: 'The person moves; their records stay with the old phase, whose '
            'unpaid dues remain its receivable. Officers are not moved this '
            'way -- set their phase on the approvals screen.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I change the logo or colours?',
    section: 'Branding and content',
    officer: true,
    needs: 'system_settings:update',
    steps: [
      TourStep(
        route: '/admin/branding',
        anchor: TourAnchorId.page,
        title: 'CMS, Branding tab',
        body: 'Upload the logo and pick the colours, then save. Every '
            'signed-in device and the public page pick it up within seconds. '
            'The installed phone-app icon does not change.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I set the office contact details?',
    section: 'Branding and content',
    officer: true,
    needs: 'system_settings:update',
    steps: [
      TourStep(
        route: '/admin/branding',
        anchor: TourAnchorId.page,
        title: 'CMS, Home Page tab',
        body: 'Use the office-hours picker rather than typing the hours. '
            'These details show on the public home page.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I edit the Terms of Use or Privacy Notice?',
    section: 'Branding and content',
    officer: true,
    needs: 'system_settings:update',
    steps: [
      TourStep(
        route: '/admin/branding',
        anchor: TourAnchorId.page,
        title: 'CMS, Legal tab',
        body: 'Saving publishes a new dated version. It does not rewrite past '
            'consent -- each account keeps the version it agreed to.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I add a bookable facility?',
    section: 'Branding and content',
    officer: true,
    needs: 'reservations:update',
    steps: [
      TourStep(
        route: '/admin/branding',
        anchor: TourAnchorId.page,
        title: 'CMS, Facilities tab',
        body: 'Shared means any phase can book it; a phase means only that '
            'association. Name shared ones with a "Community" prefix so '
            'residents can tell them apart.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I add a permit or violation type?',
    section: 'Branding and content',
    officer: true,
    needs: 'permits:update',
    steps: [
      TourStep(
        route: '/admin/branding',
        anchor: TourAnchorId.page,
        title: 'CMS, Categories tab',
        body: 'To stop offering a type, switch it off rather than deleting '
            'it -- existing records keep pointing at it. Delete only works on '
            'a type nothing uses.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I take or restore a backup?',
    section: 'Backups',
    officer: true,
    needs: 'backup',
    steps: [
      TourStep(
        route: '/admin/backup',
        anchor: TourAnchorId.page,
        title: 'Create Backup',
        body: 'Full captures every table; incremental captures only what '
            'changed since a date you choose. The file holds everyone\'s '
            'details with no protections -- treat it like the filing cabinet '
            'keys.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Restore',
        body: 'Overwrites current data with the snapshot and writes one audit '
            'entry per row. Take a fresh backup immediately before '
            'restoring.',
      ),
    ],
  ),
  HelpGuide(
    question: 'How do I place lot pins or edit a block?',
    section: 'The community map',
    officer: true,
    needs: 'lots:update',
    steps: [
      TourStep(
        route: '/admin/community',
        anchor: TourAnchorId.page,
        title: 'Adjust Pins',
        body: 'Drag each lot onto the survey plan. Viewing several phases? '
            'Pin one phase at a time -- each has its own plan.',
      ),
      TourStep(
        anchor: TourAnchorId.page,
        title: 'Blocks',
        body: 'The pencil on a block card sets its name, phase and '
            'description. A block with no phase leaves its households '
            'unscoped, so fix any "No phase set" chip.',
      ),
    ],
  ),
];
