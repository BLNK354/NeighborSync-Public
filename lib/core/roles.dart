/// Role names (`roles.name`) for officers/staff, who get the admin dashboard.
/// Used by login and the router guard; keep it the only copy.
const officerRoleNames = <String>[
  'super_admin',
  'hoa_president',
  'treasurer',
  'secretary',
  'audit_officer',
  'security',
];

/// Set form of [officerRoleNames] for quick membership checks.
/// The list form exists because const field values need a List.
const officerRoles = {...officerRoleNames};

/// Roles an approver can assign to a public signup. Signups default to
/// [defaultSelfServiceRole]; the registrant does not choose.
const selfServiceRoles = ['member_resident', 'tenant', 'visitor'];

/// Display names for [selfServiceRoles].
const selfServiceRoleLabels = {
  'member_resident': 'Resident',
  'tenant': 'Tenant',
  'visitor': 'Visitor',
};

/// Role a public signup gets until an officer reviews it.
const defaultSelfServiceRole = 'member_resident';

/// Roles that can be billed. Visitors and officers are not billed.
const billableRoleNames = ['member_resident', 'tenant'];

/// Temporary accounts with `users.expires_at`. Expiry is enforced in the
/// database (current_user_id() returns NULL), not just in the UI.
const expiringRoleNames = <String>['guest'];

/// Non-resident accounts: resident shell with a smaller menu.
/// A guest is a temporary login (map, announcements, events).
const outsiderRoleNames = <String>['guest', 'visitor'];

/// Set form of [outsiderRoleNames].
const outsiderRoles = {...outsiderRoleNames};

/// Roles an officer creates directly, not through public signup.
const officerIssuedRoleLabels = {
  'guest': 'Guest (temporary)',
};

/// Every role, broadest authority first. Used for the Super Admin's role
/// picker, which is not limited to [selfServiceRoles].
const allRoleOrder = [
  'super_admin',
  'hoa_president',
  'treasurer',
  'secretary',
  'audit_officer',
  'security',
  'member_resident',
  'tenant',
  'guest',
  'visitor',
];

/// Can this officer edit or delete the announcement or event?
/// One-phase posts: yes. All-phase posts: only a super admin, or the HOA
/// president or secretary who wrote it. Must match the
/// all_phases_posts_admin_only_* database policies.
bool canManageSharedPost(
  Map<String, dynamic> row, {
  required String authorKey,
  required String? role,
  required int? myUserId,
}) {
  if (row['phase'] != null) return true;
  if (role == 'super_admin') return true;
  return (role == 'hoa_president' || role == 'secretary') &&
      myUserId != null &&
      row[authorKey]?.toString() == myUserId.toString();
}
