import 'form_helpers.dart' show kPhoneMaxLength, kReferenceMaxLength;
import 'field_rules.dart';
import '../services/supabase_service.dart';
import 'concern_routing.dart';
import 'module_config.dart';
import 'roles.dart';
import '../widgets/form_context_cards.dart';

/// Officer roles eligible to take a complaint, based on its category.
/// Pulled out as a top-level function because FieldConfig entries are const.
List<String> _assigneeRolesForCategory(Map<String, dynamic> values) =>
    rolesForConcernCategory(values['category']?.toString());

/// Officer roles eligible to take a security incident: the guards plus
/// admins. The incident type makes no difference, so the set is fixed.
List<String> _incidentAssigneeRoles(Map<String, dynamic> values) =>
    <String>['security', ...concernAdminRoles];

/// Columns for a plain person picker: id and name.
const _users = ['id', 'first_name', 'last_name'];

/// Person picker columns plus phone and lot: the list reads "Name — phone",
/// and choosing someone fills in their address.
const _usersWithPhoneAndLot = [
  'id', 'first_name', 'last_name', 'phone', 'lot_id'
];

/// "Juan Dela Cruz — 0917 123 4567". Shows whichever half exists, or a dash
/// when neither does.
String residentContactLabel(Map<String, dynamic> r) {
  final name = [r['first_name'], r['last_name']]
      .map((v) => (v ?? '').toString().trim())
      .where((v) => v.isNotEmpty)
      .join(' ');
  final phone = (r['phone'] ?? '').toString().trim();
  if (name.isEmpty) return phone.isEmpty ? '—' : phone;
  return phone.isEmpty ? name : '$name — $phone';
}

/// Person picker columns plus lot_id, so choosing someone can fill in "Lot".
/// Needs a label builder: the default label would print lot_id raw.
const _usersWithLot = ['id', 'first_name', 'last_name', 'lot_id'];

/// Bill picker columns. Carries user_id so choosing a bill fills "Paid By".
const _billsWithPayer = ['id', 'bill_number', 'description', 'user_id'];

/// Lot picker columns. Always pair a lot picker with a block and a label
/// builder; without them it shows a bare number such as "18".
const _lotsWithBlock = ['id', 'lot_number', 'blocks(block_name)'];

/// Lot picker columns plus who is registered there, so choosing an address
/// can fill in the person.
// Named FK: users has two foreign keys to lots, so a bare `users(...)` embed
// is ambiguous and PostgREST rejects the whole query.
const _lotsWithBlockAndOwner = [
  'id', 'lot_number', 'blocks(block_name)', 'users!users_lot_id_fkey(id)'
];

/// The one person registered to a picked lot, or null when there are none
/// or several, so the app never guesses and a person chooses.
dynamic _soleOccupantId(Map<String, dynamic> lot) {
  final people = lot['users'];
  if (people is List && people.length == 1) {
    final only = people.first;
    if (only is Map) return only['id'];
  }
  return null;
}

/// True when this status closes a case, which requires a resolution note.
bool _closingViolation(Map<String, dynamic> v) =>
    const ['resolved', 'dismissed'].contains((v['status'] ?? '').toString());
String _reportedStatus() => 'reported';

/// Bill picker label: the number, then the description if there is one.
String _billLabel(Map<String, dynamic> row) {
  final desc = (row['description'] ?? '').toString().trim();
  final number = (row['bill_number'] ?? '#${row['id']}').toString();
  return desc.isEmpty ? number : '$number · $desc';
}

