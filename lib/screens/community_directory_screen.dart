import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/address_sort.dart';
import '../core/form_helpers.dart';
import '../core/branding.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/permissions.dart';
import '../core/text_utils.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/resident_theme.dart';
import '../widgets/admin_shell.dart';
import '../widgets/member_shell.dart';
import '../widgets/module_form_dialog.dart';
import '../widgets/map_pin.dart';
import '../widgets/responsive_bits.dart';
import '../widgets/status_badge.dart';
import '../core/module_registry.dart' show lots;
import '../core/refresh_bus.dart';
import '../core/dialog_sizing.dart';
import '../core/safe_state.dart';

/// Officer view of the Community Map and the lot directory.
class AdminCommunityScreen extends StatelessWidget {
  const AdminCommunityScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const AdminShell(
      title: 'Community Map',
      activeItem: 'Community Map',
      child: _CommunityBody(officer: true),
    );
  }
}

/// Resident view of the Community Map; shows only their own address.
class MemberCommunityScreen extends StatelessWidget {
  const MemberCommunityScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const MemberShell(
      title: 'Community Map',
      activeItem: 'Community Map',
      child: _CommunityBody(officer: false),
    );
  }
}

/// The map, plus the Locations list and Blocks & Lots directory for officers.
/// The map is a picture (site plan or aerial photo) with pins, not a GPS map.
/// Pins (`lots.map_x`/`map_y`) are 0-1 fractions of the picture they were
/// placed on, so they only make sense on that picture.
class _CommunityBody extends StatefulWidget {
  final bool officer;
  const _CommunityBody({required this.officer});

  @override
  State<_CommunityBody> createState() => _CommunityBodyState();
}

class _CommunityBodyState extends State<_CommunityBody> with SafeSetState<_CommunityBody> {
  List<Map<String, dynamic>> _blocks = [];

  /// True groups the lot list by status; false groups it by block.
  bool _groupByStatus = true;
  List<Map<String, dynamic>> _lots = [];
  Map<int, List<Map<String, dynamic>>> _lotsByBlock = {};
  Map<int, String> _blockNames = {};
  Map<String, Set<String>> _perms = {};
  bool _loading = true;
  String? _error;

  /// The signed-in resident's approved lot; residents see only their own pin.
  /// Null for officers (they see every lot) and for anyone with no approved
  /// address.
  int? _myLotId;
  // A pending resident's claimed (not yet approved) address.
  int? _myClaimedLotId;

  /// Phase numbers whose blocks are visible, and the one the map is showing.
  /// Only one phase is drawn at a time, because each has its own site plan.
  List<String> _phaseOptions = const [];
  String? _mapPhase;

  /// Turns '4A' into '4'. Must match `phase_number_of()` in the database,
  /// which the phase policies compare on.
  static String _numberOfPhase(String code) {
    final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? code : digits;
  }
  String? _mapImageUrl;

  // Placement mode: the next tap on the map picture sets a pin. Null
  // _placementLotId means the tap will create a brand-new address;
  // otherwise it moves that existing lot's pin.
  bool _placementMode = false;
  int? _placementLotId;

  // Adjust mode: pins can be dragged to re-align them. Zoom and pan are off
  // while it is on, because the map would otherwise take the drag.
  bool _adjustMode = false;
  int? _dragLotId;

  /// Live tip position of the pin being dragged, in map-box pixels. Null
  /// when nothing is being dragged; the stored coordinate is used then.
  Offset? _dragTip;

  /// Converts a pin tip in map-box pixels to the stored 0-1 coordinate.
  /// Must stay the exact inverse of the drawing maths (`x * (W - pin) + pin/2`),
  /// or pins save to a different spot than where they were dropped.
  Offset _tipToFraction(Offset tip, BoxConstraints c, double pin) {
    final w = (c.maxWidth - pin);
    final h = (c.maxHeight - pin);
    return Offset(
      w <= 0 ? 0 : ((tip.dx - pin / 2) / w).clamp(0.0, 1.0),
      h <= 0 ? 0 : ((tip.dy - pin / 2) / h).clamp(0.0, 1.0),
    );
  }

  // Shared by pinch/scroll zoom and the +/- and reset buttons.
  final TransformationController _mapTransform = TransformationController();

  /// Width / height of the site plan, once it has loaded.
  /// The map box takes this shape. Pins are fractions of the box, so a box
  /// shaped differently from the picture puts every pin in the wrong spot.
  double? _mapAspect;
  String? _mapAspectFor;
  ImageStream? _mapStream;
  ImageStreamListener? _mapStreamListener;

  double get _mapScale => _mapTransform.value.getMaxScaleOnAxis();

