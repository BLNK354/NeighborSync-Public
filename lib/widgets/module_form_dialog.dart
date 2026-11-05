import 'dart:async';
import '../core/app_locale.dart' show tr;
import '../core/content_moderation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:file_picker/file_picker.dart';
import '../core/form_helpers.dart';
import '../core/module_config.dart';
import '../core/text_utils.dart';
import '../services/crud_service.dart';
import '../services/supabase_service.dart';
import '../core/evidence_upload.dart';
import '../theme/app_theme.dart';
// viewPaymentReceipt opens any file in the private documents bucket,
// attachments included, through a short-lived signed link.
import 'payment_proof_actions.dart';
import 'searchable_picker.dart';
import '../core/safe_state.dart';

/// Opens the generic create/edit dialog for [config]. Pass [initial] with
/// an existing row (including its id) to edit; omit it to create.
/// Returns true if the record was saved.
/// To create a record with values already filled in, use [prefill], never
/// [initial]: `initial != null` makes the dialog issue an UPDATE.
Future<bool?> showModuleFormDialog(
  BuildContext context,
  ModuleConfig config, {
  Map<String, dynamic>? initial,
  Map<String, dynamic>? prefill,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) =>
        ModuleFormDialog(config: config, initial: initial, prefill: prefill),
  );
}

/// The create/edit form for any module, built from its [ModuleConfig]. The
/// same form serves every role; each field's config decides who sees or
/// may edit it.
class ModuleFormDialog extends StatefulWidget {
  final ModuleConfig config;
  final Map<String, dynamic>? initial;

  /// Starting values for a NEW record — see [showModuleFormDialog].
  final Map<String, dynamic>? prefill;
  const ModuleFormDialog(
      {super.key, required this.config, this.initial, this.prefill});

  @override
  State<ModuleFormDialog> createState() => _ModuleFormDialogState();
}