/// Person picker label: first and last name.
String _billedToLabel(Map<String, dynamic> row) =>
    [row['first_name'], row['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');

/// Lot picker label: "Block A · Lot 12".
String _lotWithBlockLabel(Map<String, dynamic> row) {
  final block = (row['blocks'] as Map<String, dynamic>?)?['block_name'];
  return 'Block ${block ?? '—'} · Lot ${row['lot_number'] ?? ''}';
}

dynamic _currentUserId() => SupabaseService.cachedUserRowId;

/// The signed-in person for a resident filing their own request. Null for
/// an officer, who must choose who the request is for.
dynamic _currentUserIdIfResident() =>
    officerRoleNames.contains(SupabaseService.cachedRole)
        ? null
        : SupabaseService.cachedUserRowId;

/// True once "Billed To" has filled the lot. False for a resident with no
/// lot on record, so the required picker comes back.
bool _lotAlreadyKnown(Map<String, dynamic> v) => v['lot_id'] != null;

/// True once the chosen bill has filled in who paid.
bool _payerAlreadyKnown(Map<String, dynamic> v) => v['user_id'] != null;

/// Default payment method on the officer form.
String _cashMethod() => 'cash';

/// True when this status closes a complaint, which requires a resolution
/// note. Must match `require_resolution_to_close()` in the database.
bool _closingComplaint(Map<String, dynamic> v) =>
    const ['resolved', 'dismissed'].contains((v['status'] ?? '').toString());

/// Same for an incident, which closes on different words.
bool _closingIncident(Map<String, dynamic> v) =>
    const ['resolved', 'closed'].contains((v['status'] ?? '').toString());

/// Default Severity and Priority, so those dropdowns are not blank on a new
/// form. Category and Type stay blank: they are required and have no safe
/// default.
String _mediumSeverity() => 'medium';
String _submittedStatus() => 'submitted';
String _unpaidPayment() => 'unpaid';

/// Default for a pass's Valid From and a visitor's Time In: right now.
dynamic _todayStart() => DateTime.now();

String _openStatus() => 'open';

String _generalCategory() => 'general';
String _normalPriority() => 'normal';
String _allAudience() => 'all';

/// Default purpose category for a new gate entry.
dynamic _defaultPurposeType() => 'visitor';

dynamic _currentYear() => DateTime.now().year;
dynamic _today() => DateTime.now();
// Starting status for new records.
dynamic _publishedStatus() => 'published';
dynamic _upcomingStatus() => 'upcoming';
dynamic _pendingStatus() => 'pending';

/// The joined resident's "First Last" name (see
/// householdMembers.selectOverride), or null when there is none.
dynamic _joinedResidentName(Map<String, dynamic> row) {
  final r = row['resident'] as Map<String, dynamic>?;
  if (r == null) return null;
  final name = [r['first_name'], r['last_name']]
      .where((s) => s != null && s.toString().isNotEmpty)
      .join(' ');
  return name.isEmpty ? null : name;
}

/// Groups household members by their owner. Rows with no joined resident
/// share one named group.
String _householdGroupKey(Map<String, dynamic> row) =>
    (_joinedResidentName(row) as String?) ?? 'No owner on record';

/// Group header text: "Karla Espiritu  ·  3 members".
String _householdGroupHeader(String key, List<Map<String, dynamic>> rows) =>
    '$key  ·  ${rows.length} ${rows.length == 1 ? 'member' : 'members'}';

/// Bills raised by officers. The database keeps each bill's status up to date.
const billing = ModuleConfig(
  key: 'billing',
  table: 'bills',
  label: 'Billing',
  itemNoun: 'Bill',
  titleField: 'description',
  subtitleField: 'bill_number',
  statusField: 'status',
  searchField: 'description',
  permissionModuleOverride: 'bills',
  // Card under the resident picker: their address and what they already owe.
  contextAfterField: 'user_id',
  contextBuilder: billingResidentCard,
  fields: [
    // Issued by a database trigger, so it stays off the form.
    FieldConfig(key: 'bill_number', label: 'Bill Number', type: FieldType.text, editable: false),
    // Lists billable people only. Picking someone fills "Lot" from their record.
    FieldConfig(key: 'user_id', lockOnEdit: true, label: 'Billed To', type: FieldType.reference, required: true, refTable: 'users', refSelectColumns: _usersWithLot, refRoleFilter: billableRoleNames, refLabelBuilder: _billedToLabel, showInList: false, autoFillTargetKey: 'lot_id', autoFillSourceColumn: 'lot_id'),
    // Hidden once filled from the resident; comes back if no lot was found,
    // because a required field must not fail validation while invisible.
    FieldConfig(key: 'lot_id', lockOnEdit: true, label: 'Lot', type: FieldType.reference, required: true, refTable: 'lots', refSelectColumns: _lotsWithBlock, refLabelBuilder: _lotWithBlockLabel, showInList: false, hiddenWhen: _lotAlreadyKnown),
    FieldConfig(key: 'description', label: 'Description', type: FieldType.text, required: true),
    FieldConfig(key: 'amount', label: 'Amount', type: FieldType.decimal, required: true, currency: true, halfWidth: true),
    // futureOnly: a bill can't be created already overdue.
    FieldConfig(key: 'due_date', label: 'Due Date', type: FieldType.date, required: true, futureOnly: true, halfWidth: true),
    FieldConfig(key: 'penalty_amount', label: 'Penalty', type: FieldType.decimal, showInList: false, currency: true, halfWidth: true, advanced: true),
    FieldConfig(key: 'discount_amount', label: 'Discount', type: FieldType.decimal, showInList: false, currency: true, halfWidth: true, advanced: true),
    FieldConfig(key: 'notes', label: 'Notes', type: FieldType.longText, showInList: false, advanced: true),
    // Off the form: the database sets this from payments and the nightly
    // sweep. Cancel and waive are actions on the bill detail screen.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['pending', 'partial', 'paid', 'overdue', 'cancelled', 'waived'], editable: false, defaultValue: _pendingStatus),
    FieldConfig(key: 'created_by', label: 'Created By', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId),
  ],
);

/// Payments recorded against bills.
const payments = ModuleConfig(
  key: 'payments',
  table: 'payments',
  label: 'Payments',
  itemNoun: 'Payment',
  titleField: 'or_number',
  subtitleField: 'payment_method',
  statusField: 'status',
  searchField: 'or_number',
  // Card under the bill picker: the bill's real remaining balance.
  contextAfterField: 'bill_id',
  contextBuilder: paymentBillCard,
  fields: [
    FieldConfig(key: 'or_number', label: 'OR Number', type: FieldType.text, editable: false),
    // Picking the bill also fills "Paid By"; the two must agree.
    FieldConfig(key: 'bill_id', lockOnEdit: true, label: 'Bill', type: FieldType.reference, required: true, refTable: 'bills', refSelectColumns: _billsWithPayer, refLabelBuilder: _billLabel, showInList: false, autoFillTargetKey: 'user_id', autoFillSourceColumn: 'user_id'),
    FieldConfig(key: 'user_id', lockOnEdit: true, label: 'Paid By', type: FieldType.reference, required: true, refTable: 'users', refSelectColumns: _users, showInList: false, hiddenWhen: _payerAlreadyKnown),
    FieldConfig(key: 'amount_paid', label: 'Amount Paid', type: FieldType.decimal, required: true, currency: true, halfWidth: true),
    FieldConfig(key: 'payment_method', label: 'Method', type: FieldType.select, options: ['cash', 'bank_transfer', 'gcash', 'maya', 'check', 'online'], defaultValue: _cashMethod, halfWidth: true),
    FieldConfig(key: 'payment_date', label: 'Payment Date', type: FieldType.dateTime, required: true, pastOnly: true, defaultValue: _today, halfWidth: true),
    FieldConfig(key: 'reference_number', label: 'Reference #', type: FieldType.text, showInList: false, halfWidth: true, maxLength: kReferenceMaxLength),
    // Stays on the form: a bill only counts payments marked 'verified'.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['pending', 'verified', 'rejected', 'refunded'], defaultValue: _pendingStatus),
    FieldConfig(key: 'notes', label: 'Notes', type: FieldType.longText, showInList: false, advanced: true),
  ],
);

/// Community notices.
const announcements = ModuleConfig(
  key: 'announcements',
  table: 'announcements',
  label: 'Announcements',
  itemNoun: 'Announcement',
  titleField: 'title',
  subtitleField: 'category',
  statusField: 'status',
  searchField: 'title',
  // Owner of the post, for the locked "All phases" switch's reason line.
  filedByField: 'author_id',
  filedByNoun: 'the system administrator, or the HOA president or secretary who posted this',
  fields: [
    FieldConfig(key: 'title', label: 'Title', type: FieldType.text, required: true),
    FieldConfig(key: 'content', label: 'Content', type: FieldType.longText, required: true, showInList: false),
    FieldConfig(key: 'image_url', label: 'Photo', type: FieldType.text, showInList: false, imageFolder: 'announcements'),
    FieldConfig(key: 'category', label: 'Category', type: FieldType.select, options: ['general', 'emergency', 'maintenance', 'event', 'financial', 'security', 'other'], defaultValue: _generalCategory, halfWidth: true),
    FieldConfig(key: 'priority', label: 'Priority', type: FieldType.select, options: ['normal', 'important', 'urgent'], defaultValue: _normalPriority, halfWidth: true),
    FieldConfig(key: 'target_audience', label: 'Audience', type: FieldType.select, options: ['all', 'owners', 'tenants', 'security', 'board'], showInList: false, defaultValue: _allAudience),
    // Capped at 5 months out; a date further away is almost certainly a typo.
    FieldConfig(key: 'publish_at', label: 'Publish At', type: FieldType.dateTime, showInList: false, maxMonthsFromNow: 5, futureOnly: true, halfWidth: true),
    FieldConfig(key: 'expire_at', label: 'Expire At', type: FieldType.dateTime, showInList: false, maxMonthsFromNow: 5, futureOnly: true, halfWidth: true),
    FieldConfig(key: 'is_pinned', label: 'Pinned', type: FieldType.boolean, showInList: false, halfWidth: true),
    // Post to every phase: these roles only, and the president and secretary
    // only on their own posts. Enforced by set_phase_from_all_phases_flag().
    FieldConfig(key: 'all_phases', label: 'All phases', type: FieldType.boolean, showInList: false, halfWidth: true, restrictedToRoles: ['super_admin', 'hoa_president', 'secretary'], editableWhen: announcementAllPhasesEditable),
    // Off the form: new posts publish on create, and Archive/Publish are
    // actions on the card's menu. "Expired" comes from expire_at, not stored.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['draft', 'published', 'archived'], editable: false, defaultValue: _publishedStatus),
    FieldConfig(key: 'author_id', label: 'Author', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId),
  ],
);

/// Community events.
const events = ModuleConfig(
  key: 'events',
  table: 'events',
  label: 'Events',
  itemNoun: 'Event',
  titleField: 'title',
  subtitleField: 'venue',
  statusField: 'status',
  searchField: 'title',
  // Owner of the post, for the locked "All phases" switch's reason line.
  filedByField: 'organizer_id',
  filedByNoun: 'the system administrator, or the HOA president or secretary who posted this',
  fields: [
    FieldConfig(key: 'title', label: 'Title', type: FieldType.text, required: true),
    FieldConfig(key: 'description', label: 'Description', type: FieldType.longText, showInList: false),
    FieldConfig(key: 'image_url', label: 'Photo', type: FieldType.text, showInList: false, imageFolder: 'events'),
    FieldConfig(key: 'category', label: 'Category', type: FieldType.select, options: ['meeting', 'social', 'sports', 'maintenance', 'election', 'general'], defaultValue: _generalCategory, halfWidth: true),
    FieldConfig(key: 'venue', label: 'Venue', type: FieldType.text, halfWidth: true),
    FieldConfig(key: 'start_datetime', label: 'Start', type: FieldType.dateTime, required: true, futureOnly: true, halfWidth: true),
    FieldConfig(key: 'end_datetime', label: 'End', type: FieldType.dateTime, required: true, futureOnly: true, halfWidth: true),
    FieldConfig(key: 'max_attendees', label: 'Max Attendees', type: FieldType.number, showInList: false),
    FieldConfig(key: 'is_public', label: 'Public', type: FieldType.boolean, showInList: false, halfWidth: true),
    // Post to every phase: these roles only, and the president and secretary
    // only on their own posts. Enforced by set_phase_from_all_phases_flag().
    FieldConfig(key: 'all_phases', label: 'All phases', type: FieldType.boolean, showInList: false, halfWidth: true, restrictedToRoles: ['super_admin', 'hoa_president', 'secretary'], editableWhen: eventAllPhasesEditable),
    // Off the form: Upcoming/Ongoing/Completed are worked out from the start
    // and end times. Only 'cancelled' matters, set by the Cancel Event action.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['upcoming', 'ongoing', 'completed', 'cancelled'], editable: false, defaultValue: _upcomingStatus),
    FieldConfig(key: 'organizer_id', label: 'Organizer', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId),
  ],
);

/// Violation cases filed by officers against a resident.
const cases = ModuleConfig(
  key: 'cases',
  table: 'violations',
  label: 'Cases',
  itemNoun: 'Case',
  filedByField: 'reported_by',
  filedByNoun: 'the officer who filed this',
  statusOpenValues: ['reported', 'noticed'],
  titleField: 'violation_number',
  subtitleField: 'description',
  statusField: 'status',
  searchField: 'violation_number',
  permissionModuleOverride: 'violations',
  fields: [
    // Issued by a database trigger.
    FieldConfig(key: 'violation_number', label: 'Case Number', type: FieldType.text, editable: false),
    FieldConfig(key: 'reported_by', label: 'Reported By', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId),
    // Progress strip. contested and dismissed sit off the track: neither is
    // a step toward resolved. Off the create form: a new case is 'reported'.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['reported', 'noticed', 'contested', 'upheld', 'dismissed', 'penalty_imposed', 'resolved'],
        statusTrack: ['reported', 'noticed', 'upheld', 'penalty_imposed', 'resolved'],
        defaultValue: _reportedStatus, editOnly: true),
    // Picking the person fills in their address.
    FieldConfig(key: 'reported_against', lockOnEdit: true, label: 'Reported Against', type: FieldType.reference, required: true, refTable: 'users', refSelectColumns: _usersWithLot, refLabelBuilder: _billedToLabel, showInList: false, halfWidth: true,
        autoFillTargetKey: 'lot_id', autoFillSourceColumn: 'lot_id'),
    // Picking the address fills in whoever is registered there, only while
    // the person is blank, so correcting the address never replaces them.
    FieldConfig(key: 'lot_id', lockOnEdit: true, label: 'Where (Block/Lot)', type: FieldType.reference, refTable: 'lots', refSelectColumns: _lotsWithBlockAndOwner, refLabelBuilder: _lotWithBlockLabel, showInList: false, halfWidth: true,
        autoFillTargetKey: 'reported_against', autoFillPick: _soleOccupantId, autoFillOnlyWhenEmpty: true),
    FieldConfig(key: 'violation_type_id', label: 'Violation Type', type: FieldType.reference, refTable: 'violation_types', refSelectColumns: ['id', 'name'], refActiveOnly: true, showInList: false),
    FieldConfig(key: 'description', label: 'Description', type: FieldType.longText, required: true),
    FieldConfig(key: 'violation_date', label: 'Date', type: FieldType.date, required: true, pastOnly: true, halfWidth: true),
    FieldConfig(key: 'penalty_amount', label: 'Penalty', type: FieldType.decimal, showInList: false, currency: true, halfWidth: true),
    FieldConfig(key: 'resolution', label: 'Resolution', type: FieldType.longText, showInList: false, editOnly: true,
        requiredWhen: _closingViolation),
  ],
);