  /// Reads the plan's real proportions when the map picture changes.
  void _resolveMapAspect() {
    final url = _mapImageUrl;
    if (url == _mapAspectFor) return;
    _mapAspectFor = url;
    _detachMapStream();
    // A new picture starts zoomed out. Deferred because this runs during
    // build and the controller notifies the AnimatedBuilder drawing the map.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _mapScale > 1.0) _mapTransform.value = Matrix4.identity();
    });
    if (url == null) {
      _setMapAspect(null);
      return;
    }
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      final a = info.image.width / info.image.height;
      if (a <= 0 || !a.isFinite) return;
      _setMapAspect(a);
    }, onError: (_, __) {
      // A plan that will not load falls back to the landscape box rather
      // than leaving the card collapsed.
      _setMapAspect(null);
    });
    _mapStream = stream;
    _mapStreamListener = listener;
    stream.addListener(listener);
  }

  /// Stores the plan's shape after the current frame.
  /// Must stay deferred: a cached image calls back during build, and a plain
  /// `setState` there throws "setState() called during build".
  void _setMapAspect(double? a) {
    if (!mounted || _mapAspect == a) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mapAspect == a) return;
      setState(() => _mapAspect = a);
    });
  }

  void _detachMapStream() {
    if (_mapStream != null && _mapStreamListener != null) {
      _mapStream!.removeListener(_mapStreamListener!);
    }
    _mapStream = null;
    _mapStreamListener = null;
  }

  /// Multiplies the zoom by [factor], kept between 1x and 5x.
  void _zoomMap(double factor) {
    final next = (_mapScale * factor).clamp(1.0, 5.0);
    // Reset to identity first, then scale, so the zoom stays centered and
    // predictable regardless of the current pan offset.
    if (next <= 1.0) {
      _mapTransform.value = Matrix4.identity();
    } else {
      _mapTransform.value = Matrix4.identity()..scaleByDouble(next, next, next, 1.0);
    }
    setState(() {});
  }

  Color get _textPrimary =>
      widget.officer ? AppColors.textPrimary : ResidentColors.textPrimary;
  Color get _textSecondary =>
      widget.officer ? AppColors.textSecondary : ResidentColors.textSecondary;
  Color get _border => widget.officer ? AppColors.border : ResidentColors.border;

  bool get _canManage =>
      widget.officer && canPerform(_perms, 'lots', 'update');

  @override
  void initState() {
    super.initState();
    RefreshBus.bind(this, _load);
    _load();
  }

  @override
  void dispose() {
    _detachMapStream();
    _mapTransform.dispose();
    super.dispose();
  }

  /// Loads blocks, lots, permissions and the viewer's address, then works out
  /// which phase's map picture to show.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Explicit <dynamic> so Future.wait accepts these differently-typed
      // futures together.
      final results = await Future.wait<dynamic>([
        SupabaseService.instance.client
            .from('blocks')
            .select('id, block_name, phase, description')
            .order('block_name'),
        SupabaseService.instance.client
            .from('lots')
            // `phase` is needed so only the selected phase's pins are drawn.
            .select('id, lot_number, block_id, street_address, lot_type, status, map_x, map_y, '
                'phase')
            .order('lot_number'),
        widget.officer
            ? SupabaseService.instance.getMyPermissions()
            : Future.value(<String, Set<String>>{}),
        SupabaseService.instance.client
            .from('system_settings')
            .select('value')
            .eq('setting_key', 'community.map_image_url')
            .maybeSingle(),
        // The viewer's lot (members) and their phase or viewed phase
        // (officers, for when no blocks exist yet to name the phase).
        SupabaseService.instance.client
              .from('users')
              // requested_lot_id: a resident awaiting approval has no lot_id
              // yet, so their claimed address decides which map they see.
              .select('lot_id, requested_lot_id, phase, viewing_phase')
              .eq('supabase_uid',
                  SupabaseService.instance.client.auth.currentUser?.id ?? '')
              .maybeSingle(),
      ]);
      if (!mounted) return;
      final blockRows = List<Map<String, dynamic>>.from(results[0] as List);
      final lots = List<Map<String, dynamic>>.from(results[1] as List);
      final grouped = <int, List<Map<String, dynamic>>>{};
      final names = <int, String>{};
      for (final b in blockRows) {
        names[b['id'] as int] = (b['block_name'] ?? '').toString();
      }
      for (final lot in lots) {
        final blockId = lot['block_id'] as int?;
        if (blockId == null) continue;
        grouped.putIfAbsent(blockId, () => []).add(lot);
      }
      // Lot numbers are text, so the query puts "9" after "10". Sort them
      // naturally inside each block.
      for (final list in grouped.values) {
        list.sort((a, b) => compareNatural(
            (a['lot_number'] ?? '').toString(), (b['lot_number'] ?? '').toString()));
      }
      lots.sort((a, b) => compareAddress(
          a['phase'], names[a['block_id']], a['lot_number'],
          b['phase'], names[b['block_id']], b['lot_number']));
      final mapSetting = results[3] as Map<String, dynamic>?;
      var mapUrl = mapSetting?['value'] as String?;

      // Each phase has its own map picture. The phase comes from the blocks
      // RLS lets the viewer see, which also follows the phase switcher.
      // With several phase numbers in view the screen shows one tab per
      // number; divisions of one number (1A, 1B) share a tab.
      final visibleCodes = <String>{
        for (final b in blockRows)
          if ((b['phase'] ?? '').toString().trim().isNotEmpty)
            (b['phase'] as String).trim()
      };
      // number -> the first code seen for it, which is what
      // map_image_for_phase() wants.
      final byNumber = <String, String>{};
      for (final c in visibleCodes) {
        byNumber.putIfAbsent(_numberOfPhase(c), () => c);
      }
      final options = byNumber.keys.toList()..sort(compareNatural);

      // A member's map comes from their own address, approved or claimed.
      // Never use the lowest phase in view: someone with no phase can see
      // every phase's blocks, so that would show the wrong plan.
      final me = results[4] as Map<String, dynamic>?;
      final myLot = widget.officer ? null : me?['lot_id'] as int?;
      final myClaim = widget.officer ? null : me?['requested_lot_id'] as int?;
      String? memberPhaseCode;
      if (!widget.officer) {
        final homeId = myLot ?? myClaim;
        for (final l in lots) {
          if (l['id'] == homeId) {
            final p = (l['phase'] ?? '').toString().trim();
            if (p.isNotEmpty) memberPhaseCode = p;
            break;
          }
        }
      }

      String? selected;
      if (!widget.officer) {
        if (memberPhaseCode != null) {
          selected = _numberOfPhase(memberPhaseCode);
          byNumber[selected] = memberPhaseCode;
        }
      } else {
        // Keep the officer's current choice across a refresh; otherwise
        // start on the lowest-numbered phase.
        selected = _mapPhase;
        if (selected == null || !options.contains(selected)) {
          selected = options.isEmpty ? null : options.first;
        }
        // No blocks in view: use the viewer's own or viewed phase. Without
        // this, a phase with no map shows the subdivision-wide picture,
        // which is another phase's plan.
        if (options.isEmpty) {
          final code = ((me?['viewing_phase'] ?? me?['phase']) ?? '')
              .toString()
              .trim();
          if (code.isNotEmpty) {
            selected = _numberOfPhase(code);
            byNumber[selected] = code;
          } else {
            mapUrl = null; // All phases, nothing to anchor a map to.
          }
        }
      }
      if (!widget.officer && selected == null && options.length != 1) {
        // The global picture belongs to one phase; with several in view it
        // would be someone else's plan.
        mapUrl = null;
      }

      if (selected != null) {
        try {
          final resolved = await SupabaseService.instance.client.rpc(
              'map_image_for_phase',
              params: {'p_phase': byNumber[selected]});
          // Null is a real answer -- a phase with no plan of its own must
          // show the "no map" state rather than a neighbour's picture.
          mapUrl = (resolved is String && resolved.isNotEmpty) ? resolved : null;
        } catch (_) {
          // Leave whatever the global setting gave us.
        }
      }
      if (!mounted) return;
      setState(() {
        _phaseOptions = options;
        _mapPhase = selected;
        _blocks = blockRows;
        _lots = lots;
        _lotsByBlock = grouped;
        _blockNames = names;
        _perms = results[2] as Map<String, Set<String>>;
        _myLotId = myLot;
        _myClaimedLotId = myClaim;
        _mapImageUrl = (mapUrl == null || mapUrl.isEmpty) ? null : mapUrl;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  // ---------- Add Address / pin placement ----------

  /// Starts "Add Address": the next tap on the map sets the new lot's pin.
  void _startAddAddress() {
    if (_mapImageUrl == null) {
      // No picture to tap yet -- create the address without a pin. It can
      // be pinned later from its detail view once a picture is uploaded.
      _openAddressForm(mapX: null, mapY: null);
      return;
    }
    setState(() {
      _placementMode = true;
      _placementLotId = null;
    });
  }

  /// Turns draggable-pin mode on or off. Needs a map picture.
  void _toggleAdjustMode() {
    if (_mapImageUrl == null) {
      _snack('Upload a map picture first before adjusting pins.', error: true);
      return;
    }
    setState(() {
      _adjustMode = !_adjustMode;
      _dragLotId = null;
      _dragTip = null;
      // Pins are dragged at 1x; a zoomed map would throw off the drag maths.
      if (_adjustMode) _mapTransform.value = Matrix4.identity();
    });
  }

  /// Saves a dragged pin's new position when the drag ends.
  Future<void> _commitPinDrag(int lotId, BoxConstraints constraints) async {
    final tip = _dragTip;
    setState(() {
      _dragLotId = null;
      _dragTip = null;
    });
    if (tip == null) return;
    final f = _tipToFraction(tip, constraints, AppBranding.instance.pinSize);
    try {
      await SupabaseService.instance.client
          .from('lots')
          .update({'map_x': f.dx, 'map_y': f.dy}).eq('id', lotId);
      _load();
    } catch (e) {
      _snack('Could not save pin position. ${friendlyError(e)}', error: true);
      // Reload so the pin snaps back to its stored spot rather than
      // sitting where it was dropped but never saved.
      _load();
    }
  }

  /// Starts moving [lot]'s pin: the next tap on the map sets its position.
  void _startMovePin(Map<String, dynamic> lot) {
    if (_mapImageUrl == null) {
      _snack('Upload a map picture first before placing pins.', error: true);
      return;
    }
    setState(() {
      _placementMode = true;
      _placementLotId = lot['id'] as int;
    });
  }

  void _skipPinForNewAddress() {
    setState(() {
      _placementMode = false;
      _placementLotId = null;
    });
    _openAddressForm(mapX: null, mapY: null);
  }

  void _cancelPlacement() {
    setState(() {
      _placementMode = false;
      _placementLotId = null;
    });
  }

  /// Handles a tap in placement mode: moves the chosen lot's pin, or opens the
  /// new-address form with the tapped position.
  Future<void> _handleMapTap(TapUpDetails details, BoxConstraints constraints) async {
    // Must use the same conversion as dragging, so the pin lands where tapped.
    final f = _tipToFraction(
        details.localPosition, constraints, AppBranding.instance.pinSize);
    final fx = f.dx;
    final fy = f.dy;
    final movingLotId = _placementLotId;
    setState(() {
      _placementMode = false;
      _placementLotId = null;
    });
    if (movingLotId == null) {
      _openAddressForm(mapX: fx, mapY: fy);
      return;
    }
    try {
      await SupabaseService.instance.client
          .from('lots')
          .update({'map_x': fx, 'map_y': fy}).eq('id', movingLotId);
      _snack('Pin placed.');
      _load();
    } catch (e) {
      _snack('Could not save pin position. ${friendlyError(e)}', error: true);
    }
  }

  /// Opens the Add Address form and reloads the map if a lot was saved.
  Future<void> _openAddressForm({double? mapX, double? mapY}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddressFormDialog(
          blocks: _sortedBlocks, mapX: mapX, mapY: mapY, hasMap: _mapImageUrl != null),
    );
    if (saved == true) _load();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.redAccent : null),
    );
  }

  /// Shows a lot's details; officers who can manage lots also get pin, edit
  /// and delete actions.
  void _showLot(Map<String, dynamic> lot) {
    final blockName = _blockNames[lot['block_id']] ?? '—';
    final hasPin = lot['map_x'] != null && lot['map_y'] != null;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Lot ${lot['lot_number'] ?? ''}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Block $blockName'),
            if (lot['street_address'] != null) Text(lot['street_address'].toString()),
            const SizedBox(height: 8),
            StatusBadge((lot['status'] ?? 'owned').toString()),
            if (_canManage && _mapImageUrl != null) ...[
              const SizedBox(height: 10),
              Text(
                hasPin ? 'Pinned on the current map picture.' : 'Not pinned on the current map picture yet.',
                style: TextStyle(fontSize: 11.5, color: _textSecondary),
              ),
            ],
          ],
        ),
        actions: [
          if (_canManage && _mapImageUrl != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _startMovePin(lot);
              },
              child: Text(hasPin ? 'Move Pin' : 'Place Pin'),
            ),
          if (_canManage)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final saved = await showModuleFormDialog(context, lots, initial: lot);
                if (saved == true) _load();
              },
              child: const Text('Edit'),
            ),
          if (_canManage)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteLot(lot);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Deletes an empty block after confirming. A block that still has lots is
  /// refused with a plain message.
  Future<void> _deleteBlock(Map<String, dynamic> block, int lotCount) async {
    if (lotCount > 0) {
      _snack(
        'Block ${block['block_name']} still has $lotCount lot${lotCount == 1 ? '' : 's'} -- '
        'delete or move its lots first.',
        error: true,
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Block ${block['block_name'] ?? ''}?'),
        content: const Text('This block has no lots and will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await SupabaseService.instance.client.from('blocks').delete().eq('id', block['id']);
      _load();
    } catch (e) {
      _snack('Delete failed. ${friendlyError(e)}', error: true);
    }
  }

  /// Edits a block's name, phase and description.
  /// The phase links a person to their area (user -> lot -> block -> phase),
  /// so the resident waste-schedule filter depends on it.
  Future<void> _editBlock(Map<String, dynamic> block) async {
    final nameCtrl =
        TextEditingController(text: (block['block_name'] ?? '').toString());
    final phaseCtrl =
        TextEditingController(text: (block['phase'] ?? '').toString());
    final descCtrl =
        TextEditingController(text: (block['description'] ?? '').toString());

    String? nameError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
        title: Text('Edit Block ${block['block_name'] ?? ''}'),
        content: SizedBox(
          width: dialogContentWidth(context, 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                onChanged: (_) {
                  if (nameError != null) setLocal(() => nameError = null);
                },
                decoration: InputDecoration(
                    labelText: 'Block name',
                    errorText: nameError,
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phaseCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phase',
                  hintText: 'e.g. 3',
                  helperText: 'Leave blank if the subdivision has no phases.',
                  helperMaxLines: 3,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                maxLength: kMaxTextLength,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Text(
                  'The phase decides which waste-collection schedule the '
                  'households on this block see.',
                  style: TextStyle(fontSize: 11.5, color: _textSecondary, height: 1.4)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          // Checked here so the dialog stays open with what was typed.
          FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) {
                  setLocal(() => nameError = 'A block needs a name.');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Save')),
        ],
      )),
    );
    if (ok != true) return;

    try {
      await SupabaseService.instance.client.from('blocks').update({
        'block_name': nameCtrl.text.trim(),
        // Blank means whole subdivision. Store NULL, never '', so there is
        // only one way to say "no phase".
        'phase': phaseCtrl.text.trim().isEmpty ? null : phaseCtrl.text.trim(),
        'description':
            descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      }).eq('id', block['id']);
      if (!mounted) return;
      _snack('Block updated.');
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Could not save. ${friendlyError(e)}', error: true);
    }
  }

  /// Deletes a lot and its pin after confirming.
  Future<void> _deleteLot(Map<String, dynamic> lot) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Lot ${lot['lot_number'] ?? ''}?'),
        content: const Text('This will permanently remove this lot (and its pin) '
            'from the community map and directory.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await SupabaseService.instance.client.from('lots').delete().eq('id', lot['id']);
      _load();
    } catch (e) {
      // Usually a foreign-key refusal: other records still point at this lot.
      final msg = e.toString().contains('foreign key')
          ? 'This lot can\'t be deleted because other records (bills, complaints, '
              'gate passes, or move requests) refer to it.'
          : 'Delete failed. ${friendlyError(e)}';
      _snack(msg, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Text('Could not load the community map: $_error',
              style: TextStyle(fontSize: 12, color: _textSecondary)));
    }

    // Lots this viewer may see; vacant ones are hidden from non-officers.
    var visibleLots = _lots
        .where((l) => _statusVisible((l['status'] ?? 'owned').toString()))
        .toList();

    // A member sees only their own address. Narrow this one list, since it
    // feeds every view; filtering just the map would leak through the others.
    if (!widget.officer) {
      // Approved or claimed address. Matched against _lots because a vacant
      // claim was already filtered out of visibleLots.
      final home = _myLotId ?? _myClaimedLotId;
      visibleLots = home == null ? [] : _lots.where((l) => l['id'] == home).toList();
    }

    // With several phases in view, keep only the selected phase's lots: pins
    // are fractions of that phase's own plan and mean nothing on another's.
    if (widget.officer && _phaseOptions.length > 1 && _mapPhase != null) {
      visibleLots = visibleLots
          .where((l) =>
              _numberOfPhase((l['phase'] ?? '').toString()) == _mapPhase)
          .toList();
    }

    final located = visibleLots
        .where((l) => l['map_x'] != null && l['map_y'] != null)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_canManage)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _placementMode
                  ? _placementBanner()
                  : _adjustMode
                      ? _adjustBanner()
                      : _actionBar(),
            ),
          if (widget.officer && _phaseOptions.length > 1) ...[
            _phaseTabs(),
            const SizedBox(height: 14),
          ],
          if (widget.officer)
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 900;
                final map = _mapCard(located);
                final locations =
                    _locationsCard(located.isEmpty ? visibleLots : located);
                if (stacked) {
                  return Column(
                      children: [map, const SizedBox(height: 20), locations]);
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 7, child: map),
                      const SizedBox(width: 20),
                      SizedBox(width: 320, child: locations),
                    ],
                  ),
                );
              },
            )
          else if (_myLotId == null && _myClaimedLotId == null)
            // No address at all: there is no right map to show (which
            // phase's plan?), so say what to do instead of an empty box.
            _chooseAddressCard()
          else ...[
            // The note goes ABOVE the map so it is read first.
            _myAddressNote(visibleLots),
            const SizedBox(height: 16),
            _mapCard(located),
          ],
          // The Blocks & Lots directory is an officer tool: it enumerates
          // every household in the subdivision.
          if (widget.officer) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text(_groupByStatus ? 'All Lots by Status' : 'All Blocks & Lots',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary)),
                const Spacer(),
                _groupToggle(),
              ],
            ),
            const SizedBox(height: 12),
            if (_blocks.isEmpty)
              Text(
                _canManage
                    ? 'No blocks have been set up yet. Use "Add Address" above to get started.'
                    : 'No blocks have been set up yet.',
                style: TextStyle(fontSize: 13, color: _textSecondary),
              )
            // Keep the spreads: with a bare `for` + `if` + `else`, the `else`
            // binds to the inner `if` and both views render wrongly.
            else if (_groupByStatus)
              ...[
                for (final s in _statusOrder)
                  if ((_lotsByStatus[s] ?? const []).isNotEmpty)
                    _statusCard(s, _lotsByStatus[s]!)
              ]
            else
              ...[for (final block in _sortedBlocks) _blockCard(block)],
          ],
        ],
      ),
    );
  }

  /// One tab per phase, shown when several are in view (a super_admin on
  /// "All phases"). Picks which phase's plan the map shows.
  Widget _phaseTabs() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final n in _phaseOptions)
          ChoiceChip(
            label: Text('Phase $n'),
            selected: _mapPhase == n,
            onSelected: (_) {
              if (_mapPhase == n) return;
              setState(() => _mapPhase = n);
              // Re-runs the load so the map picture for the newly chosen
              // phase is resolved; _load() keeps the selection.
              _load();
            },
          ),
      ],
    );
  }

  /// Blocks in phase, then block-number order (natural: 9 before 10).
  List<Map<String, dynamic>> get _sortedBlocks => [..._blocks]
    ..sort((a, b) => compareAddress(
        a['phase'], a['block_name'], null, b['phase'], b['block_name'], null));

  /// Shown to a member with no address at all, approved or claimed -- in
  /// practice a new sign-up. Says what to do next and takes them there.
  Widget _chooseAddressCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.home_work_outlined, size: 22, color: _textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Choose your address to finish registering',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Before the HOA office can approve your account, pick the block and '
            'lot you live in and upload a proof of ownership or lease on your '
            'Profile. Your phase map appears here once you have chosen an address.',
            style: TextStyle(fontSize: 13, color: _textSecondary, height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.go('/me/profile'),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Go to my Profile'),
          ),
        ],
      ),
    );
  }

  /// Member view: says in words which address the pin marks, or why there
  /// is no pin.
  Widget _myAddressNote(List<Map<String, dynamic>> mine) {
    final lot = mine.isEmpty ? null : mine.first;
    final hasPin =
        lot != null && lot['map_x'] != null && lot['map_y'] != null;

    final String title;
    final String subtitle;
    if (lot == null) {
      title = 'No address linked to your account yet';
      subtitle =
          'Once the HOA office approves your address it will be marked on the map here.';
    } else {
      final block = _blockNames[lot['block_id']] ?? '';
      final street = (lot['street_address'] ?? '').toString().trim();
      final phase = (lot['phase'] ?? '').toString().trim();
      title = [
        if (phase.isNotEmpty) 'Phase ${_numberOfPhase(phase)}',
        if (block.isNotEmpty) 'Block $block',
        'Lot ${lot['lot_number'] ?? ''}',
      ].join(' · ');
      if (_myLotId == null) {
        subtitle = 'The address you chose. The HOA office still has to approve '
            'it, and you will be notified when they do.';
      } else {
        subtitle = hasPin
            ? (street.isEmpty ? 'Your home, marked on the map below.' : street)
            : 'Your address is on record, but the office has not placed it on '
                'the map yet.';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(hasPin ? Icons.place_outlined : Icons.help_outline,
              size: 20, color: _textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11.5, color: _textSecondary, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Officer buttons above the map. They wrap onto a second line on narrow
  /// screens. The map picture itself is managed from the CMS.
  Widget _actionBar() {
    return ActionButtonBar(
      children: [
        FilledButton.icon(
          onPressed: _startAddAddress,
          icon: const Icon(Icons.add_location_alt_outlined, size: 15),
          label: const Text('Add Address'),
        ),
        // Only worth offering once there is something to drag.
        if (_mapImageUrl != null &&
            _lots.any((l) => l['map_x'] != null && l['map_y'] != null))
          OutlinedButton.icon(
            onPressed: _toggleAdjustMode,
            icon: const Icon(Icons.open_with, size: 15),
            label: const Text('Adjust Pins'),
          ),
      ],
    );
  }

  /// Banner shown while pins are draggable, since a stray drag moves a real
  /// address.
  Widget _adjustBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F1E9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.open_with, size: 16, color: Color(0xFF14532D)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Drag any pin to reposition it. Each one saves when you let go. '
              'Zoom is off while adjusting.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF14532D)),
            ),
          ),
          TextButton(onPressed: _toggleAdjustMode, child: const Text('Done')),
        ],
      ),
    );
  }

  /// Banner shown while the next map tap will place a pin.
  Widget _placementBanner() {
    final isNew = _placementLotId == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBEFD6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app_outlined, size: 16, color: Color(0xFF8A6300)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isNew
                  ? 'Tap the map picture below to place the new address.'
                  : 'Tap the map picture below to place this pin.',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF8A6300)),
            ),
          ),
          if (isNew)
            TextButton(onPressed: _skipPinForNewAddress, child: const Text('Skip Pin')),
          TextButton(onPressed: _cancelPlacement, child: const Text('Cancel')),
        ],
      ),
    );
  }

  /// The map card: title, download button, the map and its zoom buttons.
  Widget _mapCard(List<Map<String, dynamic>> located) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${AppBranding.instance.communityName} - Community Map',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary)),
              ),
              // Only offered once a map picture exists.
              if (_mapImageUrl != null)
                TextButton.icon(
                  onPressed: _downloadMap,
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Download Map'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // The box takes the plan's shape so pin fractions stay valid. A tall
          // plan is capped at 78% of the window height; the box narrows to
          // keep the same shape.
          LayoutBuilder(builder: (context, outer) {
            final aspect = _mapAspect ?? 1.3;
            final maxH = MediaQuery.sizeOf(context).height * 0.78;
            var w = outer.maxWidth;
            var h = w / aspect;
            if (h > maxH) {
              h = maxH;
              w = h * aspect;
            }
            return Center(
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
              children: [
                Positioned.fill(child: _mapViewport(located)),
                // Zoom buttons, for when the page scroll swallows a pinch or
                // drag. Hidden during pin placement, which stays at 1x.
                if (!_placementMode)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _zoomButton(Icons.add, 'Zoom in', () => _zoomMap(1.4)),
                        const SizedBox(height: 6),
                        _zoomButton(Icons.remove, 'Zoom out', () => _zoomMap(1 / 1.4)),
                        if (_mapScale > 1.01) ...[
                          const SizedBox(height: 6),
                          _zoomButton(Icons.center_focus_strong_outlined, 'Reset', () => _zoomMap(0)),
                        ],
                      ],
                    ),
                  ),
              ],
                ),
              ),
            );
          }),
          // Hidden while adjusting -- zoom is off in that mode, so the
          // buttons would do nothing.
          if (!_placementMode && !_adjustMode && _mapImageUrl != null) ...[
            const SizedBox(height: 6),
            Text(
              'Use + / − to zoom, or pinch / scroll · drag to pan',
              style: TextStyle(fontSize: 11, color: _textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _zoomButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: _textPrimary),
          ),
        ),
      ),
    );
  }

  /// The map picture and its pins, set up for the current mode: normal
  /// (zoomable), adjust (draggable pins) or placement (tap to place).
  Widget _mapViewport(List<Map<String, dynamic>> located) {
    // Picks up a map that was just uploaded or a phase that was just
    // switched; no-ops when the URL has not changed.
    _resolveMapAspect();
    return LayoutBuilder(
              builder: (context, constraints) {
                // One pin size on every device and at every zoom level.
                final effPin = AppBranding.instance.pinSize;
                // A picture in a BoxDecoration is invisible to screen readers,
                // so the map needs this label.
                final mapLabel = _mapImageUrl == null
                    ? 'Schematic community map. No survey plan has been uploaded yet.'
                    // _mapPhase already holds the phase number, not the code.
                    : 'Community survey plan'
                        '${_mapPhase == null ? '' : ' for Phase $_mapPhase'}'
                        '. Lot positions are marked on it.';
                // The label lives inside buildBox so all three callers get it.
                // The pins stay individually reachable by screen readers.
                Widget buildBox(double drawPin) => Semantics(
                  image: true,
                  label: mapLabel,
                  child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2EC),
                    borderRadius: BorderRadius.circular(10),
                    image: _mapImageUrl == null
                        ? null
                        // contain, not cover: the whole sheet stays visible
                        // even before the plan's real shape has loaded.
                        : DecorationImage(image: NetworkImage(_mapImageUrl!), fit: BoxFit.contain),
                  ),
                  child: Stack(
                    children: [
                      // Crosshair lines, only on the plain background with no
                      // map picture.
                      if (_mapImageUrl == null) ...[
                        Positioned(
                          left: constraints.maxWidth / 2 - 1,
                          top: 0,
                          bottom: 0,
                          child: Container(width: 2, color: const Color(0xFFD7E6DC)),
                        ),
                        Positioned(
                          top: constraints.maxHeight / 2 - 1,
                          left: 0,
                          right: 0,
                          child: Container(height: 2, color: const Color(0xFFD7E6DC)),
                        ),
                      ],
                      if (located.isEmpty && !_placementMode)
                        Center(
                          child: Container(
                            margin: const EdgeInsets.all(24),
                            padding: const EdgeInsets.all(16),
                            // Keeps the text readable over a map picture.
                            decoration: _mapImageUrl == null
                                ? null
                                : BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                            child: Text(
                              _mapImageUrl == null
                                  // Don't mention the CMS: most people seeing
                                  // this cannot reach it.
                                  ? 'Map under maintenance.\nThe site plan for this phase has not been uploaded yet.'
                                  : !widget.officer
                                      ? 'Your home has not been placed on the map yet.'
                                      : 'No pins yet.\nUse "Add Address" above to place your first one.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: _textSecondary, height: 1.5),
                            ),
                          ),
                        )
                      else
                        for (final lot in located)
                          () {
                            final lotId = lot['id'] as int;
                            final dragging = _dragLotId == lotId;
                            // A pin marks its spot with its tip. This maths
                            // must stay the exact inverse of _tipToFraction.
                            final tip = dragging && _dragTip != null
                                ? _dragTip!
                                : Offset(
                                    (num.parse(lot['map_x'].toString()).toDouble()) *
                                            (constraints.maxWidth - effPin) +
                                        effPin / 2,
                                    (num.parse(lot['map_y'].toString()).toDouble()) *
                                            (constraints.maxHeight - effPin) +
                                        effPin / 2,
                                  );
                            // Uses drawPin, not effPin: the tip must stay
                            // pinned to the map while the body grows and
                            // shrinks around it as you zoom.
                            final at = MapPin.offsetForTip(tip, drawPin);
                            final pin = MapPin(
                              color: _pinColor(lot['status']?.toString()),
                              size: drawPin,
                              scale: effPin / drawPin,
                              // Tapping opens the lot normally; in adjust
                              // mode the gesture belongs to the drag.
                              onTap: _adjustMode ? null : () => _showLot(lot),
                            );
                            return Positioned(
                              left: at.dx,
                              top: at.dy,
                              child: !_adjustMode
                                  ? pin
                                  : GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onPanStart: (_) => setState(() {
                                        _dragLotId = lotId;
                                        _dragTip = tip;
                                      }),
                                      onPanUpdate: (d) => setState(() {
                                        final moved = (_dragTip ?? tip) + d.delta;
                                        // Clamped to the map box so a pin
                                        // can't be flung outside and lost.
                                        _dragTip = Offset(
                                          moved.dx.clamp(0.0, constraints.maxWidth),
                                          moved.dy.clamp(0.0, constraints.maxHeight),
                                        );
                                      }),
                                      onPanEnd: (_) =>
                                          _commitPinDrag(lotId, constraints),
                                      child: Opacity(
                                        opacity: dragging ? 0.75 : 1,
                                        child: pin,
                                      ),
                                    ),
                            );
                          }(),
                    ],
                  ),
                  ),
                );
                // Adjust mode stays flat at 1x: an InteractiveViewer would take
                // the drag as a pan before the pin saw it.
                // Otherwise anyone can pinch, scroll or drag the map. Pins sit
                // inside the child, so they move with the picture.
                if (_adjustMode) return buildBox(effPin);
                if (!_placementMode) {
                  return InteractiveViewer(
                    transformationController: _mapTransform,
                    panEnabled: true,
                    scaleEnabled: true,
                    // Mouse-wheel and trackpad scroll zoom instead of pan.
                    trackpadScrollCausesScale: true,
                    minScale: 1.0,
                    maxScale: 5.0,
                    clipBehavior: Clip.antiAlias,
                    // Keep the +/- buttons in sync when the user pinches/scrolls.
                    onInteractionEnd: (_) => setState(() {}),
                    // Divides the pin size by the zoom so pins keep about the
                    // same on-screen size as the map scales.
                    child: AnimatedBuilder(
                      animation: _mapTransform,
                      builder: (context, _) {
                        final scale = _mapTransform.value.getMaxScaleOnAxis();
                        final drawPin = (effPin / scale).clamp(2.0, effPin).toDouble();
                        return buildBox(drawPin);
                      },
                    ),
                  );
                }
                // Placement mode stays at 1x so a tap maps straight to a
                // relative pin coordinate without undoing a zoom transform.
                return MouseRegion(
                  cursor: SystemMouseCursors.precise,
                  child: GestureDetector(
                    onTapUp: (details) => _handleMapTap(details, constraints),
                    child: buildBox(effPin),
                  ),
                );
              },
    );
  }

  /// Saves the map picture to the device.
  /// Storage's `download` parameter makes the browser save the file instead
  /// of just opening it.
  Future<void> _downloadMap() async {
    final url = _mapImageUrl;
    if (url == null || url.isEmpty) return;
    try {
      final base = Uri.parse(url);
      final community = AppBranding.instance.communityName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      // Keep the existing query (the CMS adds a ?v= cache-buster) and add
      // `download` alongside it rather than replacing it.
      final ext = base.path.contains('.') ? base.path.split('.').last : 'jpg';
      final target = base.replace(queryParameters: {
        ...base.queryParameters,
        'download': '${community.isEmpty ? 'community' : community}-map.$ext',
      });
      await launchUrl(target, webOnlyWindowName: '_self');
    } catch (e) {
      if (mounted) _snack('Could not download the map. ${friendlyError(e)}', error: true);
    }
  }

  /// Pin colour for a lot status, from the CMS branding settings.
  Color _pinColor(String? status) {
    final b = AppBranding.instance;
    // Non-officers get an ordinary pin, so the colour can't reveal empty homes.
    if (status == 'vacant' && !widget.officer) return b.pinColor;
    switch (status) {
      case 'vacant':
        return b.pinColorVacant;
      case 'occupied':
        return b.pinColorOccupied;
      default:
        // Owned/default lots.
        return b.pinColor;
    }
  }

  /// Officer side panel listing up to 8 lots; tapping one opens its details.
  Widget _locationsCard(List<Map<String, dynamic>> rows) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1A0D2617), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Locations',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textPrimary)),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            Text('No lots yet.', style: TextStyle(fontSize: 12.5, color: _textSecondary))
          else
            for (final lot in rows.take(8))
              InkWell(
                onTap: () => _showLot(lot),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: _border), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: _pinColor(lot['status']?.toString()).withValues(alpha: 0.15),
                        child: Icon(Icons.place_outlined, size: 16, color: _pinColor(lot['status']?.toString())),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Lot ${lot['lot_number'] ?? ''}',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _textPrimary)),
                            Text('Block ${_blockNames[lot['block_id']] ?? '—'}',
                                style: TextStyle(fontSize: 11, color: _textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// Statuses hidden from non-officers: a list of empty homes would help
  /// burglars.
  static const _officerOnlyStatuses = {'vacant'};

  bool _statusVisible(String status) =>
      widget.officer || !_officerOnlyStatuses.contains(status);

  /// Status groups, ordered so the ones people scan for come first.
  /// Any status not listed here still renders, appended at the end.
  List<String> get _statusOrder {
    const known = ['vacant', 'occupied', 'rented', 'owned'];
    final seen = <String>{
      for (final lots in _lotsByBlock.values)
        for (final l in lots) (l['status'] ?? 'owned').toString()
    }.where(_statusVisible).toSet();
    return [...known.where(seen.contains), ...seen.where((s) => !known.contains(s))];
  }

  /// All lots keyed by status, each carrying its block so the label still
  /// reads "Block 64 · Lot 44" once block grouping is gone.
  Map<String, List<Map<String, dynamic>>> get _lotsByStatus {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final block in _blocks) {
      for (final lot in _lotsByBlock[block['id']] ?? const []) {
        final s = (lot['status'] ?? 'owned').toString();
        if (!_statusVisible(s)) continue;
        out.putIfAbsent(s, () => []).add({...lot, '_block': block});
      }
    }
    // Within a group, order by block then lot number so it reads predictably.
    for (final list in out.values) {
      list.sort((a, b) {
        final ab = (a['_block']?['block_name'] ?? '').toString();
        final bb = (b['_block']?['block_name'] ?? '').toString();
        final byBlock = ab.compareTo(bb);
        if (byBlock != 0) return byBlock;
        final an = num.tryParse((a['lot_number'] ?? '').toString()) ?? 0;
        final bn = num.tryParse((b['lot_number'] ?? '').toString()) ?? 0;
        return an.compareTo(bn);
      });
    }
    return out;
  }

  /// Switches between grouping by status and by block. Editing and deleting
  /// a block is only possible in the block view.
  Widget _groupToggle() {
    Widget seg(String label, bool active, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? (widget.officer ? AppColors.badgeGreenBg : ResidentColors.iconGreenBg)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? _textPrimary : _textSecondary)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: widget.officer ? AppColors.contentBg : ResidentColors.contentBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('By Status', _groupByStatus, () => setState(() => _groupByStatus = true)),
        seg('By Block', !_groupByStatus, () => setState(() => _groupByStatus = false)),
      ]),
    );
  }

  /// One card per status, holding every lot with that status.
  Widget _statusCard(String status, List<Map<String, dynamic>> lots) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: widget.officer ? Border.all(color: _border) : null,
          borderRadius: BorderRadius.circular(widget.officer ? 8 : 16),
          boxShadow: widget.officer ? null : ResidentColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusBadge(status),
                const SizedBox(width: 10),
                Text(titleCase(status),
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary)),
                const Spacer(),
                Text('${lots.length} lot${lots.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: _textSecondary)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final lot in lots)
                  InkWell(
                    onTap: () => _showLot(lot),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.officer ? AppColors.contentBg : ResidentColors.contentBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Block ${lot['_block']?['block_name'] ?? '—'} · Lot ${lot['lot_number'] ?? ''}',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _textPrimary),
                          ),
                          if (lot['street_address'] != null) ...[
                            const SizedBox(height: 4),
                            Text(lot['street_address'].toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: _textSecondary)),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One card per block, listing its lots, with edit and delete for officers.
  Widget _blockCard(Map<String, dynamic> block) {
    // Same visibility rule as the status view, so vacant lots stay hidden.
    final lots = (_lotsByBlock[block['id']] ?? const <Map<String, dynamic>>[])
        .where((l) => _statusVisible((l['status'] ?? 'owned').toString()))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: widget.officer ? Border.all(color: _border) : null,
          borderRadius: BorderRadius.circular(widget.officer ? 8 : 16),
          boxShadow: widget.officer ? null : ResidentColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Block ${block['block_name'] ?? ''}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary)),
                if ((block['phase'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('· Phase ${block['phase']}', style: TextStyle(fontSize: 12, color: _textSecondary)),
                ] else if (_canManage) ...[
                  // Flags a blank phase for officers: without it, this block's
                  // waste schedule can't be filtered to its area.
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.badgeAmberBg,
                        borderRadius: BorderRadius.circular(5)),
                    child: const Text('No phase set',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.badgeAmberText)),
                  ),
                ],
                const Spacer(),
                Text('${lots.length} lot${lots.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: _textSecondary)),
                if (_canManage) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Edit block / set phase',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    onPressed: () => _editBlock(block),
                  ),
                  IconButton(
                    tooltip: 'Delete block',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 17, color: Colors.redAccent),
                    onPressed: () => _deleteBlock(block, lots.length),
                  ),
                ],
              ],
            ),
            if (lots.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final lot in lots)
                    InkWell(
                      onTap: () => _showLot(lot),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 200,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.officer ? AppColors.contentBg : ResidentColors.contentBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Lot ${lot['lot_number'] ?? ''}',
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _textPrimary)),
                                const Spacer(),
                                StatusBadge((lot['status'] ?? 'owned').toString()),
                              ],
                            ),
                            if (lot['street_address'] != null) ...[
                              const SizedBox(height: 4),
                              Text(lot['street_address'].toString(),
                                  style: TextStyle(fontSize: 11, color: _textSecondary)),
                            ],
                            if (lot['lot_type'] != null) ...[
                              const SizedBox(height: 2),
                              Text((lot['lot_type']).toString(),
                                  style: TextStyle(fontSize: 10.5, color: _textSecondary)),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// "Add Address" dialog: creates a lot, plus a new block if the officer picks
/// "+ Add New Block". [mapX]/[mapY] come from the map tap; when null, the lot
/// is saved without a pin, which can be placed later from its detail view.
class _AddressFormDialog extends StatefulWidget {
  final List<Map<String, dynamic>> blocks;
  final double? mapX;
  final double? mapY;
  // Whether this phase has a map picture. A null mapX can't tell you, because
  // skipping the pin also leaves it null.
  final bool hasMap;
  const _AddressFormDialog(
      {required this.blocks, this.mapX, this.mapY, this.hasMap = false});

  @override
  State<_AddressFormDialog> createState() => _AddressFormDialogState();
}

class _AddressFormDialogState extends State<_AddressFormDialog> with SafeSetState<_AddressFormDialog> {
  /// Block dropdown value that means "+ Add New Block".
  static const _newBlockSentinel = -1;
  int? _blockId;
  final _newBlockNameCtrl = TextEditingController();
  final _newBlockPhaseCtrl = TextEditingController();
  final _lotNumberCtrl = TextEditingController();
  final _streetAddressCtrl = TextEditingController();
  String? _lotType;
  String _status = 'owned';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _newBlockNameCtrl.dispose();
    _newBlockPhaseCtrl.dispose();
    _lotNumberCtrl.dispose();
    _streetAddressCtrl.dispose();
    super.dispose();
  }

  /// Checks the form, creates the new block if one was asked for, then the lot.
  Future<void> _save() async {
    if (_lotNumberCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Lot number is required.');
      return;
    }
    if (_blockId == null) {
      setState(() => _error = 'Choose a block, or "+ Add New Block".');
      return;
    }
    if (_blockId == _newBlockSentinel && _newBlockNameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'New block name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = SupabaseService.instance.client;
      int resolvedBlockId;
      if (_blockId == _newBlockSentinel) {
        final inserted = await client.from('blocks').insert({
          'block_name': _newBlockNameCtrl.text.trim(),
          if (_newBlockPhaseCtrl.text.trim().isNotEmpty) 'phase': _newBlockPhaseCtrl.text.trim(),
        }).select('id').single();
        resolvedBlockId = inserted['id'] as int;
      } else {
        resolvedBlockId = _blockId!;
      }
      await client.from('lots').insert({
        'lot_number': _lotNumberCtrl.text.trim(),
        'block_id': resolvedBlockId,
        if (_streetAddressCtrl.text.trim().isNotEmpty) 'street_address': _streetAddressCtrl.text.trim(),
        if (_lotType != null) 'lot_type': _lotType,
        'status': _status,
        if (widget.mapX != null) 'map_x': widget.mapX,
        if (widget.mapY != null) 'map_y': widget.mapY,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save. ${friendlyError(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNewBlock = _blockId == _newBlockSentinel;
    return AlertDialog(
      title: const Text('Add Address'),
      content: SizedBox(
        width: dialogContentWidth(context, 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.mapX == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    widget.hasMap
                        ? 'This address will be saved without a pin. You can place it '
                            'on the map later from its detail view.'
                        : 'The map for this phase is under maintenance, so this address '
                            'won\'t have a pin yet. You can place one later from its '
                            'detail view once the map is uploaded.',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ),
              DropdownButtonFormField<int>(
                initialValue: _blockId,
                decoration: const InputDecoration(labelText: 'Block *'),
                items: [
                  for (final b in widget.blocks)
                    DropdownMenuItem(value: b['id'] as int, child: Text((b['block_name'] ?? '').toString())),
                  const DropdownMenuItem(value: _newBlockSentinel, child: Text('+ Add New Block')),
                ],
                onChanged: (v) => setState(() => _blockId = v),
              ),
              if (isNewBlock) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _newBlockNameCtrl,
                  decoration: const InputDecoration(labelText: 'New Block Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newBlockPhaseCtrl,
                  decoration: const InputDecoration(labelText: 'Phase (optional)'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _lotNumberCtrl,
                decoration: const InputDecoration(labelText: 'Lot Number *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _streetAddressCtrl,
                decoration: const InputDecoration(labelText: 'Street Address (optional)'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _lotType,
                decoration: const InputDecoration(labelText: 'Lot Type (optional)'),
                items: const [
                  DropdownMenuItem(value: 'residential', child: Text('Residential')),
                  DropdownMenuItem(value: 'commercial', child: Text('Commercial')),
                  DropdownMenuItem(value: 'vacant', child: Text('Vacant')),
                ],
                onChanged: (v) => setState(() => _lotType = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'owned', child: Text('Owned')),
                  DropdownMenuItem(value: 'vacant', child: Text('Vacant')),
                  DropdownMenuItem(value: 'occupied', child: Text('Occupied')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'owned'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
