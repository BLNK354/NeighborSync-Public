import 'dart:async';
import '../core/card_filter.dart';
import 'package:flutter/material.dart';
import '../core/record_focus.dart';
import '../widgets/pagination_footer.dart';
import '../core/form_helpers.dart';
import '../core/permissions.dart';
import '../core/module_registry.dart';
import '../core/text_utils.dart';
import '../offline/connectivity_service.dart';
import '../offline/offline_repository.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/status_badge.dart';
import '../widgets/table_sorting.dart';
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/safe_state.dart';

/// Officers' complaints list: status cards that filter, plus a table (cards
/// on a phone). Assigning a "submitted" complaint moves it to "under review"
/// through a database trigger. Shown as a tab inside CommunityConcernScreen.
class AdminComplaintsScreen extends StatefulWidget {
  const AdminComplaintsScreen({super.key});

  @override
  State<AdminComplaintsScreen> createState() => _AdminComplaintsScreenState();
}

class _AdminComplaintsScreenState extends State<AdminComplaintsScreen>
    with SafeSetState<AdminComplaintsScreen>, TableSortState, RecordFocusTarget {
  // Current page of the list, starting at 1.
  int _page = 1;

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';

  /// Filters the list to a status card's status; tapping it again clears it.
  void _tapStatus(String status) => setState(() {
        _statusFilter = _statusFilter == status ? 'all' : status;
        _page = 1;
      });

  /// Whether this officer may file a complaint on someone's behalf.
  bool _canCreate = false;

  /// Whether the suggestion chip can be tapped to refile (complaints:update).
  /// Without it the chip still shows, read-only.
  bool _canReclassify = false;
  // True when the rows came from the local cache; shows the offline banner.
  bool _offlineData = false;

  // Separate cache key: these rows include joined names, so they must not
  // overwrite a plain `complaints` cache.
  static const _cacheKey = 'complaints_officer_view';

  @override
  void initState() {
    super.initState();
    // A dashboard card may have opened this screen with a filter.
    _statusFilter = CardFilter.take('complaints') ?? _statusFilter;
    RefreshBus.bind(this, _load);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!ConnectivityService.instance.isOnline.value) {
      await _loadFromCache();
      return;
    }
    try {
      // Load every complaint, 1000 at a time (the server's per-request cap).
      // Cards and filters count on the device, so a partial list undercounts.
      final data = <dynamic>[];
      const page = 1000;
      for (var from = 0;; from += page) {
        final chunk = await SupabaseService.instance.client
            .from('complaints')
            .select('*, complainant:complainant_id(first_name, last_name), '
                'assignee:assigned_to(first_name, last_name)')
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .range(from, from + page - 1);
        data.addAll(chunk as List);
        if (chunk.length < page || from >= 9000) break;
      }
      final perms = await SupabaseService.instance.getMyPermissions();
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(data);
      unawaited(OfflineRepository.instance.cacheRows(_cacheKey, rows));
      setState(() {
        _rows = rows;
        _canCreate = canPerform(perms, 'complaints', 'create');
        _canReclassify = canPerform(perms, 'complaints', 'update');
        _offlineData = false;
        _loading = false;
      });
      // Opened from a notification: show and highlight that one record.
      takeRecordFocus('complaints',
          clearFilters: () { _statusFilter = 'all'; _categoryFilter = 'all'; _priorityFilter = 'all'; _assigneeFilter = 'all'; _aiFilter = 'all'; },
          ordered: () => sortRows(_visible),
          setPage: (p) => _page = p);
    } catch (e) {
      await _loadFromCache(liveError: friendlyError(e));
    }
  }

  /// Shows the last cached rows; shows an error only if nothing is cached.
  Future<void> _loadFromCache({String? liveError}) async {
    final cached = await OfflineRepository.instance.cachedRows(_cacheKey);
    if (!mounted) return;
    setState(() {
      _rows = cached;
      _offlineData = true;
      _loading = false;
      _error = cached.isEmpty ? (liveError ?? 'Offline, and nothing cached yet.') : null;
    });
  }

  int _count(String status) => _rows.where((c) => c['status'] == status).length;

  /// Columns: 0 ID · 1 Resident · 2 Subject · 3 Category · 4 Priority ·
  /// 5 Status · 6 Assigned. Priority and status use the shared rankings so
  /// they sort by meaning, not alphabetically.
  @override
  Comparable<Object> sortKeyFor(Map<String, dynamic> c, int col) {
    switch (col) {
      case 0:
        return text(c['complaint_number'] ?? c['id']);
      case 1:
        return text(_name(c['complainant'] as Map<String, dynamic>?));
      case 2:
        return text(c['subject']);
      case 3:
        return text(c['category']);
      case 4:
        return rankedKey(c['priority'], kPriorityRank);
      case 5:
        return rankedKey(c['status'], kStatusRank);
      case 6:
        // "Unassigned" sorts after named officers when ascending.
        final n = _assigneeName(c['assignee'] as Map<String, dynamic>?);
        return n == 'Unassigned' ? kSortsLast : text(n);
      default:
        return '';
    }
  }

  // Filter facets. 'all' means "no restriction" for each.
  String _categoryFilter = 'all';
  String _priorityFilter = 'all';

  /// Assignee filter: 'all', 'unassigned', or a user id as a string.
  String _assigneeFilter = 'all';

  /// 'all' or 'mismatch': complaints whose filed category the classifier
  /// disagrees with, so they may be filed under the wrong desk.
  String _aiFilter = 'all';

  int get _activeFilterCount => [
        _statusFilter,
        _categoryFilter,
        _priorityFilter,
        _assigneeFilter,
        _aiFilter,
      ].where((f) => f != 'all').length;

  void _clearFilters() => setState(() {
        _statusFilter = 'all';
        _categoryFilter = 'all';
        _priorityFilter = 'all';
        _assigneeFilter = 'all';
        _aiFilter = 'all';
      });

  /// Officers assigned to at least one loaded complaint, A-Z, for the filter.
  List<({String id, String name})> get _assigneeOptions {
    final seen = <String, String>{};
    for (final c in _rows) {
      final a = c['assignee'] as Map<String, dynamic>?;
      final id = c['assigned_to']?.toString();
      if (a != null && id != null) seen[id] = _name(a);
    }
    final list = seen.entries.map((e) => (id: e.key, name: e.value)).toList()
      ..sort((x, y) => x.name.compareTo(y.name));
    return list;
  }

  /// Whether a complaint passes every active filter.
  bool _matchesFilters(Map<String, dynamic> c) {
    // 'open' means not resolved or dismissed, as the dashboards count it.
    if (_statusFilter == 'open') {
      if (const {'resolved', 'dismissed'}.contains(c['status'])) return false;
    } else if (_statusFilter != 'all' && c['status'] != _statusFilter) {
      return false;
    }
    if (_categoryFilter != 'all' && c['category'] != _categoryFilter) return false;
    if (_priorityFilter != 'all' && c['priority'] != _priorityFilter) return false;
    if (_assigneeFilter == 'unassigned') {
      if (c['assigned_to'] != null) return false;
    } else if (_assigneeFilter != 'all') {
      if (c['assigned_to']?.toString() != _assigneeFilter) return false;
    }
    if (_aiFilter == 'mismatch' && !_hasMismatch(c)) return false;
    return true;
  }

  /// Classifier suggestions below this confidence are not shown.
  static const _kMinConfidence = 0.55;

  /// True when the classifier confidently picked a different category.
  /// A complaint it never classified is not a mismatch.
  bool _hasMismatch(Map<String, dynamic> c) {
    final suggested = c['suggested_category']?.toString();
    if (suggested == null || suggested.isEmpty) return false;
    if (suggested == c['category']?.toString()) return false;
    final conf = num.tryParse(c['classification_confidence']?.toString() ?? '');
    return conf != null && conf >= _kMinConfidence;
  }

  int get _mismatchCount => _rows.where(_hasMismatch).length;

  List<Map<String, dynamic>> get _visible {
    final list = _rows.where(_matchesFilters).toList();
    return sortRows(list);
  }

  /// Opens the filter panel; its label shows how many filters are active.
  Widget _filterButton() {
    final n = _activeFilterCount;
    return OutlinedButton.icon(
      onPressed: _openFilterPanel,
      icon: const Icon(Icons.filter_list, size: 16),
      label: Text(n == 0 ? 'Filter' : 'Filter · $n'),
      style: OutlinedButton.styleFrom(
        foregroundColor: n == 0 ? null : AppColors.sidebarActiveText,
        side: n == 0 ? null : BorderSide(color: AppColors.sidebarActiveText),
      ),
    );
  }

  /// Filter dialog; choices apply to the list only when Apply is pressed.
  Future<void> _openFilterPanel() async {
    // Local copies so Cancel discards the changes.
    var status = _statusFilter;
    var category = _categoryFilter;
    var priority = _priorityFilter;
    var assignee = _assigneeFilter;
    var ai = _aiFilter;

    final applied = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          Widget field(String label, String value, List<(String, String)> options,
              ValueChanged<String> onChanged) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: value,
                    isDense: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: [
                      for (final o in options)
                        DropdownMenuItem(value: o.$1, child: Text(o.$2)),
                    ],
                    onChanged: (v) => setLocal(() => onChanged(v ?? 'all')),
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            title: const Text('Filter complaints'),
            content: SizedBox(
              width: dialogContentWidth(context, 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    field('STATUS', status, const [
                      ('all', 'All statuses'),
                      ('submitted', 'Submitted'),
                      ('under_review', 'Under Review'),
                      ('in_progress', 'In Progress'),
                      ('resolved', 'Resolved'),
                      ('dismissed', 'Dismissed'),
                    ], (v) => status = v),
                    field('CATEGORY', category, const [
                      ('all', 'All categories'),
                      ('noise', 'Noise'),
                      ('maintenance', 'Maintenance'),
                      ('billing', 'Billing'),
                      ('security', 'Security'),
                      ('parking', 'Parking'),
                      ('pets', 'Pets'),
                      ('sanitation', 'Sanitation'),
                      ('common_area', 'Common Area'),
                      ('neighbor_dispute', 'Neighbor Dispute'),
                      ('other', 'Other'),
                    ], (v) => category = v),
                    field('PRIORITY', priority, const [
                      ('all', 'All priorities'),
                      ('urgent', 'Urgent'),
                      ('high', 'High'),
                      ('medium', 'Medium'),
                      ('low', 'Low'),
                    ], (v) => priority = v),
                    field('ASSIGNED TO', assignee, [
                      const ('all', 'Anyone'),
                      const ('unassigned', 'Unassigned'),
                      for (final a in _assigneeOptions) (a.id, a.name),
                    ], (v) => assignee = v),
                    field('AUTO-CLASSIFIER', ai, [
                      const ('all', 'Everything'),
                      ('mismatch', 'Category disputed ($_mismatchCount)'),
                    ], (v) => ai = v),
                  ],
                ),
              ),
            ),
            // Clear all on the left, Cancel/Apply on the right.
            // Never put a Spacer in actions: it crashes the dialog (grey box).
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () {
                  setLocal(() {
                    status = category = priority = assignee = ai = 'all';
                  });
                },
                child: const Text('Clear all'),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Apply')),
                ],
              ),
            ],
          );
        },
      ),
    );

    if (applied == true) {
      setState(() {
        _statusFilter = status;
        _categoryFilter = category;
        _priorityFilter = priority;
        _assigneeFilter = assignee;
        _aiFilter = ai;
      });
    }
  }

  /// Removable chips showing the active filters, plus Clear all.
  Widget _activeFilterChips() {
    if (_activeFilterCount == 0) return const SizedBox.shrink();

    String assigneeLabel() {
      if (_assigneeFilter == 'unassigned') return 'Unassigned';
      final match = _assigneeOptions.where((a) => a.id == _assigneeFilter);
      return match.isEmpty ? 'Assignee' : match.first.name;
    }

    final chips = <(String, VoidCallback)>[
      if (_statusFilter != 'all')
        (titleCase(_statusFilter), () => setState(() => _statusFilter = 'all')),
      if (_categoryFilter != 'all')
        (titleCase(_categoryFilter), () => setState(() => _categoryFilter = 'all')),
      if (_priorityFilter != 'all')
        (titleCase(_priorityFilter), () => setState(() => _priorityFilter = 'all')),
      if (_assigneeFilter != 'all')
        (assigneeLabel(), () => setState(() => _assigneeFilter = 'all')),
      if (_aiFilter != 'all')
        ('Category disputed', () => setState(() => _aiFilter = 'all')),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final c in chips)
            InputChip(
              label: Text(c.$1, style: const TextStyle(fontSize: 12)),
              onDeleted: c.$2,
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.badgeGreenBg,
              side: BorderSide.none,
            ),
          TextButton(
            onPressed: _clearFilters,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('Clear all', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// The filed category, plus the classifier's suggestion when they differ.
  Widget _categoryCell(Map<String, dynamic> c) {
    if (!_hasMismatch(c)) return StatusBadge((c['category'] ?? '').toString());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusBadge((c['category'] ?? '').toString()),
        const SizedBox(width: 6),
        _suggestionChip(c),
      ],
    );
  }

  /// Amber chip with the classifier's category; tap to refile under it.
  Widget _suggestionChip(Map<String, dynamic> c) {
    final suggested = (c['suggested_category'] ?? '').toString();
    final conf = num.tryParse(c['classification_confidence']?.toString() ?? '');
    return Tooltip(
      message: 'The auto-classifier read this as "${titleCase(suggested)}"'
          '${conf == null ? '' : ' (${(conf * 100).round()}% confident)'}.'
          '\nTap to refile it under that category.',
      child: InkWell(
        onTap: _canReclassify ? () => _applySuggestion(c) : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.badgeAmberBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.badgeAmberText.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.auto_awesome, size: 11, color: AppColors.badgeAmberText),
            const SizedBox(width: 4),
            Text(titleCase(suggested),
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.badgeAmberText)),
          ]),
        ),
      ),
    );
  }

  /// Asks first, then refiles the complaint under the classifier's category.
  /// The category decides which officers may be assigned (concern_routing.dart).
  Future<void> _applySuggestion(Map<String, dynamic> c) async {
    final suggested = (c['suggested_category'] ?? '').toString();
    final current = (c['category'] ?? '').toString();
    if (suggested.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refile this complaint?'),
        content: SizedBox(
          width: dialogContentWidth(context, 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"${c['subject'] ?? ''}"',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              Text(
                  'Filed by the resident as ${titleCase(current)}.\n'
                  'The auto-classifier read the description as '
                  '${titleCase(suggested)}.',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary, height: 1.45)),
              const SizedBox(height: 12),
              const Text(
                  'Refiling changes which officers can be assigned to it. '
                  'Any current assignee stays put — reassign separately if '
                  'the concern now belongs to a different desk.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep as filed')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Refile as ${titleCase(suggested)}')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await SupabaseService.instance.client
          .from('complaints')
          .update({'category': suggested}).eq('id', c['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refiled as ${titleCase(suggested)}.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refile. ${friendlyError(e)}')));
    }
  }

  /// Opens the shared form: new complaint, or edit when [initial] is given.
  Future<void> _openForm([Map<String, dynamic>? initial]) async {
    final saved = await showModuleFormDialog(context, complaints, initial: initial);
    if (saved == true) _load();
  }

  String _name(Map<String, dynamic>? p) {
    if (p == null) return '—';
    return [p['first_name'], p['last_name']].where((s) => s != null && s.toString().isNotEmpty).join(' ');
  }

  /// Same as [_name] but reads "Unassigned" instead of a dash.
  String _assigneeName(Map<String, dynamic>? assignee) {
    final n = _name(assignee);
    return n == '—' ? 'Unassigned' : n;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    return Column(
      children: [
        if (_offlineData) _offlineBanner(),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            return constraints.maxWidth < 700 ? _mobileBody() : _desktopBody();
          }),
        ),
      ],
    );
  }

  Widget _offlineBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFBEFD6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Text(
        "Offline — showing the last synced data. New complaints will send once you're back online.",
        style: TextStyle(fontSize: 12, color: Color(0xFF8A6300)),
      ),
    );
  }

  Widget _desktopBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('All complaints',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              const Spacer(),
              _filterButton(),
              const SizedBox(width: 10),
              if (_canCreate) FilledButton(onPressed: () => _openForm(), child: const Text('New Complaint')),
            ],
          ),
          _activeFilterChips(),
          const SizedBox(height: 18),
          responsiveStatCards((w) => [
            DashboardStatCard(icon: Icons.mark_email_unread_outlined, iconBg: const Color(0xFFE2F0F7), label: 'Submitted', value: '${_count('submitted')}', width: w, selected: _statusFilter == 'submitted', onTap: () => _tapStatus('submitted')),
            DashboardStatCard(icon: Icons.rate_review_outlined, iconBg: const Color(0xFFFBEFD6), label: 'Under Review', value: '${_count('under_review')}', width: w, selected: _statusFilter == 'under_review', onTap: () => _tapStatus('under_review')),
            DashboardStatCard(icon: Icons.hourglass_top_outlined, iconBg: const Color(0xFFE2F0F7), label: 'In Progress', value: '${_count('in_progress')}', width: w, selected: _statusFilter == 'in_progress', onTap: () => _tapStatus('in_progress')),
            DashboardStatCard(icon: Icons.check_circle_outline, iconBg: const Color(0xFFE3F1E9), label: 'Resolved', value: '${_count('resolved')}', width: w, selected: _statusFilter == 'resolved', onTap: () => _tapStatus('resolved')),
            DashboardStatCard(icon: Icons.block_outlined, iconBg: const Color(0xFFFBE4E4), label: 'Dismissed', value: '${_count('dismissed')}', width: w, selected: _statusFilter == 'dismissed', onTap: () => _tapStatus('dismissed')),
          ]),
          const SizedBox(height: 20),
          Expanded(child: _buildTable()),
        ],
      ),
    );
  }

  // ---------- mobile body ----------
  Widget _mobileBody() {
    final rows = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              // Total, or "N of total" while a filter is on.
              Text(
                _activeFilterCount == 0
                    ? '${_rows.length} complaints'
                    : '${rows.length} of ${_rows.length}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted),
              ),
              const Spacer(),
              // Filter icon with a badge counting the active filters.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: _openFilterPanel,
                    icon: const Icon(Icons.filter_list, size: 20, color: AppColors.textSecondary),
                    tooltip: 'Filter',
                  ),
                  if (_activeFilterCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        // Not const: sidebarActiveText is a runtime getter.
                        decoration: BoxDecoration(
                            color: AppColors.sidebarActiveText, shape: BoxShape.circle),
                        child: Text('$_activeFilterCount',
                            style: const TextStyle(
                                fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
              if (_canCreate)
                FilledButton(
                  onPressed: () => _openForm(),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                  child: const Text('+ Complaint', style: TextStyle(fontSize: 12.5)),
                ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('No complaints yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: pageSlice(pinFocused(rows), _page).length + (pageCountFor(rows.length) > 1 ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= pageSlice(pinFocused(rows), _page).length) {
                      return pagerFor(rows.length, _page, (p) => setState(() => _page = p));
                    }
                    final c = pageSlice(pinFocused(rows), _page)[i];
                    return InkWell(
                      onTap: () => _openForm(c),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isFocusedRow(c) ? kFocusRowColor : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((c['subject'] ?? '—').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  const SizedBox(height: 3),
                                  Text('#${c['complaint_number'] ?? c['id']} · ${_name(c['complainant'] as Map<String, dynamic>?)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  const SizedBox(height: 3),
                                  Text(
                                      '${titleCase((c['category'] ?? '').toString())} · ${titleCase((c['priority'] ?? '').toString())} · '
                                      'Assigned: ${_assigneeName(c['assignee'] as Map<String, dynamic>?)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  if (_hasMismatch(c)) ...[
                                    const SizedBox(height: 5),
                                    _suggestionChip(c),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusBadge((c['status'] ?? '').toString()),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    final rows = _visible;
    if (rows.isEmpty) {
      return const Center(child: Text('No complaints yet.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)));
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: fullWidthTable(
            footer: pagerFor(rows.length, _page, (p) => setState(() => _page = p)),
            
        DataTable(
                showCheckboxColumn: false,
                headingRowHeight: 40,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 56,
                sortColumnIndex: sortColumn,
                sortAscending: sortAsc,
                columnSpacing: 28,
                headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                dataTextStyle: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                columns: [
                  DataColumn(label: const Text('ID'), onSort: onSort),
                  DataColumn(label: const Text('RESIDENT'), onSort: onSort),
                  DataColumn(label: const Text('SUBJECT'), onSort: onSort),
                  DataColumn(label: const Text('CATEGORY'), onSort: onSort),
                  DataColumn(label: const Text('PRIORITY'), onSort: onSort),
                  DataColumn(label: const Text('STATUS'), onSort: onSort),
                  DataColumn(label: const Text('ASSIGNED'), onSort: onSort),
                ],
                rows: [
                  for (final c in pageSlice(pinFocused(rows), _page))
                    DataRow(
                      color: focusRowColor(c),
                      onSelectChanged: (_) => _openForm(c),
                      cells: [
                        DataCell(Text('#${c['complaint_number'] ?? c['id']}')),
                        DataCell(Text(_name(c['complainant'] as Map<String, dynamic>?))),
                        DataCell(ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text((c['subject'] ?? '—').toString(),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                        DataCell(_categoryCell(c)),
                        DataCell(StatusBadge((c['priority'] ?? '').toString())),
                        DataCell(StatusBadge((c['status'] ?? '').toString())),
                        DataCell(Text(_assigneeName(c['assignee'] as Map<String, dynamic>?))),
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}