/// Permit applications: the resident applies, the office decides.
const permits = ModuleConfig(
  key: 'permits',
  table: 'permits',
  label: 'Permits',
  itemNoun: 'Permit',
  titleField: 'title',
  subtitleField: 'permit_number',
  statusField: 'status',
  searchField: 'title',
  filedByField: 'applicant_id',
  filedByNoun: 'the resident who applied',
  statusOpenValues: ['draft', 'submitted'],
  // Whose permit it is, shown first on the form.
  contextBuilder: permitApplicantCard,
  fields: [
    // Issued by a database trigger, so it stays off the form.
    FieldConfig(key: 'permit_number', label: 'Permit Number', type: FieldType.text, editable: false),
    // Progress strip. rejected, cancelled and expired sit off the track, and
    // so does 'draft', which is kept in the options for older rows.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['draft', 'submitted', 'under_review', 'approved', 'rejected', 'expired', 'cancelled'],
        statusTrack: ['submitted', 'under_review', 'approved'],
        defaultValue: _submittedStatus, editOnly: true,
        editableWhen: permitHandlingEditable),
    // Who the permit is for. Picking the resident fills their lot.
    // Hidden for residents: permits_insert_own pins applicant_id to them, so
    // a picker would be refused on save. The default files it as theirs.
    FieldConfig(key: 'applicant_id', label: 'Applicant', type: FieldType.reference, required: true, refTable: 'users', refSelectColumns: _usersWithLot, refRoleFilter: billableRoleNames, refLabelBuilder: _billedToLabel, showInList: false, halfWidth: true,
        defaultValue: _currentUserIdIfResident,
        restrictedToRoles: ['super_admin', 'secretary', 'hoa_president'],
        autoFillTargetKey: 'lot_id', autoFillSourceColumn: 'lot_id', lockOnEdit: true,
        editableWhen: permitHandlingEditable),
    // Picking the lot fills the applicant, only while that is blank, so
    // correcting the address never replaces the person.
    FieldConfig(key: 'lot_id', label: 'Lot', type: FieldType.reference, refTable: 'lots', refSelectColumns: _lotsWithBlockAndOwner, refLabelBuilder: _lotWithBlockLabel, showInList: false, halfWidth: true,
        lockOnEdit: true, lockedWhenFilledBy: 'applicant_id',
        // Residents never pick a lot: the database files it to their own.
        restrictedToRoles: officerRoleNames,
        autoFillTargetKey: 'applicant_id', autoFillPick: _soleOccupantId, autoFillOnlyWhenEmpty: true),
    // refActiveOnly: types retired in the CMS (Categories tab) are not offered.
    FieldConfig(key: 'permit_type_id', label: 'Permit Type', type: FieldType.reference, required: true, refTable: 'permit_types', refSelectColumns: ['id', 'name'], refActiveOnly: true, showInList: false, halfWidth: true,
        editableWhen: permitDetailsEditable),
    FieldConfig(key: 'title', label: 'Title', type: FieldType.text, required: true, halfWidth: true,
        editableWhen: permitDetailsEditable),
    FieldConfig(key: 'description', label: 'Description', type: FieldType.longText, showInList: false,
        editableWhen: permitDetailsEditable),
    // Both dates are required, so it is clear when the work must stop.
    FieldConfig(key: 'start_date', label: 'Start Date', type: FieldType.date, showInList: false, halfWidth: true, required: true,
        editableWhen: permitDetailsEditable),
    FieldConfig(key: 'end_date', label: 'End Date', type: FieldType.date, showInList: false, halfWidth: true, required: true,
        validate: endNotBeforeStartRule,
        editableWhen: permitDetailsEditable),
    FieldConfig(key: 'fee_amount', label: 'Fee', type: FieldType.decimal, currency: true, halfWidth: true, editOnly: true,
        editableWhen: permitHandlingEditable),
    FieldConfig(key: 'payment_status', label: 'Payment', type: FieldType.select, options: ['unpaid', 'paid', 'waived'], halfWidth: true, editOnly: true,
        defaultValue: _unpaidPayment,
        editableWhen: permitHandlingEditable),
    FieldConfig(key: 'review_notes', label: 'Review Notes', type: FieldType.longText, showInList: false, editOnly: true,
        editableWhen: permitHandlingEditable),
  ],
);

