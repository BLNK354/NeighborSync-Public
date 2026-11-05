/// Role-based access checks. Permissions are a map of module name to the
/// actions the role holds, e.g. `{'bills': {'read','create'}}`.
/// Module names must match the database; [ModuleConfig.permissionModule]
/// maps the registry keys that differ (billing->bills, cases->violations).
library;

/// True if the role has any permission on [module]; decides menu and route visibility.
bool canAccessModule(Map<String, Set<String>> perms, String module) {
  final actions = perms[module];
  return actions != null && actions.isNotEmpty;
}

/// True if the role holds [action] ('read', 'create', 'update', 'delete',
/// 'approve') on [module]; used to show or hide buttons.
bool canPerform(Map<String, Set<String>> perms, String module, String action) {
  return perms[module]?.contains(action) ?? false;
}
