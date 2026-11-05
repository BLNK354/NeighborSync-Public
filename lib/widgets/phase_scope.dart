import 'package:flutter/material.dart';
import '../core/address_sort.dart';
import '../core/form_helpers.dart';
import '../core/refresh_bus.dart';
import '../services/supabase_service.dart';
import '../core/safe_state.dart';

/// '4A' -> '4'. Must match `phase_number_of()` in the database.
String phaseNumberOf(String code) {
  final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? code : digits;
}


/// Shows the phase being viewed: a label for a phase officer, a switcher
/// for super_admin. Used by both the desktop and mobile shells.
class PhaseScopeControl extends StatefulWidget {
  /// Text colour, so it suits a dark sidebar or a white top bar.
  final Color color;
  final double fontSize;

  /// Text for an officer with no phase (super_admin always gets the switcher).
  final String? fallbackLabel;

  /// True renders "<fallback> · Phase 4"; false renders just "Phase 4".
  final bool prefixFallback;

  const PhaseScopeControl({
    super.key,
    required this.color,
    this.fontSize = 10,
    this.fallbackLabel,
    this.prefixFallback = false,
  });

  @override
  State<PhaseScopeControl> createState() => _PhaseScopeControlState();
}

class _PhaseScopeControlState extends State<PhaseScopeControl> with SafeSetState<PhaseScopeControl> {
  /// "Phase 4" for a phase officer, null for anyone with no phase set.
  String? _phaseLabel;

  /// super_admin only: all phases, and the one being viewed (null = all).
  List<Map<String, dynamic>> _phases = const [];
  String? _viewingPhase;

  bool get _isSuperAdmin => SupabaseService.cachedRole == 'super_admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads the user's phase (and the phase list for super_admin).
  Future<void> _load() async {
    try {
      final uid = SupabaseService.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await SupabaseService.instance.client
          .from('users')
          .select('phase, viewing_phase')
          .eq('supabase_uid', uid)
          .maybeSingle();
      if (!mounted || row == null) return;

      if (_isSuperAdmin) {
        final phases = await SupabaseService.instance.client
            .from('phases')
            .select('code, number')
            .eq('is_active', true)
            .order('code');
        if (!mounted) return;
        setState(() {
          // One entry per phase number; the stored value must be a real
          // `phases.code` (`users.viewing_phase` references it).
          final byNumber = <String, Map<String, dynamic>>{};
          for (final p in List<Map<String, dynamic>>.from(phases)) {
            final n = (p['number'] ?? '').toString().trim();
            byNumber.putIfAbsent(n, () => p);
          }
          _phases = byNumber.values.toList()
            ..sort((a, b) => compareNatural((a['number'] ?? '').toString(),
                (b['number'] ?? '').toString()));
          _viewingPhase = (row['viewing_phase'] as String?)?.trim();
          if (_viewingPhase?.isEmpty ?? false) _viewingPhase = null;
        });
        return;
      }

      final code = (row['phase'] ?? '').toString().trim();
      if (code.isNotEmpty) {
        setState(() => _phaseLabel = 'Phase ${phaseNumberOf(code)}');
      }
    } catch (_) {
      // Label is cosmetic; never block the shell on it.
    }
  }

  /// Narrows every screen to one phase (null = all phases) by saving
  /// `viewing_phase`, then reloads the current screen.
  /// Needs the `users` policy clause `supabase_uid = auth.uid()`, or
  /// switching breaks.
  Future<void> _setViewingPhase(String? code) async {
    final uid = SupabaseService.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _viewingPhase = code);
    try {
      await SupabaseService.instance.client
          .from('users')
          .update({'viewing_phase': code}).eq('supabase_uid', uid);
      await RefreshBus.run();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not change phase. ${friendlyError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w600,
      color: widget.color,
    );

    if (_isSuperAdmin) {
      final label = _viewingPhase == null
          ? 'All phases'
          : 'Phase ${phaseNumberOf(_viewingPhase!)}';
      // A popup menu, because a dropdown clashes with the dark sidebar.
      return PopupMenuButton<String?>(
        tooltip: 'Choose which phase to view',
        // Default padding overflows the 72px mobile top bar.
        padding: EdgeInsets.zero,
        onSelected: (v) => _setViewingPhase(v == '' ? null : v),
        itemBuilder: (context) => [
          const PopupMenuItem<String?>(value: '', child: Text('All phases')),
          const PopupMenuDivider(),
          for (final p in _phases)
            PopupMenuItem<String?>(
              value: p['code'] as String,
              // Number only; divisions of a phase show the same rows.
              child: Text('Phase ${phaseNumberOf((p['code'] ?? '').toString())}'),
            ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text('Viewing: $label',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
            Icon(Icons.expand_more, size: widget.fontSize + 3, color: widget.color),
          ],
        ),
      );
    }

    // Phase officers: show which phase they govern.
    final fallback = widget.fallbackLabel;
    final String text;
    if (_phaseLabel == null) {
      if (fallback == null) return const SizedBox.shrink();
      text = fallback;
    } else {
      text = (fallback != null && widget.prefixFallback)
          ? '$fallback · $_phaseLabel'
          : _phaseLabel!;
    }
    return Text(text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(fontWeight: FontWeight.w500));
  }
}