/// Registered vehicles: the owner describes the car, the office handles
/// status and sticker.
const vehicles = ModuleConfig(
  key: 'vehicles',
  table: 'vehicles',
  label: 'Vehicles',
  itemNoun: 'Vehicle',
  titleField: 'plate_number',
  subtitleField: 'model',
  statusField: 'status',
  searchField: 'plate_number',
  filedByField: 'user_id',
  filedByNoun: 'the vehicle owner',
  statusOpenValues: ['pending'],
  // Header card with plate, status and sticker, built from the form's values.
  // It has no contextAfterField, so it shows at the top.
  contextBuilder: vehicleSummaryCard,
  advancedLabel: 'Issue or change the sticker',
  // Lets an owner retire a car, freeing a place in the 4-vehicle limit.
  // protect_vehicle_officer_columns() allows this change, one way only.
  retireAction: RetireAction(
    label: 'No longer used',
    tooltip: 'Mark as no longer used (sold or retired)',
    confirmTitle: 'Mark this vehicle as no longer used?',
    confirmBody: 'It will stop counting toward your 4-vehicle limit and the '
        'guardhouse will no longer treat it as yours. Only the HOA office '
        'can bring it back.',
    field: 'status',
    value: 'inactive',
    doneValues: ['sold', 'inactive'],
  ),
  fields: [
    // Who the vehicle belongs to. Hidden for residents: vehicles_insert_own
    // pins user_id to them, so a picker would be refused on save. The default
    // files it as theirs.
    FieldConfig(key: 'user_id', label: 'Owner', type: FieldType.reference, required: true, lockOnEdit: true, refTable: 'users', refSelectColumns: _usersWithLot, refRoleFilter: billableRoleNames, refLabelBuilder: _billedToLabel, showInList: false, halfWidth: true,
        defaultValue: _currentUserIdIfResident,
        restrictedToRoles: ['super_admin', 'secretary', 'hoa_president', 'security'],
        autoFillTargetKey: 'lot_id', autoFillSourceColumn: 'lot_id',
        editableWhen: vehicleOfficerEditable),
    // Picking the lot fills the owner, only while that field is blank.
    FieldConfig(key: 'lot_id', label: 'Lot', type: FieldType.reference, refTable: 'lots', refSelectColumns: _lotsWithBlockAndOwner, refLabelBuilder: _lotWithBlockLabel, showInList: false, halfWidth: true,
        lockOnEdit: true, lockedWhenFilledBy: 'user_id',
        autoFillTargetKey: 'user_id', autoFillPick: _soleOccupantId, autoFillOnlyWhenEmpty: true,
        // Hidden for residents: protect_vehicle_officer_columns() files their
        // car to their own lot.
        restrictedToRoles: ['super_admin', 'secretary', 'hoa_president', 'security', 'audit_officer'],
        editableWhen: vehicleOfficerEditable),
    // Fixed once filed (the database's freeze_identity_columns also refuses a
    // change). A wrong plate means filing a new record.
    FieldConfig(key: 'plate_number', label: 'Plate Number', type: FieldType.text, required: true, halfWidth: true,
        lockOnEdit: true,
        upperCase: true, validate: plateRule,
        maxLength: kPlateMaxLength, allowedChars: kPlateAllowedChars, hint: 'e.g. ABC 1234'),
    FieldConfig(key: 'vehicle_type', label: 'Type', type: FieldType.select, required: true, options: ['car', 'motorcycle', 'truck', 'van', 'suv', 'other'], halfWidth: true),
    FieldConfig(key: 'make', label: 'Make', type: FieldType.text, showInList: false, halfWidth: true,
        allowedChars: kWordAllowedChars, validate: lettersOnlyRule),
    FieldConfig(key: 'model', label: 'Model', type: FieldType.text, halfWidth: true,
        allowedChars: kModelAllowedChars, validate: modelRule),
    FieldConfig(key: 'color', label: 'Color', type: FieldType.text, showInList: false, halfWidth: true,
        allowedChars: kWordAllowedChars, validate: lettersOnlyRule),
    // Up to this year only. protect_vehicle_officer_columns() refuses a later
    // year too.
    FieldConfig(key: 'year', label: 'Year', type: FieldType.number, showInList: false, halfWidth: true,
        yearPicker: true, yearsAhead: 0),
    // ---- the office's side, behind the disclosure ----
    // A new vehicle starts 'pending', becomes 'registered' once approved, and
    // 'active' in regular use. flagged, sold and inactive sit off the track.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['pending', 'registered', 'active', 'flagged', 'sold', 'inactive'],
        statusTrack: ['pending', 'registered', 'active'],
        defaultValue: _pendingStatus, editOnly: true, advanced: true,
        restrictedToRoles: ['super_admin', 'secretary', 'hoa_president', 'security'],
        editableWhen: vehicleOfficerEditable),
    // Off the create form: a new vehicle is pending, and the sticker comes at
    // approval.
    FieldConfig(key: 'sticker_number', label: 'Sticker Number', type: FieldType.text, showInList: false, halfWidth: true, advanced: true, editOnly: true,
        restrictedToRoles: ['super_admin', 'secretary', 'hoa_president', 'security'],
        editableWhen: vehicleOfficerEditable),
    FieldConfig(key: 'sticker_expiry', label: 'Sticker Expiry', type: FieldType.date, showInList: false, halfWidth: true, advanced: true, editOnly: true,
        restrictedToRoles: ['super_admin', 'secretary', 'hoa_president', 'security'],
        editableWhen: vehicleOfficerEditable),
  ],
);

/// The guardhouse's visitor log: who came in, who they visited, when they left.
const visitors = ModuleConfig(
  key: 'visitors',
  table: 'visitor_logs',
  label: 'Visitors',
  itemNoun: 'Visitor',
  titleField: 'visitor_name',
  subtitleField: 'purpose',
  searchField: 'visitor_name',
  permissionModuleOverride: 'visitor_logs',
  // Card under Time In: the expected time out, worked out from the purpose.
  contextAfterField: 'time_in',
  contextBuilder: visitorClockCard,
  fields: [
    FieldConfig(key: 'visitor_name', lockOnEdit: true, label: 'Visitor Name', type: FieldType.text, required: true, halfWidth: true,
        allowedChars: kNameAllowedChars, validate: nameRule),
    FieldConfig(key: 'visitor_contact', label: 'Contact Number', type: FieldType.text, showInList: false, halfWidth: true, maxLength: kPhoneMaxLength, allowedChars: '[0-9]', hint: '09XXXXXXXXX',
        required: true, validate: phoneRule),
    // Picking the host fills the lot being visited.
    FieldConfig(key: 'host_user_id', lockOnEdit: true, label: 'Host', type: FieldType.reference, required: true, refTable: 'users', refSelectColumns: _usersWithPhoneAndLot, refLabelBuilder: residentContactLabel, showInList: false, halfWidth: true,
        autoFillTargetKey: 'visiting_lot_id', autoFillSourceColumn: 'lot_id'),
    // Follows the host's address and locks once a host is chosen. Picking the
    // lot first fills the host, only while that is blank.
    FieldConfig(key: 'visiting_lot_id', lockOnEdit: true, lockedWhenFilledBy: 'host_user_id', label: 'Visiting Lot', type: FieldType.reference, required: true, refTable: 'lots', refSelectColumns: _lotsWithBlockAndOwner, refLabelBuilder: _lotWithBlockLabel, showInList: false, halfWidth: true,
        autoFillTargetKey: 'host_user_id', autoFillPick: _soleOccupantId, autoFillOnlyWhenEmpty: true),
    // Sets how long the visitor may stay, which drives overstay detection.
    FieldConfig(key: 'purpose_type', label: 'Purpose', type: FieldType.select, required: true,
        options: ['visitor', 'delivery', 'service', 'contractor', 'household_help', 'viewing', 'other'],
        defaultValue: _defaultPurposeType, halfWidth: true),
    // Free-text detail alongside the category ("Aircon cleaning service").
    FieldConfig(key: 'purpose', label: 'Details', type: FieldType.text, showInList: false, halfWidth: true),
    // No allotted-time field: while expected_minutes is null, expectedOut() in
    // visitor_rules.dart uses the time set for the purpose.
    FieldConfig(key: 'time_in', label: 'Time In', type: FieldType.dateTime, required: true, halfWidth: true,
        defaultValue: _todayStart),
    FieldConfig(key: 'vehicle_plate', label: 'Vehicle Plate', type: FieldType.text, showInList: false, halfWidth: true,
        upperCase: true, validate: plateRule,
        maxLength: kPlateMaxLength, allowedChars: kPlateAllowedChars, hint: 'e.g. ABC 1234'),
    // Off the create form: a visitor checking in has not left yet.
    FieldConfig(key: 'time_out', label: 'Time Out', type: FieldType.dateTime, editOnly: true),
    FieldConfig(key: 'notes', label: 'Notes', type: FieldType.longText, showInList: false, advanced: true),
    FieldConfig(key: 'logged_by', label: 'Logged By', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId),
  ],
);