class _ModuleFormDialogState extends State<ModuleFormDialog> with SafeSetState<ModuleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, List<Map<String, dynamic>>> _refOptions = {};
  bool _loadingRefs = true;
  bool _saving = false;

  /// Set by the first Save. After that every field is re-checked on each
  /// rebuild so errors clear once fixed (pickers never call didChange).
  bool _submitted = false;
  String? _error;
  String? _myRole; // current user's role name, for role-restricted fields
  int? _myUserId;
  Map<String, Set<String>> _myPerms = const {};

  /// Builds the context a [FieldConfig.editableWhen] gate needs.
  FieldGate get _gate => FieldGate(
        row: widget.initial,
        role: _myRole,
        userId: _myUserId,
        permissions: _myPerms,
      );

  /// Treats 0 and '' as empty, so a zero penalty does not force the
  /// "More options" section open on every edit.
  static bool _hasValue(dynamic v) {
    if (v == null) return false;
    final s = v.toString().trim();
    if (s.isEmpty) return false;
    final n = num.tryParse(s);
    return n == null || n != 0;
  }

  /// Whether the "More options" section is open. Starts closed, unless a
  /// field inside it already has a value.
  bool _showAdvanced = false;

  /// Guards the attach button while a file is going up.
  bool _uploadingAttachment = false;

  /// True when the field's gate, its edit lock or its auto-fill lock closes it.
  bool _isReadOnly(FieldConfig f) =>
      (f.editableWhen != null && !f.editableWhen!(_gate)) ||
      _lockedOnEdit(f) ||
      _lockedByFill(f);

  /// Locked on edit only if the record was filed with a value, so an older
  /// row missing its lot can still have one filled in once.
  bool _lockedOnEdit(FieldConfig f) {
    if (!f.lockOnEdit || !_isEdit) return false;
    final v = widget.initial?[f.key];
    return v != null && v.toString().trim().isNotEmpty;
  }

  /// Locked when this field and the one named by lockedWhenFilledBy both
  /// have a value.
  bool _lockedByFill(FieldConfig f) {
    final by = f.lockedWhenFilledBy;
    if (by == null) return false;
    bool has(dynamic v) => v != null && v.toString().isNotEmpty;
    return has(_values[by]) && has(_values[f.key]);
  }

  /// Required always, or only in the record's current state (e.g. a
  /// resolution note once a closing status is picked). Read `required`
  /// only through here, so the label and the validators always agree.
  bool _required(FieldConfig f) =>
      f.required || (f.requiredWhen?.call(_values) ?? false);

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    for (final f in widget.config.formFields) {
      final existing = widget.initial?[f.key] ?? widget.prefill?[f.key];
      _values[f.key] = existing ?? f.defaultValue?.call();
      if (f.type == FieldType.text ||
          f.type == FieldType.longText ||
          f.type == FieldType.number ||
          f.type == FieldType.decimal) {
        _controllers[f.key] =
            TextEditingController(text: _values[f.key]?.toString() ?? '');
      }
      // Never hide a value already set behind the closed section.
      if (f.advanced && _hasValue(_values[f.key])) _showAdvanced = true;
      // A lookup's id column has no form field of its own, so seed it here.
      if (f.lookupIdKey != null) {
        _values[f.lookupIdKey!] = widget.initial?[f.lookupIdKey!] ??
            widget.prefill?[f.lookupIdKey!];
      }
    }
    _loadRefs();
  }

  /// Loads who the caller is, then the option list for every picker.
  Future<void> _loadRefs() async {
    // Fills cachedUserRowId, which _save() needs for the auto
    // "created/reported/organized by" fields.
    _myUserId = await SupabaseService.instance.getMyUserId();
    _myPerms = await SupabaseService.instance.getMyPermissions();
    // Decides which role-restricted fields this user sees.
    _myRole = await SupabaseService.instance.getMyRole();
    for (final f in widget.config.formFields) {
      // Text fields with a lookup use the same option list as a reference
      // field; refOptions() goes by refTable, not the field type.
      if (f.type == FieldType.reference || f.lookupIdKey != null) {
        try {
          _refOptions[f.key] = await CrudService.instance.refOptions(f, values: _values);
        } catch (_) {
          _refOptions[f.key] = const [];
        }
      }
    }
    if (mounted) setState(() => _loadingRefs = false);
  }

  /// Reloads any picker whose options depend on [changedKey] (e.g. Category
  /// filters Assigned To), and clears a selection the new list no longer has.
  Future<void> _reloadDependentRefs(String changedKey) async {
    final dependents = widget.config.formFields.where(
      (f) => f.type == FieldType.reference && f.refRoleFilterDependsOn == changedKey,
    );
    for (final f in dependents) {
      List<Map<String, dynamic>> opts;
      try {
        opts = await CrudService.instance.refOptions(f, values: _values);
      } catch (_) {
        opts = const [];
      }
      if (!mounted) return;
      setState(() {
        _refOptions[f.key] = opts;
        final current = _values[f.key];
        if (current != null && !opts.any((o) => o['id'] == current)) {
          _values[f.key] = null;
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Validates, runs the offensive-language check, then inserts or updates
  /// the record and closes the dialog.
  Future<void> _save() async {
    if (!_submitted) setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    // Check the free text the person can edit (content_moderation.dart); a
    // problem is shown as the form's error and nothing is saved.
    final problem = await moderationProblem([
      for (final f in widget.config.formFields)
        if ((f.type == FieldType.text || f.type == FieldType.longText) &&
            // Digit-only boxes (phones) carry no words; names, makes and
            // colours DO have allowedChars and must still be read.
            f.allowedChars != '[0-9]' &&
            !(_isEdit && _isReadOnly(f)))
          _values[f.key]?.toString(),
    ]);
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _saving = false;
        _error = problem;
      });
      return;
    }
    try {
      final payload = <String, dynamic>{};
      for (final f in widget.config.formFields) {
        // Never send a field this user can't change: a stale copy could
        // trip the database guard with an error on a field they never touched.
        if (_isEdit && _isReadOnly(f)) continue;
        // The lookup id is saved with its text field, under the same rule.
        if (f.lookupIdKey != null) payload[f.lookupIdKey!] = _values[f.lookupIdKey!];
        var v = _values[f.key];
        if (f.type == FieldType.number) {
          v = v == null || v.toString().isEmpty ? null : int.tryParse(v.toString());
        } else if (f.type == FieldType.decimal) {
          v = v == null || v.toString().isEmpty ? null : num.tryParse(v.toString());
        } else if (v is DateTime) {
          // Times go as UTC (no offset would be read as UTC). Plain dates
          // stay local: toUtc() would shift the day after 4pm.
          v = f.type == FieldType.date
              ? v.toIso8601String().split('T').first
              : v.toUtc().toIso8601String();
        }
        payload[f.key] = v;
      }
      // Non-editable defaults (e.g. organizer_id) apply on create only, so
      // an edit never overwrites who created a record.
      if (!_isEdit) {
        for (final f in widget.config.fields) {
          if (!f.editable && f.defaultValue != null) {
            payload[f.key] = f.defaultValue!();
          }
        }
      }
      // Time limit, so a dropped connection ends with a message instead of
      // a spinner that never stops.
      const limit = Duration(seconds: 30);
      if (_isEdit) {
        await CrudService.instance
            .update(widget.config, widget.initial![widget.config.idField], payload)
            .timeout(limit);
      } else {
        await CrudService.instance.create(widget.config, payload).timeout(limit);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'Saving is taking too long. Check your connection, '
            'then close this form and look at the list before trying again -- '
            'it may already have been saved.');
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Cap the dialog to the space above the on-screen keyboard so its
    // internal scroll view can bring the focused field into view.
    final availableHeight = media.size.height - media.viewInsets.bottom - 48;
    return Dialog(
      // Do not add media.viewInsets.bottom here: Dialog already adds it, and
      // counting the keyboard twice collapses the form on a phone.
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 520, maxHeight: availableHeight.clamp(220.0, 640.0)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit
                    ? '${tr('Edit')} ${tr(widget.config.formNoun)}'
                    : '${tr('New')} ${tr(widget.config.formNoun)}',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              if (_loadingRefs)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _submitted
                          ? AutovalidateMode.always
                          : AutovalidateMode.disabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _formBody(),
                      ),
                    ),
                  ),
                ),
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.errorRedBg,
                    border: Border.all(color: AppColors.errorRedBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: AppColors.errorRed),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.errorRed,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    child: Text(tr('Cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving || _loadingRefs ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(tr('Save')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A field's label, with a red * when required.
  Widget _label(String text, bool required) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(text: tr(text), children: [
          if (required)
            const TextSpan(text: ' *', style: TextStyle(color: Colors.redAccent)),
        ]), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );

  /// The form's children: any summary card, the main fields, then the
  /// "More options" section. Hidden and restricted fields are left out.
  List<Widget> _formBody() {
    bool shown(FieldConfig f) =>
        (f.restrictedToRoles == null ||
            f.restrictedToRoles!.contains(_myRole)) &&
        !(f.hiddenWhen?.call(_values) ?? false) &&
        (_isEdit || !f.editOnly);

    final visible = widget.config.formFields.where(shown).toList();
    final main = visible.where((f) => !f.advanced).toList();
    final advanced = visible.where((f) => f.advanced).toList();

    final out = <Widget>[];
    // A card with no anchor field is a summary header, so it goes first.
    if (widget.config.contextBuilder != null &&
        widget.config.contextAfterField == null) {
      final card = widget.config.contextBuilder!(_values);
      out.add(card);
      out.add(const SizedBox(height: 14));
    }
    out.addAll(_rowsFor(main));
    if (advanced.isNotEmpty) out.addAll(_advancedSection(advanced));
    return out;
  }

  /// Lays a list of fields out, pairing consecutive half-width ones.
  List<Widget> _rowsFor(List<FieldConfig> fields) {
    final out = <Widget>[];
    for (var i = 0; i < fields.length; i++) {
      final f = fields[i];
      final next = i + 1 < fields.length ? fields[i + 1] : null;

      // A half-width field with no half-width neighbour takes the full row.
      if (f.halfWidth && next != null && next.halfWidth) {
        out.add(_pairRow(f, next));
        i++;
      } else {
        out.add(_fieldOrReadOnly(f));
      }
      out.add(const SizedBox(height: 14));

      if (widget.config.contextAfterField == f.key ||
          (next != null && widget.config.contextAfterField == next.key)) {
        final card = widget.config.contextBuilder?.call(_values);
        if (card != null) {
          out.add(card);
          out.add(const SizedBox(height: 14));
        }
      }
    }
    return out;
  }

  /// The fold-out section for rarely used fields. They are still saved
  /// while it is closed.
  List<Widget> _advancedSection(List<FieldConfig> fields) {
    return [
      InkWell(
        onTap: () => setState(() => _showAdvanced = !_showAdvanced),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_showAdvanced ? Icons.remove : Icons.add,
                  size: 15, color: AppColors.sidebarActiveText),
              const SizedBox(width: 6),
              Text(
                _showAdvanced
                    ? 'Fewer options'
                    : widget.config.advancedLabel ??
                        'Add ${_advancedLabel(fields)}',
                style: TextStyle(
                    fontSize: 12.5, color: AppColors.sidebarActiveText),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      if (_showAdvanced) ..._rowsFor(fields),
    ];
  }

  /// Lists the fields in the section, e.g. "penalty, discount or notes".
  String _advancedLabel(List<FieldConfig> fields) {
    final names = [for (final f in fields) f.label.toLowerCase()];
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}';
  }

  /// Two fields side by side, stacking below [_kPairStackWidth]. Uses the
  /// row's own width, not the screen's, because the dialog is capped.
  Widget _pairRow(FieldConfig left, FieldConfig right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _kPairStackWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldOrReadOnly(left),
              const SizedBox(height: 14),
              _fieldOrReadOnly(right),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _pairCell(left, right)),
            const SizedBox(width: 14),
            Expanded(child: _pairCell(right, left)),
          ],
        );
      },
    );
  }

  /// A status shown as a row of steps instead of a dropdown. The steps come
  /// from [FieldConfig.statusTrack]; anything else in [FieldConfig.options]
  /// (e.g. "dismissed") appears underneath as an "Or mark as" chip.
  Widget _statusTrackField(FieldConfig f) {
    final track = f.statusTrack ?? const <String>[];
    final current = (_values[f.key] ?? '').toString();
    final offRamps = [
      for (final o in (f.options ?? const <String>[]))
        if (!track.contains(o)) o
    ];
    final atIndex = track.indexOf(current);
    final readOnly = _isReadOnly(f);

    // A step, as either an equal share of the row or a self-sized chip.
    Widget step(String value, int index, {required bool stretch}) {
      final isCurrent = value == current;
      // Steps before the current one are tinted.
      final isPast = atIndex >= 0 && index < atIndex;
      final chip = InkWell(
        onTap: readOnly ? null : () => _setStatus(f, value),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 7, horizontal: stretch ? 4 : 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.sidebarActiveText
                : isPast
                    ? AppColors.badgeGreenBg
                    : Colors.transparent,
            border: isCurrent || isPast
                ? null
                : Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            titleCase(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              color: isCurrent
                  ? Colors.white
                  : isPast
                      ? AppColors.sidebarActiveText
                      : AppColors.textSecondary,
            ),
          ),
        ),
      );
      return stretch
          ? Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: chip))
          : chip;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f.label, _required(f)),
        // Equal shares while each step has room for its label, wrapped
        // chips once it doesn't.
        LayoutBuilder(
          builder: (context, constraints) {
            final perStep =
                track.isEmpty ? 0.0 : constraints.maxWidth / track.length;
            if (perStep >= _kStatusStepMinWidth) {
              return Row(children: [
                for (var i = 0; i < track.length; i++)
                  step(track[i], i, stretch: true),
              ]);
            }
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < track.length; i++)
                  step(track[i], i, stretch: false),
              ],
            );
          },
        ),
        if (offRamps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Or mark as',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              for (final o in offRamps)
                InkWell(
                  onTap: readOnly ? null : () => _setStatus(f, o),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    decoration: BoxDecoration(
                      color: o == current
                          ? AppColors.badgeAmberBg
                          : Colors.transparent,
                      border: Border.all(
                          color: o == current
                              ? AppColors.badgeAmberBg
                              : AppColors.border),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(titleCase(o),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: o == current
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: AppColors.textPrimary)),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Sets the status and refreshes any picker that depends on it.
  void _setStatus(FieldConfig f, String value) {
    setState(() => _values[f.key] = value);
    _reloadDependentRefs(f.key);
  }

  /// One half of a pair. A switch has no label above it, so it is pushed
  /// down by the label's height (12pt text + _label()'s 6px gap) to line up
  /// with its neighbour's input.
  Widget _pairCell(FieldConfig f, FieldConfig other) {
    final cell = _fieldOrReadOnly(f);
    if (f.type == FieldType.boolean && other.type != FieldType.boolean) {
      return Padding(padding: const EdgeInsets.only(top: 22), child: cell);
    }
    return cell;
  }

  /// Read-only fields are still shown, so an officer can read what a
  /// resident wrote without being able to rewrite it.
  Widget _fieldOrReadOnly(FieldConfig f) =>
      _isReadOnly(f) ? _readOnlyField(f) : _fieldWidget(f);

  /// A locked field: dimmed, not tappable, with a one-line reason underneath.
  Widget _readOnlyField(FieldConfig f) {
    return Opacity(
      opacity: 0.55,
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldWidget(f),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(_readOnlyReason(f),
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Why this particular field is locked, in the reader's terms.
  String _readOnlyReason(FieldConfig f) {
    if (_lockedOnEdit(f)) return 'Set when this was filed -- it cannot be changed.';
    if (_lockedByFill(f)) return "Filled in from the person's address.";
    // Which column says who filed this, and what to call them; modules
    // differ, so set filedByField/filedByNoun on the config.
    final ownerField = widget.config.filedByField ?? 'complainant_id';
    final ownerNoun = widget.config.filedByNoun ?? 'the resident who filed this';
    final owner = widget.initial?[ownerField];

    final mineToFile =
        owner != null && _myUserId != null && (owner as num).toInt() == _myUserId;
    final status = (widget.initial?['status'] ?? '').toString();
    final open = widget.config.statusOpenValues;

    if (mineToFile && status.isNotEmpty && !open.contains(status)) {
      return 'Locked — this is already being handled by the HOA office.';
    }
    if (mineToFile) {
      return 'Only HOA officers can change this.';
    }
    return 'Only $ownerNoun can change this.';
  }

  /// Builds the input that matches the field's type.
  Widget _fieldWidget(FieldConfig f) {
    switch (f.type) {
      case FieldType.text:
        if (f.imageFolder != null) return _imageField(f);
        return _textField(f, maxLines: 1);
      case FieldType.longText:
        return _textField(f, maxLines: 4);
      case FieldType.number:
        if (f.yearPicker) return _yearField(f);
        return _textField(f, keyboardType: TextInputType.number);
      case FieldType.decimal:
        return _textField(f,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // Peso prefix on money fields so amounts read as amounts.
            prefixText: f.currency ? '₱ ' : null);
      case FieldType.boolean:
        return Row(
          children: [
            Switch(
              value: _values[f.key] == true,
              onChanged: (v) => setState(() => _values[f.key] = v),
            ),
            const SizedBox(width: 8),
            Text(tr(f.label), style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          ],
        );
      case FieldType.attachments:
        return _attachmentsField(f);
      case FieldType.select:
        if (f.statusTrack != null) return _statusTrackField(f);
        final opts = <String>[...(f.options ?? const <String>[])];
        final current = _values[f.key]?.toString();
        // Keep a saved value that isn't in the options, or the field shows
        // blank and the next save wipes it to null.
        if (current != null && current.isNotEmpty && !opts.contains(current)) {
          opts.add(current);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f.label, _required(f)),
            DropdownButtonFormField<String>(
              initialValue: opts.contains(current) ? current : null,
              items: [
                for (final o in opts)
                  DropdownMenuItem(value: o, child: Text(titleCase(o))),
              ],
              onChanged: (v) {
                setState(() => _values[f.key] = v);
                // e.g. changing Category re-filters the Assigned To picker.
                _reloadDependentRefs(f.key);
              },
              validator: (v) => _required(f) && v == null ? '${f.label} is required' : null,
            ),
          ],
        );
      case FieldType.reference:
        final opts = _refOptions[f.key] ?? const [];
        final currentId = _values[f.key];
        final selected =
            opts.where((o) => o['id'] == currentId).cast<Map<String, dynamic>?>().firstOrNull;
        // A tap-to-open searchable picker, since these lists (users, lots)
        // can be long. The FormField wrapper provides required validation.
        return FormField<dynamic>(
          initialValue: selected?['id'],
          validator: (_) => _required(f) && _values[f.key] == null ? '${f.label} is required' : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(f.label, _required(f)),
              InkWell(
                onTap: () async {
                  final picked = await _showSearchablePicker(f, opts);
                  if (picked != null) {
                    setState(() {
                      _values[f.key] = picked['id'];
                      // Auto-fill another field from the pick, e.g. a
                      // resident for "Billed To" also fills "Lot".
                      if (f.autoFillTargetKey != null) {
                        final target = f.autoFillTargetKey!;
                        // autoFillPick reads values that aren't a plain
                        // column, such as a lot's embedded occupant.
                        final value = f.autoFillPick != null
                            ? f.autoFillPick!(picked)
                            : picked[f.autoFillSourceColumn ?? target];
                        final blank = _values[target] == null ||
                            _values[target].toString().isEmpty;
                        // With autoFillOnlyWhenEmpty, never overwrite an
                        // answer: correcting an address must not replace
                        // the person named.
                        if (value != null && (blank || !f.autoFillOnlyWhenEmpty)) {
                          _values[target] = value;
                        }
                      }
                    });
                    state.didChange(picked['id']);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: state.hasError ? Colors.redAccent : AppColors.inputBorder,
                        width: 1.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selected == null ? 'Tap to search & select' : f.refLabel(selected),
                          style: TextStyle(
                              fontSize: 13,
                              color: selected == null
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary),
                        ),
                      ),
                      const Icon(Icons.search, size: 16, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(state.errorText!,
                      style: const TextStyle(fontSize: 11.5, color: Colors.redAccent)),
                ),
            ],
          ),
        );
      case FieldType.date:
      case FieldType.dateTime:
        final current = _values[f.key];
        DateTime? dt;
        if (current is DateTime) {
          dt = current;
        } else if (current is String && current.isNotEmpty) {
          // A stored timestamp arrives as UTC; show it in the reader's zone.
          // A `date` string parses as local midnight, so it is unaffected.
          dt = DateTime.tryParse(current)?.toLocal();
        }
        final display = dt == null
            ? 'Select date${f.type == FieldType.dateTime ? ' & time' : ''}'
            : f.type == FieldType.dateTime
                ? dt.toString().split('.').first
                : dt.toIso8601String().split('T').first;
        // A FormField so required dates and date rules (end not before
        // start) are checked on Save.
        return FormField<Object?>(
          key: ValueKey('date-${f.key}'),
          validator: (_) {
            final v = _values[f.key];
            if (_required(f) && (v == null || (v is String && v.isEmpty))) {
              return '${f.label} is required';
            }
            return f.validate?.call(v, _values);
          },
          builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f.label, _required(f)),
            InkWell(
              onTap: () async {
                // The picker is the only way to set these fields, so its
                // bounds are the rule: futureOnly = not before today,
                // pastOnly = not after today, maxMonthsFromNow = how far ahead.
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                var maxDate = f.maxMonthsFromNow == null
                    ? DateTime(2100)
                    : DateTime(now.year, now.month + f.maxMonthsFromNow!, now.day);
                if (f.pastOnly) maxDate = today;
                final minDate = f.futureOnly ? today : DateTime(2020);
                var initial = dt ?? now;
                if (initial.isAfter(maxDate)) initial = maxDate;
                if (initial.isBefore(minDate)) initial = minDate;
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: minDate,
                  lastDate: maxDate,
                );
                if (picked == null) return;
                var result = picked;
                if (f.type == FieldType.dateTime) {
                  final time = await showTimePicker(
                    // ignore: use_build_context_synchronously
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(dt ?? DateTime.now()),
                  );
                  if (time != null) {
                    result = DateTime(
                        picked.year, picked.month, picked.day, time.hour, time.minute);
                  }
                }
                setState(() => _values[f.key] = result);
                if (state.hasError) state.validate();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.inputBorder, width: 1.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(display,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(state.errorText!,
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
        );
    }
  }

  /// Below this row width a half-width pair stacks, because each column
  /// would be too narrow for its label.
  static const double _kPairStackWidth = 380;

  /// Below this much room per step, the status strip wraps into chips.
  /// Roughly what "Penalty Imposed" needs at 11.5pt without being cut off.
  static const double _kStatusStepMinWidth = 96;

  /// Opens the searchable picker for a reference field. Returns the chosen
  /// option row, or null if dismissed.
  Future<Map<String, dynamic>?> _showSearchablePicker(
      FieldConfig f, List<Map<String, dynamic>> opts) {
    // Find the current row by its id: refOptions() rebuilds these maps, so
    // a row held from earlier would never match and never tick.
    Map<String, dynamic>? current;
    for (final o in opts) {
      if (o['id'] == _values[f.key]) {
        current = o;
        break;
      }
    }
    return showSearchablePicker<Map<String, dynamic>>(
      context: context,
      title: 'Select ${f.label}',
      items: opts,
      labelOf: f.refLabel,
      selected: current,
    );
  }

  /// Guards the photo buttons while a picture is going up.
  bool _uploadingImage = false;

  /// A photo for an announcement or event: preview, Change, Remove. The
  /// file is shrunk, then uploaded to the public `community-media` bucket
  /// (signed-out visitors see these posts) and the row stores its public URL.
  Widget _imageField(FieldConfig f) {
    final url = (_values[f.key] ?? '').toString();
    Future<void> pick() async {
      final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (picked == null || picked.files.isEmpty || picked.files.first.bytes == null) return;
      final file = picked.files.first;
      setState(() => _uploadingImage = true);
      try {
        final shrunk = compressImageBytes(file.bytes!, file.name);
        final safe = shrunk.filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final path = '${f.imageFolder}/${DateTime.now().millisecondsSinceEpoch}-$safe';
        final ext = safe.contains('.') ? safe.split('.').last.toLowerCase() : 'jpg';
        final type = switch (ext) {
          'png' => 'image/png',
          'webp' => 'image/webp',
          'gif' => 'image/gif',
          _ => 'image/jpeg',
        };
        final storage = SupabaseService.instance.client.storage.from('community-media');
        await storage.uploadBinary(path, shrunk.bytes, fileOptions: FileOptions(contentType: type));
        final publicUrl = storage.getPublicUrl(path);
        if (!mounted) return;
        setState(() {
          _values[f.key] = publicUrl;
          _controllers[f.key]?.text = publicUrl;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Could not upload the photo. ${friendlyError(e)}')));
        }
      } finally {
        if (mounted) setState(() => _uploadingImage = false);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f.label, _required(f)),
        if (url.isEmpty)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _uploadingImage ? null : pick,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.inputBorder, width: 1.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                _uploadingImage
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_photo_alternate_outlined, size: 28, color: AppColors.textMuted),
                const SizedBox(height: 6),
                Text(_uploadingImage ? 'Uploading...' : 'Add a photo (optional)',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ]),
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(url, width: 140, height: 90, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 140, height: 90, color: const Color(0xFFF1F3F4),
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted))),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextButton.icon(
                  onPressed: _uploadingImage ? null : pick,
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: Text(_uploadingImage ? 'Uploading...' : 'Change photo'),
                ),
                TextButton.icon(
                  onPressed: _uploadingImage
                      ? null
                      : () => setState(() {
                            _values[f.key] = null;
                            _controllers[f.key]?.text = '';
                          }),
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                  label: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
                ),
              ]),
            ],
          ),
      ],
    );
  }

  /// A year chosen from a grid of years rather than typed. The value is
  /// also kept in the field's text controller, which this widget reads back.
  Widget _yearField(FieldConfig f) {
    final now = DateTime.now().year;
    final current = int.tryParse(_controllers[f.key]?.text ?? '');
    return FormField<int>(
      initialValue: current,
      validator: (_) {
        final v = int.tryParse(_controllers[f.key]?.text ?? '');
        return _required(f) && v == null ? '${f.label} is required' : null;
      },
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(f.label, _required(f)),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Select ${f.label.toLowerCase()}'),
                  content: SizedBox(
                    width: 300,
                    height: 320,
                    child: YearPicker(
                      firstDate: DateTime(f.firstYear),
                      lastDate: DateTime(now + f.yearsAhead),
                      selectedDate: DateTime(current ?? now),
                      onChanged: (d) => Navigator.pop(ctx, d.year),
                    ),
                  ),
                  actions: [
                    if (current != null && !_required(f))
                      TextButton(onPressed: () => Navigator.pop(ctx, -1), child: const Text('Clear')),
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  ],
                ),
              );
              if (picked == null) return;
              setState(() {
                final v = picked == -1 ? null : picked;
                _values[f.key] = v;
                _controllers[f.key]?.text = v?.toString() ?? '';
              });
              state.didChange(picked == -1 ? null : picked);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                    color: state.hasError ? Colors.redAccent : AppColors.inputBorder, width: 1.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                    current?.toString() ?? 'Select year',
                    style: TextStyle(
                        fontSize: 13,
                        color: current == null ? AppColors.textSecondary : AppColors.textPrimary),
                  ),
                ),
                const Icon(Icons.calendar_month_outlined, size: 16, color: AppColors.textMuted),
              ]),
            ),
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(state.errorText!, style: const TextStyle(fontSize: 11.5, color: Colors.redAccent)),
            ),
        ],
      ),
    );
  }

  /// A text or number box. A field with lookupIdKey also gets a search
  /// button that links the text to a resident.
  Widget _textField(FieldConfig f,
      {int maxLines = 1, TextInputType? keyboardType, String? prefixText}) {
    final lookup = f.lookupIdKey;
    final linkedId = lookup == null ? null : _values[lookup];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f.label, _required(f)),
        TextFormField(
          controller: _controllers[f.key],
          maxLines: maxLines,
          keyboardType: keyboardType,
          // Free text stops at the field's limit or kMaxTextLength; numbers
          // have their own validator. Only multi-line boxes show the counter.
          maxLength: keyboardType == null ? (f.maxLength ?? kMaxTextLength) : null,
          inputFormatters: f.type == FieldType.decimal
              ? moneyInputFormatters
              : f.allowedChars == null
                  ? null
                  : [FilteringTextInputFormatter.allow(RegExp(f.allowedChars!))],
          decoration: InputDecoration(
            counterText: maxLines > 1 ? null : '',
            prefixText: prefixText,
            hintText: f.hint,
            suffixIcon: lookup == null
                ? null
                : IconButton(
                    tooltip: 'Search residents',
                    icon: const Icon(Icons.search, size: 18),
                    onPressed: () => _pickLookup(f, lookup),
                  ),
          ),
          textCapitalization:
              f.upperCase ? TextCapitalization.characters : TextCapitalization.none,
          onChanged: (v) {
            _values[f.key] = f.upperCase ? v.toUpperCase() : v;
            // Typing by hand breaks the link: the id must never disagree
            // with the words. Picking from the list sets it again.
            if (lookup != null && _values[lookup] != null) {
              setState(() => _values[lookup] = null);
            }
          },
          validator: (v) => _validate(f, v),
        ),
        if (lookup != null && linkedId != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.link, size: 13, color: AppColors.sidebarActiveText),
                const SizedBox(width: 5),
                Text('Linked to this resident\'s record',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.sidebarActiveText)),
              ],
            ),
          ),
      ],
    );
  }

  /// Files attached to the record, stored in the column as a jsonb list of
  /// `{path, name}`. Uploads go to `<folder>/<my user id>/…` in the private
  /// `documents` bucket; the storage policies match on that path.
  /// When read-only, files can still be opened but not added or removed.
  Widget _attachmentsField(FieldConfig f) {
    final items = _attachmentList(f);
    final readOnly = _isReadOnly(f);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(f.label, _required(f)),
        if (items.isEmpty && readOnly)
          const Text('No files attached.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        for (final a in items)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.highlight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.attach_file, size: 15, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text((a['name'] ?? 'file').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textPrimary)),
                ),
                TextButton(
                  onPressed: () =>
                      viewPaymentReceipt(context, (a['path'] ?? '').toString()),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero),
                  child: const Text('Open', style: TextStyle(fontSize: 12)),
                ),
                if (!readOnly)
                  IconButton(
                    tooltip: 'Remove',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      // Drops the reference only; the stored file stays, so
                      // no evidence is lost if the row is ever rolled back.
                      final next = [...items]..remove(a);
                      _values[f.key] = next;
                    }),
                  ),
              ],
            ),
          ),
        if (!readOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _uploadingAttachment ? null : () => _attachFile(f),
              icon: const Icon(Icons.upload_file, size: 16),
              label: Text(_uploadingAttachment ? 'Uploading…' : 'Attach a photo or file',
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ),
      ],
    );
  }

  /// The field's current value as a list of `{path, name}` maps.
  List<Map<String, dynamic>> _attachmentList(FieldConfig f) {
    final raw = _values[f.key];
    if (raw is List) {
      return [
        for (final e in raw)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    }
    return const [];
  }

  /// Lets the person pick a file, uploads it and adds it to the field's list.
  Future<void> _attachFile(FieldConfig f) async {
    final folder = f.attachmentFolder;
    if (folder == null || _myUserId == null) return;

    setState(() => _uploadingAttachment = true);
    try {
      // Shared uploader, so every form writes to the path the storage
      // policies expect.
      final added = await pickAndUploadEvidence(
          folder: folder, userId: _myUserId!);
      if (added == null || !mounted) return;
      setState(() {
        _values[f.key] = [..._attachmentList(f), added];
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not attach. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _uploadingAttachment = false);
    }
  }

  /// Opens the same searchable picker a reference field uses, and writes
  /// BOTH the display text and the chosen id.
  Future<void> _pickLookup(FieldConfig f, String idKey) async {
    final opts = _refOptions[f.key] ?? const [];
    final picked = await _showSearchablePicker(f, opts);
    if (picked == null) return;
    setState(() {
      _values[f.key] = f.refLabel(picked);
      _values[idKey] = picked['id'];
      _controllers[f.key]?.text = _values[f.key].toString();
    });
  }

  /// Validation for every text box: required, then the field's own rule.
  /// Number and decimal fields also refuse negatives and non-numbers.
  String? _validate(FieldConfig f, String? v) {
    if (_required(f) && (v == null || v.trim().isEmpty)) return '${f.label} is required';
    if ((f.type == FieldType.number || f.type == FieldType.decimal) &&
        v != null &&
        v.trim().isNotEmpty) {
      final n = num.tryParse(v.trim());
      if (n == null) return 'Enter a valid number';
      if (n < 0) return 'Must be a positive number';
    }
    return f.validate?.call(v, _values);
  }
}
