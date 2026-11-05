/// Which officer roles are responsible for which kind of concern.
///
/// Used by the "Assigned To" picker so a complaint or incident only offers
/// officers whose job covers it.
///
/// This is about job scope, not permissions: permissions say what a role may
/// do, this says what a role should be given.
///
/// Keep the category keys in sync with the `category` options on the
/// complaints module in [module_registry.dart].
library;

/// Roles that can be assigned any concern, whatever the category.
const concernAdminRoles = <String>['super_admin', 'hoa_president'];

/// category -> officer roles that can be assigned that category.
///
/// Security covers gate and enforcement, treasurer covers money, secretary
/// covers records and upkeep. `neighbor_dispute` and `other` are shared.
/// `audit_officer` is left out on purpose so auditors never handle cases.
const concernCategoryRoles = <String, List<String>>{
  // --- Security / enforcement ---
  'security': ['security'],
  'parking': ['security'],
  'noise': ['security'],
  'pets': ['security'],

  // --- Finance ---
  'billing': ['treasurer'],

  // --- Records / facilities / administration ---
  'maintenance': ['secretary'],
  'sanitation': ['secretary'],
  'common_area': ['secretary'],

  // --- Shared: either role may take these ---
  'neighbor_dispute': ['secretary', 'security'],
  'other': ['secretary', 'security'],
};

/// Officer roles eligible to be assigned a concern in [category].
///
/// Always includes [concernAdminRoles]. An unknown category returns every
/// listed role, so the picker is never empty.
List<String> rolesForConcernCategory(String? category) {
  final key = (category ?? '').trim().toLowerCase();
  final specific = concernCategoryRoles[key];
  if (specific == null || specific.isEmpty) {
    final all = <String>{...concernAdminRoles};
    for (final v in concernCategoryRoles.values) {
      all.addAll(v);
    }
    return all.toList();
  }
  return <String>{...concernAdminRoles, ...specific}.toList();
}

/// Whether [roleName] is in scope for [category]. Used to flag assignments
/// that fall outside the routing.
bool roleHandlesConcern(String? roleName, String? category) {
  if (roleName == null || roleName.isEmpty) return true;
  if (concernAdminRoles.contains(roleName)) return true;
  return rolesForConcernCategory(category).contains(roleName);
}

/// Short label for who normally handles a category, shown on out-of-scope
/// assignments.
String concernOwnerLabel(String? category) {
  final roles = concernCategoryRoles[(category ?? '').trim().toLowerCase()];
  if (roles == null || roles.isEmpty) return 'an administrator';
  const display = {
    'security': 'Security Personnel',
    'treasurer': 'the Treasurer',
    'secretary': 'the Secretary',
  };
  return roles.map((r) => display[r] ?? r).join(' or ');
}