/// Security incidents logged by officers.
const security = ModuleConfig(
  key: 'security',
  table: 'security_incidents',
  label: 'Security',
  itemNoun: 'Incident',
  // Names the officer, not a resident, in the locked-field message.
  filedByField: 'reported_by',
  filedByNoun: 'the officer who logged this',
  statusOpenValues: ['open', 'investigating'],
  titleField: 'title',
  subtitleField: 'type',
  statusField: 'status',
  searchField: 'title',
  permissionModuleOverride: 'security_incidents',
  // After creation this Edge Function suggests a severity. An officer decides
  // the final value.
  classifyFunctionName: 'classify-incident',
  fields: [
    // Issued by the database. Off the form, but shown in the list.
    FieldConfig(key: 'incident_number', label: 'Incident Number', type: FieldType.text, editable: false),
    // The AI's suggestion, shown as a read-only column. Set by classify-incident.
    FieldConfig(key: 'suggested_severity', label: 'AI Severity', type: FieldType.text, editable: false),
    FieldConfig(key: 'reported_by', label: 'Reported By', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId),
    // Progress strip. 'escalated' sits off the track: it is an outcome, not a
    // step toward closing. Off the create form: a new incident is 'open'.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['open', 'investigating', 'resolved', 'closed', 'escalated'],
        statusTrack: ['open', 'investigating', 'resolved', 'closed'],
        defaultValue: _openStatus, editOnly: true),
    FieldConfig(key: 'type', label: 'Type', type: FieldType.select, required: true, options: ['theft', 'vandalism', 'trespassing', 'disturbance', 'accident', 'fire', 'medical', 'other'], halfWidth: true),
    FieldConfig(key: 'severity', label: 'Severity', type: FieldType.select, options: ['low', 'medium', 'high', 'critical'], defaultValue: _mediumSeverity, halfWidth: true),
    // The reporter's account of what happened: read-only for other officers,
    // not hidden, because they need to read it.
    FieldConfig(key: 'title', label: 'Title', type: FieldType.text, required: true,
        editableWhen: incidentNarrativeEditable),
    FieldConfig(key: 'description', label: 'Description', type: FieldType.longText, required: true, showInList: false,
        editableWhen: incidentNarrativeEditable),
    FieldConfig(key: 'location', label: 'Location', type: FieldType.text, showInList: false, halfWidth: true,
        editableWhen: incidentNarrativeEditable),
    FieldConfig(key: 'incident_date', label: 'Date', type: FieldType.dateTime, required: true, halfWidth: true,
        editableWhen: incidentNarrativeEditable),
    // The picker offers only the guards plus admins.
    FieldConfig(key: 'assigned_to', label: 'Assigned To', type: FieldType.reference, refTable: 'users', refSelectColumns: _users, refRoleFilter: officerRoleNames, refRoleFilterFrom: _incidentAssigneeRoles, showInList: false),
    FieldConfig(key: 'resolution', label: 'Resolution', type: FieldType.longText, showInList: false, editOnly: true,
        requiredWhen: _closingIncident),
  ],
);

/// Document details, for editing and for the resident document list.
const documents = ModuleConfig(
  key: 'documents',
  table: 'documents',
  label: 'Documents',
  titleField: 'name',
  subtitleField: 'category',
  searchField: 'name',
  // Off because a new document needs a real file uploaded first, which
  // AdminDocumentsScreen does itself.
  allowCreate: false,
  fields: [
    FieldConfig(key: 'name', label: 'Name', type: FieldType.text, required: true),
    FieldConfig(key: 'category', label: 'Category', type: FieldType.text),
    FieldConfig(key: 'module', label: 'Related Module', type: FieldType.text),
    FieldConfig(key: 'mime_type', label: 'Type', type: FieldType.text, editable: false),
    FieldConfig(key: 'is_public', label: 'Public', type: FieldType.boolean, showInList: false),
  ],
);

/// Homeowner accounts: `users` rows with the member_resident role.
const residents = ModuleConfig(
  key: 'residents',
  table: 'users',
  label: 'Residents',
  itemNoun: 'Resident',
  titleField: 'first_name',
  subtitleField: 'email',
  statusField: 'status',
  searchField: 'last_name',
  roleFilter: 'member_resident',
  allowCreate: false, // residents self-register
  allowDelete: false,
  permissionModuleOverride: 'users',
  fields: [
    FieldConfig(key: 'first_name', label: 'First Name', type: FieldType.text, required: true, allowedChars: kNameAllowedChars, validate: nameRule),
    FieldConfig(key: 'last_name', label: 'Last Name', type: FieldType.text, required: true, allowedChars: kNameAllowedChars, validate: nameRule),
    // Locked: it is the sign-in address, and changing it only here would leave
    // auth.users on the old one.
    FieldConfig(key: 'email', label: 'Email', type: FieldType.text, required: true, lockOnEdit: true),
    FieldConfig(key: 'phone', label: 'Phone', type: FieldType.text, maxLength: kPhoneMaxLength, allowedChars: '[0-9]', hint: '09XXXXXXXXX', validate: phoneRule),
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['active', 'inactive', 'suspended', 'pending_verification']),
  ],
);

/// Tenant accounts: `users` rows with the tenant role.
final tenants = ModuleConfig(
  key: 'tenants',
  table: 'users',
  label: 'Tenants',
  itemNoun: 'Tenant',
  titleField: 'first_name',
  subtitleField: 'email',
  statusField: 'status',
  searchField: 'last_name',
  roleFilter: 'tenant',
  allowCreate: false,
  allowDelete: false,
  permissionModuleOverride: 'users',
  // The `residents` fields plus landlord and lease end.
  fields: [
    ...residents.fields,
    const FieldConfig(key: 'landlord_id', label: 'Landlord', type: FieldType.reference, refTable: 'users', refSelectColumns: _users, showInList: false),
    const FieldConfig(key: 'lease_end_date', label: 'Lease End', type: FieldType.date, showInList: false),
  ],
);

// Field gates for the request modules: the resident writes what they are
// asking for, the officer decides. These only explain the rule on screen; the
// database triggers enforce it, so keep the two in step.

// ---- permits -------------------------------------------------------
/// The application itself: its applicant, while it is draft or submitted.
bool permitDetailsEditable(FieldGate g) =>
    g.isCreating ||
    (g.isMine('applicant_id') && const {'draft', 'submitted'}.contains(g.status));

/// Fee, payment state, status and review notes — the office's side.
bool permitHandlingEditable(FieldGate g) =>
    g.isCreating || g.can('permits', 'update') || g.can('permits', 'approve');

// ---- gate passes ---------------------------------------------------
/// Who is visiting and why: the host, while the pass is pending.
bool gatePassDetailsEditable(FieldGate g) =>
    g.isCreating || (g.isMine('requested_by') && g.status == 'pending');

