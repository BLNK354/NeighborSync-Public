import 'package:flutter/material.dart';
import '../core/module_config.dart';
import '../services/supabase_service.dart';
import '../widgets/admin_shell.dart';
import '../widgets/member_shell.dart';
import '../widgets/module_list_view.dart';
import '../core/safe_state.dart';

/// Officer screen for any generic module: a [ModuleListView] inside [AdminShell].
class ModuleScreen extends StatelessWidget {
  final ModuleConfig config;
  const ModuleScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: config.label,
      activeItem: config.label,
      child: ModuleListView(config: config),
    );
  }
}

/// Resident view of a module inside [MemberShell]. Set [selfFilterField]
/// (e.g. `'user_id'`) to show only the resident's own rows; [staticFilters]
/// narrows further.
///
/// [allowCreate]/[allowEdit]/[allowDelete] default to false; match them to
/// what the database allows, or a button will show and then fail.
class MemberModuleScreen extends StatefulWidget {
  final ModuleConfig config;
  final String navLabel;
  final String? selfFilterField;
  final Map<String, dynamic>? staticFilters;
  final bool allowCreate;
  final bool allowEdit;
  final bool allowDelete;

  const MemberModuleScreen({
    super.key,
    required this.config,
    required this.navLabel,
    this.selfFilterField,
    this.staticFilters,
    this.allowCreate = false,
    this.allowEdit = false,
    this.allowDelete = false,
  });

  @override
  State<MemberModuleScreen> createState() => _MemberModuleScreenState();
}

class _MemberModuleScreenState extends State<MemberModuleScreen> with SafeSetState<MemberModuleScreen> {
  Map<String, dynamic>? _filters;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _resolveFilters();
  }

  Future<void> _resolveFilters() async {
    final filters = <String, dynamic>{...?widget.staticFilters};
    if (widget.selfFilterField != null) {
      final myId = await SupabaseService.instance.getMyUserId();
      if (myId != null) filters[widget.selfFilterField!] = myId;
    }
    if (!mounted) return;
    setState(() {
      _filters = filters;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MemberShell(
      title: widget.config.label,
      activeItem: widget.navLabel,
      child: _ready
          ? ModuleListView(
              config: widget.config,
              extraFilters: _filters,
              allowCreateOverride: widget.allowCreate,
              allowEditOverride: widget.allowEdit,
              allowDeleteOverride: widget.allowDelete,
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