/// Plate and expiry: officers too, because the guard learns them at the gate,
/// plus the host while the pass is pending.
bool gatePassPlateOrValidityEditable(FieldGate g) =>
    g.isCreating ||
    g.can('gate_passes', 'update') ||
    g.can('gate_passes', 'approve') ||
    (g.isMine('requested_by') && g.status == 'pending');

/// Status and host: the office's side.
bool gatePassHandlingEditable(FieldGate g) =>
    g.isCreating ||
    g.can('gate_passes', 'update') ||
    g.can('gate_passes', 'approve');

// ---- move in / out --------------------------------------------------
/// Type, date and notes: the resident who filed it, while it is pending.
bool moveRequestDetailsEditable(FieldGate g) =>
    g.isCreating || (g.isMine('resident_id') && g.status == 'pending');

/// Status: the office's side.
bool moveRequestHandlingEditable(FieldGate g) =>
    g.isCreating || g.can('move_requests', 'update');

// ---- vehicles -------------------------------------------------------
/// Owner, lot, status and sticker: the office's, on a new vehicle as well as
/// on edit.
bool vehicleOfficerEditable(FieldGate g) => g.can('vehicles', 'update');

// ---- security incidents ---------------------------------------------
/// Title, description, location and date: only the officer who logged the
/// incident, and only while it is open or under investigation.
bool incidentNarrativeEditable(FieldGate g) {
  if (g.isCreating) return true;
  return g.isMine('reported_by') &&
      const {'open', 'investigating'}.contains(g.status);
}

/// The "All phases" switch: always on a new post; on an existing one only for
/// the system administrator or whoever wrote it. Must match
/// set_phase_from_all_phases_flag() in the database.
bool announcementAllPhasesEditable(FieldGate g) =>
    g.isCreating || g.role == 'super_admin' || g.isMine('author_id');

/// Same switch on events, whose author is the organizer.
bool eventAllPhasesEditable(FieldGate g) =>
    g.isCreating || g.role == 'super_admin' || g.isMine('organizer_id');

/// The resident's account of a complaint (subject, description, location,
/// date, who it is against, evidence): only the person who filed it, and only
/// while it is still `submitted`.
bool complaintNarrativeEditable(FieldGate g) {
  if (g.isCreating) return true;
  return g.isMine('complainant_id') && g.status == 'submitted';
}

/// The officers' handling of a complaint (category, priority, status,
/// assignment, resolution): anyone holding complaints:update, plus the
/// assignee, who must be able to close it. Must match
/// protect_complaint_columns() in the database.
bool complaintHandlingEditable(FieldGate g) {
  if (g.isCreating) return true;
  return g.can('complaints', 'update') || g.isMine('assigned_to');
}

/// Resident complaints: the resident owns the account, officers handle it.
const complaints = ModuleConfig(
  key: 'complaints',
  table: 'complaints',
  label: 'Complaints',
  itemNoun: 'Complaint',
  filedByField: 'complainant_id',
  filedByNoun: 'the resident who filed this',
  titleField: 'subject',
  subtitleField: 'complaint_number',
  statusField: 'status',
  searchField: 'subject',
  // Classifies complaints filed on this form. CrudService sends {'id': ...},
  // so the Edge Function must keep accepting that key.
  classifyFunctionName: 'classify-complaint',
  fields: [
    // Issued by a database trigger.
    FieldConfig(key: 'complaint_number', label: 'Complaint Number', type: FieldType.text, editable: false),
    // Always the person filing.
    FieldConfig(key: 'complainant_id', label: 'Complainant', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId),
    // Progress strip. 'dismissed' sits off the track: it is an outcome, not a
    // step toward resolved. Off the create form: a new complaint is 'submitted'.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['submitted', 'under_review', 'in_progress', 'resolved', 'dismissed'],
        statusTrack: ['submitted', 'under_review', 'in_progress', 'resolved'],
        defaultValue: _submittedStatus, editOnly: true,
        editableWhen: complaintHandlingEditable),
    FieldConfig(key: 'category', label: 'Category', type: FieldType.select, required: true, options: ['noise', 'maintenance', 'billing', 'security', 'parking', 'pets', 'sanitation', 'common_area', 'neighbor_dispute', 'other'],
        halfWidth: true,
        editableWhen: complaintHandlingEditable),
    FieldConfig(key: 'priority', label: 'Priority', type: FieldType.select, options: ['low', 'medium', 'high', 'urgent'],
        defaultValue: _mediumSeverity, halfWidth: true,
        editableWhen: complaintHandlingEditable),
    FieldConfig(key: 'subject', label: 'Subject', type: FieldType.text, required: true,
        editableWhen: complaintNarrativeEditable),
    FieldConfig(key: 'description', label: 'Description', type: FieldType.longText, required: true, showInList: false,
        editableWhen: complaintNarrativeEditable),
    // Free text, because the target may have no account, with a resident
    // lookup. Choosing a resident records against_user_id; typing by hand
    // clears it, so the link always matches the words.
    FieldConfig(key: 'against_text', label: 'Against', type: FieldType.text, showInList: false, halfWidth: true,
        refTable: 'users', refSelectColumns: _users, refRoleFilter: billableRoleNames,
        refLabelBuilder: _billedToLabel, lookupIdKey: 'against_user_id',
        editableWhen: complaintNarrativeEditable),
    // Free text ("near the gym"): complaints often happen at common areas, not
    // at a lot.
    FieldConfig(key: 'location', label: 'Where', type: FieldType.text, showInList: false, halfWidth: true,
        editableWhen: complaintNarrativeEditable),
    // Defaults to the filing day; the database fills the same day if it is
    // left blank (trg_000_default_incident_date).
    FieldConfig(key: 'incident_date', label: 'Incident Date', type: FieldType.date, showInList: false, pastOnly: true,
        defaultValue: _today, editableWhen: complaintNarrativeEditable),
    // Supporting photos or documents, in the private documents bucket. Only
    // the complainant may change them, while the complaint is submitted.
    // Storage must check complaints:read_all, not read: residents hold read.
    FieldConfig(key: 'attachments', label: 'Evidence', type: FieldType.attachments, showInList: false,
        attachmentFolder: 'complaints',
        editableWhen: complaintNarrativeEditable),
    // restrictedToRoles: who may assign. refRoleFilter: who can be assigned,
    // narrowed by the category (see core/concern_routing.dart).
    FieldConfig(key: 'assigned_to', label: 'Assigned To', type: FieldType.reference, refTable: 'users', refSelectColumns: _users, refRoleFilter: officerRoleNames, refRoleFilterFrom: _assigneeRolesForCategory, refRoleFilterDependsOn: 'category', showInList: false, restrictedToRoles: ['super_admin', 'secretary', 'hoa_president'],
        editableWhen: complaintHandlingEditable),
    // Off the create form: nothing is resolved at filing.
    FieldConfig(key: 'resolution', label: 'Resolution', type: FieldType.longText, showInList: false, editOnly: true,
        requiredWhen: _closingComplaint,
        editableWhen: complaintHandlingEditable),
  ],
);

/// Gate passes for visitors: a resident requests, the guardhouse decides.
const gatePasses = ModuleConfig(
  key: 'gate_passes',
  table: 'gate_passes',
  label: 'Gate Passes',
  itemNoun: 'Gate Pass',
  titleField: 'visitor_name',
  subtitleField: 'pass_number',
  statusField: 'status',
  searchField: 'visitor_name',
  filedByField: 'requested_by',
  filedByNoun: 'the resident who requested this',
  statusOpenValues: ['pending'],
  // Card under the host and lot pickers: the host's address and phone.
  contextAfterField: 'lot_id',
  contextBuilder: gatePassHostCard,
  advancedLabel: 'Add vehicle plate or extra uses',
  fields: [
    // Issued by a database trigger.
    FieldConfig(key: 'pass_number', label: 'Pass Number', type: FieldType.text, editable: false),
    // Progress strip. rejected and expired sit off the track.
    // Off the create form: a new pass is 'pending'.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['pending', 'approved', 'rejected', 'expired', 'used'],
        statusTrack: ['pending', 'approved', 'used'],
        defaultValue: _pendingStatus, editOnly: true,
        editableWhen: gatePassHandlingEditable),
    // The host: the resident expecting the visitor. Hidden from residents:
    // gate_passes_insert_own pins requested_by to them, so a picker would be
    // refused on save. The default files it as theirs.
    FieldConfig(key: 'requested_by', lockOnEdit: true, label: 'Host', type: FieldType.reference, required: true,
        refTable: 'users', refSelectColumns: _usersWithPhoneAndLot,
        refRoleFilter: billableRoleNames, refLabelBuilder: residentContactLabel,
        showInList: false, halfWidth: true,
        defaultValue: _currentUserIdIfResident,
        restrictedToRoles: ['super_admin', 'secretary', 'hoa_president', 'security'],
        autoFillTargetKey: 'lot_id', autoFillSourceColumn: 'lot_id',
        editableWhen: gatePassHandlingEditable),
    // Picking the lot fills the host, only while that is blank.
    FieldConfig(key: 'lot_id', lockOnEdit: true, label: 'Lot', type: FieldType.reference, required: true, refTable: 'lots', refSelectColumns: _lotsWithBlockAndOwner, refLabelBuilder: _lotWithBlockLabel, showInList: false, halfWidth: true,
        autoFillTargetKey: 'requested_by', autoFillPick: _soleOccupantId, autoFillOnlyWhenEmpty: true),
    FieldConfig(key: 'visitor_name', lockOnEdit: true, label: 'Visitor Name', type: FieldType.text, required: true, halfWidth: true,
        editableWhen: gatePassDetailsEditable, allowedChars: kNameAllowedChars, validate: nameRule),
    FieldConfig(key: 'visitor_contact', label: 'Contact Number', type: FieldType.text, showInList: false, halfWidth: true, maxLength: kPhoneMaxLength, allowedChars: '[0-9]', hint: '09XXXXXXXXX',
        required: true, validate: phoneRule,
        editableWhen: gatePassDetailsEditable),
    FieldConfig(key: 'purpose', label: 'Purpose', type: FieldType.longText, showInList: false,
        editableWhen: gatePassDetailsEditable),
    FieldConfig(key: 'valid_from', label: 'Valid From', type: FieldType.dateTime, required: true, futureOnly: true, halfWidth: true,
        defaultValue: _todayStart,
        editableWhen: gatePassDetailsEditable),
    // Plate and expiry are shared with the guard: see
    // gatePassPlateOrValidityEditable.
    FieldConfig(key: 'valid_until', label: 'Valid Until', type: FieldType.dateTime, required: true, futureOnly: true, halfWidth: true,
        editableWhen: gatePassPlateOrValidityEditable),
    FieldConfig(key: 'vehicle_plate', label: 'Vehicle Plate', type: FieldType.text, showInList: false, halfWidth: true, advanced: true,
        upperCase: true, validate: plateRule,
        maxLength: kPlateMaxLength, allowedChars: kPlateAllowedChars, hint: 'e.g. ABC 1234',
        editableWhen: gatePassPlateOrValidityEditable),
    FieldConfig(key: 'max_uses', label: 'Max Uses', type: FieldType.number, showInList: false, halfWidth: true, advanced: true,
        editableWhen: gatePassDetailsEditable),
    // Officers only, and off the create form.
    FieldConfig(key: 'approved_by', label: 'Approved By', type: FieldType.reference, refTable: 'users', refSelectColumns: _users, refRoleFilter: officerRoleNames, showInList: false, editOnly: true, advanced: true,
        restrictedToRoles: ['super_admin', 'secretary', 'hoa_president', 'security']),
  ],
);

/// Read-only activity trail. The screen cannot create, edit or delete entries.
const auditLogs = ModuleConfig(
  key: 'audit_logs',
  table: 'audit_logs',
  label: 'Audit Logs',
  titleField: 'action',
  subtitleField: 'module',
  statusField: 'severity',
  searchField: 'action',
  allowCreate: false,
  allowEdit: false,
  allowDelete: false,
  fields: [
    FieldConfig(key: 'action', label: 'Action', type: FieldType.text),
    FieldConfig(key: 'module', label: 'Module', type: FieldType.text),
    FieldConfig(key: 'resource', label: 'Resource', type: FieldType.text, showInList: false),
    FieldConfig(key: 'resource_id', label: 'Resource ID', type: FieldType.number, showInList: false),
    FieldConfig(key: 'severity', label: 'Severity', type: FieldType.select, options: ['info', 'warning', 'critical']),
    FieldConfig(key: 'created_at', label: 'When', type: FieldType.dateTime),
  ],
);

/// Key/value app configuration.
const systemSettings = ModuleConfig(
  key: 'system_settings',
  table: 'system_settings',
  label: 'Settings',
  titleField: 'setting_key',
  subtitleField: 'category',
  searchField: 'setting_key',
  allowDelete: false,
  fields: [
    FieldConfig(key: 'setting_key', label: 'Key', type: FieldType.text, required: true),
    FieldConfig(key: 'value', label: 'Value', type: FieldType.text),
    FieldConfig(key: 'type', label: 'Type', type: FieldType.select, options: ['string', 'number', 'boolean', 'json']),
    FieldConfig(key: 'category', label: 'Category', type: FieldType.text),
    FieldConfig(key: 'description', label: 'Description', type: FieldType.longText, showInList: false),
    FieldConfig(key: 'is_public', label: 'Public', type: FieldType.boolean, showInList: false),
    FieldConfig(key: 'updated_by', label: 'Updated By', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId),
  ],
);

/// Form behind "Add Block" on the Community Map screen. Not in
/// [moduleRegistry], so it has no route of its own.
const blocks = ModuleConfig(
  key: 'blocks',
  table: 'blocks',
  label: 'Block',
  titleField: 'block_name',
  subtitleField: 'phase',
  searchField: 'block_name',
  fields: [
    FieldConfig(key: 'block_name', label: 'Block Name', type: FieldType.text, required: true),
    FieldConfig(key: 'phase', label: 'Phase', type: FieldType.text),
    FieldConfig(key: 'description', label: 'Description', type: FieldType.longText, showInList: false),
  ],
);

/// Form behind "Add Lot" on the Community Map screen, same as [blocks].
const lots = ModuleConfig(
  key: 'lots',
  table: 'lots',
  label: 'Lot',
  titleField: 'lot_number',
  subtitleField: 'street_address',
  statusField: 'status',
  searchField: 'lot_number',
  fields: [
    FieldConfig(key: 'lot_number', label: 'Lot Number', type: FieldType.text, required: true),
    FieldConfig(key: 'block_id', label: 'Block', type: FieldType.reference, required: true, refTable: 'blocks', refSelectColumns: ['id', 'block_name']),
    FieldConfig(key: 'street_address', label: 'Street Address', type: FieldType.text),
    FieldConfig(key: 'lot_type', label: 'Lot Type', type: FieldType.select, options: ['residential', 'commercial', 'vacant']),
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['owned', 'vacant', 'occupied']),
    // The pin position (map_x/map_y) is not on this form: it is set by tapping
    // the picture on the Community Map screen.
    FieldConfig(key: 'area_sqm', label: 'Area (sqm)', type: FieldType.decimal, showInList: false),
    FieldConfig(key: 'notes', label: 'Notes', type: FieldType.longText, showInList: false),
  ],
);

/// Create/edit form for a budget allocation on the Budget screen. Not in
/// [moduleRegistry], so it has no route of its own.
const budgetCategories = ModuleConfig(
  key: 'budget_categories',
  table: 'budget_categories',
  label: 'Budget Category',
  itemNoun: 'Budget Category',
  titleField: 'name',
  subtitleField: 'fiscal_year',
  searchField: 'name',
  // Card under the amount: the year's running total.
  contextAfterField: 'allocated_amount',
  contextBuilder: budgetYearCard,
  fields: [
    FieldConfig(key: 'name', label: 'Category Name', type: FieldType.text, required: true),
    // Picked from a year grid; defaults to the current year.
    FieldConfig(key: 'fiscal_year', label: 'Fiscal Year', type: FieldType.number, required: true, defaultValue: _currentYear, halfWidth: true,
        yearPicker: true, yearsAhead: 5, firstYear: 2010),
    FieldConfig(key: 'allocated_amount', label: 'Allocated Amount', type: FieldType.decimal, required: true, currency: true, halfWidth: true),
    FieldConfig(key: 'notes', label: 'Notes', type: FieldType.longText, showInList: false),
    FieldConfig(key: 'created_by', label: 'Created By', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId),
  ],
);

/// Residents' household members. Read-only on the officer route; the resident
/// route passes `true` overrides on `MemberModuleScreen` so residents can
/// manage their own rows.
const householdMembers = ModuleConfig(
  key: 'household_members',
  table: 'household_members',
  label: 'Household Members',
  itemNoun: 'Household Member',
  titleField: 'full_name',
  subtitleField: 'relationship',
  searchField: 'full_name',
  allowCreate: false,
  allowEdit: false,
  allowDelete: false,
  // One header row per household instead of the owner on every line.
  groupKey: _householdGroupKey,
  groupHeader: _householdGroupHeader,
  // Joins the owner's name for the group header.
  selectOverride: '*, resident:resident_id(first_name, last_name)',
  fields: [
    // Always the current user's own row. Not a list column: the owner is the
    // group header.
    FieldConfig(key: 'resident_id', label: 'Owner (Resident)', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId, listValueBuilder: _joinedResidentName),
    FieldConfig(key: 'full_name', label: 'Full Name', type: FieldType.text, required: true, allowedChars: kNameAllowedChars, validate: nameRule),
    // 'tenant' only records who lives at this address. It is not the `tenant`
    // account role, which has its own login.
    FieldConfig(key: 'relationship', label: 'Relationship', type: FieldType.select, required: true, options: ['spouse', 'child', 'parent', 'helper', 'tenant', 'other']),
    // Required for adults so the office and the guardhouse can reach them;
    // a child usually has no number of their own.
    FieldConfig(key: 'phone', label: 'Phone', type: FieldType.text, maxLength: kPhoneMaxLength, allowedChars: '[0-9]', hint: '09XXXXXXXXX', requiredWhen: _phoneRequiredUnlessChild,
        validate: phoneRule),
    FieldConfig(key: 'email', label: 'Email', type: FieldType.text),
  ],
);

bool _phoneRequiredUnlessChild(Map<String, dynamic> v) =>
    (v['relationship'] ?? '').toString() != 'child';

/// Form for the Move In/Out screen. Officers with the right permission can
/// file a request for any resident.
const moveRequests = ModuleConfig(
  key: 'move_requests',
  table: 'move_requests',
  label: 'Move Request',
  titleField: 'request_number',
  subtitleField: 'request_type',
  statusField: 'status',
  searchField: 'request_number',
  filedByField: 'resident_id',
  filedByNoun: 'the resident who filed this',
  statusOpenValues: ['pending'],
  advancedLabel: 'Record who reviewed this',
  fields: [
    // Issued by a database trigger.
    FieldConfig(key: 'request_number', label: 'Request Number', type: FieldType.text, editable: false),
    // Progress strip. 'rejected' sits off the track.
    // Off the create form: a new request is 'pending'.
    FieldConfig(key: 'status', label: 'Status', type: FieldType.select, options: ['pending', 'approved', 'scheduled', 'rejected', 'completed'],
        statusTrack: ['pending', 'approved', 'scheduled', 'completed'],
        defaultValue: _pendingStatus, editOnly: true,
        editableWhen: moveRequestHandlingEditable),
    // Picking the resident fills their address. Hidden for residents:
    // move_requests_insert_own pins resident_id to them, so a picker would be
    // refused on save. The default files it as theirs.
    FieldConfig(key: 'resident_id', label: 'Resident', type: FieldType.reference, required: true, lockOnEdit: true, refTable: 'users', refSelectColumns: _usersWithLot, refRoleFilter: billableRoleNames, refLabelBuilder: _billedToLabel, halfWidth: true,
        defaultValue: _currentUserIdIfResident,
        restrictedToRoles: ['super_admin', 'secretary', 'hoa_president', 'security'],
        autoFillTargetKey: 'lot_id', autoFillSourceColumn: 'lot_id'),
    // Picking the lot fills the resident, only while that field is blank.
    FieldConfig(key: 'lot_id', label: 'Lot', type: FieldType.reference, refTable: 'lots', refSelectColumns: _lotsWithBlockAndOwner, refLabelBuilder: _lotWithBlockLabel, showInList: false, halfWidth: true,
        lockOnEdit: true, lockedWhenFilledBy: 'resident_id',
        // Residents never pick a lot: the database files it to their own.
        restrictedToRoles: officerRoleNames,
        autoFillTargetKey: 'resident_id', autoFillPick: _soleOccupantId, autoFillOnlyWhenEmpty: true),
    FieldConfig(key: 'request_type', label: 'Type', type: FieldType.select, required: true, lockOnEdit: true, options: ['move_in', 'move_out'], halfWidth: true,
        editableWhen: moveRequestDetailsEditable),
    // futureOnly: a move is requested ahead of time.
    FieldConfig(key: 'move_date', label: 'Move Date', type: FieldType.date, required: true, futureOnly: true, halfWidth: true,
        editableWhen: moveRequestDetailsEditable),
    FieldConfig(key: 'notes', label: 'Notes', type: FieldType.longText, showInList: false,
        editableWhen: moveRequestDetailsEditable),
    // Set only once someone reviews it, so it is off the create form. Officers
    // only.
    FieldConfig(key: 'reviewed_by', label: 'Reviewed By', type: FieldType.reference, refTable: 'users', refSelectColumns: _users, refRoleFilter: officerRoleNames, showInList: false, editOnly: true, advanced: true,
        restrictedToRoles: ['super_admin', 'secretary', 'hoa_president', 'security']),
  ],
);

/// Form for logging an expense on the Budget screen. Not in [moduleRegistry].
const budgetExpenses = ModuleConfig(
  key: 'budget_expenses',
  table: 'budget_expenses',
  label: 'Expense',
  titleField: 'description',
  subtitleField: 'expense_date',
  searchField: 'description',
  fields: [
    FieldConfig(key: 'category_id', label: 'Category', type: FieldType.reference, required: true, refTable: 'budget_categories', refSelectColumns: ['id', 'name']),
    FieldConfig(key: 'description', label: 'Description', type: FieldType.text, required: true),
    FieldConfig(key: 'amount', label: 'Amount', type: FieldType.decimal, required: true, currency: true),
    // pastOnly: an expense is recorded after it happened.
    FieldConfig(key: 'expense_date', label: 'Expense Date', type: FieldType.date, required: true, defaultValue: _today, pastOnly: true),
    FieldConfig(key: 'recorded_by', label: 'Recorded By', type: FieldType.reference, editable: false, showInList: false, defaultValue: _currentUserId),
  ],
);

/// The generic modules. main.dart builds a route for each one that has no
/// bespoke screen. Screens with their own route (Community Map, Budget, Move
/// In/Out) are left out, and some keys map to a different permission module
/// through [ModuleConfig.permissionModuleOverride].
final List<ModuleConfig> moduleRegistry = [
  billing,
  payments,
  announcements,
  events,
  cases,
  permits,
  vehicles,
  visitors,
  security,
  documents,
  residents,
  tenants,
  complaints,
  gatePasses,
  auditLogs,
  systemSettings,
  householdMembers,
];

/// The module with this key, or null if there is none.
ModuleConfig? moduleByKey(String key) {
  for (final m in moduleRegistry) {
    if (m.key == key) return m;
  }
  return null;
}