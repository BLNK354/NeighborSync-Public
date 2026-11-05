/// Settings for the generic list and form screens.
///
/// A [ModuleConfig] describes how one Supabase table is listed, created,
/// edited and deleted through `ModuleListView` and `ModuleFormDialog`.
/// The actual modules are defined in module_registry.dart.
library;

// widgets.dart only: this file just needs the `Widget` type.
import 'package:flutter/widgets.dart';

import 'text_utils.dart';

/// The kinds of input a form field can be.
enum FieldType {
  text,
  longText,
  number,
  decimal,
  date,
  dateTime,
  boolean,
  select,
  reference,

  /// Files attached to the record, kept as a jsonb list of `{path, name}`.
  /// Files go to the private `documents` bucket under
  /// `<attachmentFolder>/<user_id>/…`.
  /// Never add them to the `documents` table: residents with
  /// `documents:read` could then read them.
  attachments,
}

/// What an [FieldConfig.editableWhen] gate gets to decide with. Passed by
/// the form dialog.
class FieldGate {
  /// The record being edited, or null on create.
  final Map<String, dynamic>? row;

  /// Current user's role name, e.g. 'secretary'.
  final String? role;

  /// Current user's `users.id`, for "did I file this" checks.
  final int? userId;

  /// Current user's permissions, as returned by getMyPermissions().
  final Map<String, Set<String>> permissions;

  const FieldGate({
    required this.row,
    required this.role,
    required this.userId,
    required this.permissions,
  });

  bool get isCreating => row == null;

  bool can(String module, String action) =>
      permissions[module]?.contains(action) ?? false;

  /// True when [column] on the row equals the current user's id.
  bool isMine(String column) {
    final v = row?[column];
    return v != null && userId != null && (v as num).toInt() == userId;
  }

  String get status => (row?['status'] ?? '').toString();
}

/// One column of a module: how it is shown in the list and edited in the
/// form.
class FieldConfig {
  /// Column name in the Supabase table.
  final String key;
  final String label;
  final FieldType type;
  final bool required;

  /// Whether this field gets a column in the list/table view.
  final bool showInList;

  /// Whether this field appears in the create/edit form. Set false for
  /// columns that are server/trigger-managed (id, created_at, ...).
  final bool editable;

  /// Allowed values for [FieldType.select].
  final List<String>? options;

  /// Table to pull dropdown options from for [FieldType.reference].
  final String? refTable;

  /// Columns to select from [refTable]; first is conventionally the id.
  final List<String>? refSelectColumns;

  /// Offers only rows with `is_active = true`, for lookup tables the office
  /// can retire (`permit_types`, `violation_types`).
  /// The row already selected stays listed even when retired; otherwise the
  /// dropdown goes blank and saving clears the field.
  final bool refActiveOnly;

  /// Limits a `users` dropdown to accounts holding one of these `roles.name`
  /// values. Only meaningful when [refTable] is `users`.
  final List<String>? refRoleFilter;

  /// Like [refRoleFilter], but worked out from the form's values, so the
  /// roles can depend on another field (see concern_routing.dart).
  /// Wins over [refRoleFilter] when both are set.
  final List<String> Function(Map<String, dynamic> values)? refRoleFilterFrom;

  /// Field key that [refRoleFilterFrom] reads. When this field's value
  /// changes the form reloads this dropdown's options and clears any
  /// selection that is no longer valid.
  final String? refRoleFilterDependsOn;

  /// Builds the human-readable label for one reference row. Defaults to
  /// joining every non-id column with a space.
  final String Function(Map<String, dynamic> row)? refLabelBuilder;

  /// Value pre-filled when creating a new record (e.g. current user id).
  final dynamic Function()? defaultValue;

  /// Date fields: how many months ahead may be picked. Null = no limit.
  final int? maxMonthsFromNow;

  /// Date fields for deadlines and schedules: no dates before today.
  final bool futureOnly;

  /// Date fields for things that already happened: no future dates.
  final bool pastOnly;

  /// [FieldType.decimal] fields that hold money get a peso-sign prefix.
  final bool currency;

  /// Reads this field's list value from a joined relation instead of a
  /// flat column (e.g. `row['lots']['lot_number']`).
  final dynamic Function(Map<String, dynamic> row)? listValueBuilder;

  /// Formats the raw value for display in the list view.
  final String Function(dynamic value)? listFormatter;

  /// Shows this field only to these roles. Other roles don't see it, and
  /// their save leaves its value untouched.
  final List<String>? restrictedToRoles;

  /// [FieldType.reference]: picking a value also fills another field on the
  /// form (e.g. picking a resident fills in their lot).
  /// [autoFillTargetKey] is the field to fill. [autoFillSourceColumn] is the
  /// picked row's column to copy, and must be in [refSelectColumns]; it
  /// defaults to [autoFillTargetKey].
  final String? autoFillTargetKey;
  final String? autoFillSourceColumn;

  /// Gets the auto-fill value when it is not a plain column, such as an
  /// embedded list. Return null to fill nothing, e.g. when a lot has more
  /// than one person on it.
  /// Must be top-level or static to stay const-compatible.
  final dynamic Function(Map<String, dynamic> pickedRow)? autoFillPick;

  /// Fills the target only when it is empty, instead of overwriting. Use on
  /// the lot-to-person side of a pair, so fixing an address never replaces
  /// the person named.
  final bool autoFillOnlyWhenEmpty;

  /// Decides whether this user may edit this field on this row right now
  /// (who filed it, what status it is in). When false the field shows
  /// read-only with a short reason.
  /// Must be top-level or static to stay const-compatible.
  final bool Function(FieldGate gate)? editableWhen;

  /// Hides this field from the form while it still saves, usually because
  /// another field auto-filled it. Must return false when the auto-fill
  /// found nothing, or a required field fails while invisible.
  /// Must be top-level or static to stay const-compatible.
  final bool Function(Map<String, dynamic> values)? hiddenWhen;

  /// Shows a [FieldType.select] as a progress strip, in this order, instead
  /// of a dropdown. [options] not listed here become chips below the strip,
  /// for outcomes that are not steps (dismissed, escalated).
  final List<String>? statusTrack;

  /// Makes a [FieldType.text] field free text with a lookup: a search icon
  /// opens a picker, and choosing someone fills in their name and stores
  /// their id in the field named here. Set the `ref*` properties to say what
  /// to search. Typing by hand clears the id, so the two cannot disagree.
  final String? lookupIdKey;

  /// [FieldType.attachments]: the first folder in the private `documents`
  /// bucket. Files land at `<attachmentFolder>/<user_id>/…`; the storage
  /// policies depend on that shape.
  final String? attachmentFolder;

  /// Makes this field required only in some states, e.g. a resolution note
  /// when closing a case. This only warns early; the database rule
  /// `require_resolution_to_close()` is what enforces it.
  /// Must be top-level or static to stay const-compatible.
  final bool Function(Map<String, dynamic> values)? requiredWhen;

  /// Format or range rule, run on every save attempt. Gets this field's
  /// value and all form values, and returns an error message or null.
  /// Empty values are passed too; required checks are separate.
  /// Must be top-level or static to stay const-compatible.
  final String? Function(Object? value, Map<String, dynamic> values)? validate;

  /// Upper-cases the text as it is saved (plate numbers, sticker numbers).
  final bool upperCase;

  /// Keeps this field off the create form, for fields that only mean
  /// something once the record exists. [defaultValue] is still saved on
  /// create.
  final bool editOnly;

  /// Moves this field behind the form's fold-out section, for fields that
  /// are rarely used.
  final bool advanced;

  /// Lets short related fields share a row. Two half-width fields in a row
  /// pair up; an unpaired one takes the full width. Pairs stack on a narrow
  /// screen.
  final bool halfWidth;

  /// Read-only on edit once it holds a value, for "who is this for" fields.
  /// An old record with it empty can still be filled in once.
  final bool lockOnEdit;

  /// Character limit for this text box, when it is shorter than the
  /// app-wide 255 (a plate number is 9 at most).
  final int? maxLength;

  /// Only these characters can be typed (a plate: letters, digits, space,
  /// dash). Anything else is ignored as it is typed.
  final String? allowedChars;

  /// Greyed example shown inside the empty box, e.g. "ABC 1234".
  final String? hint;

  /// A number field holding a year: picked from a grid instead of typed.
  /// [yearsAhead] is how far past this year the grid goes.
  final bool yearPicker;

  /// A text field holding a photo's public URL. Shows a picture picker that
  /// uploads to the public `community-media` bucket under this folder and
  /// stores the URL.
  final String? imageFolder;
  final int yearsAhead;

  /// Earliest year the year grid offers.
  final int firstYear;

  /// Read-only while the named field and this one both have a value, e.g.
  /// the Lot filled in from the chosen person. Picking another person
  /// updates it.
  final String? lockedWhenFilledBy;

  const FieldConfig({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.showInList = true,
    this.editable = true,
    this.options,
    this.refTable,
    this.refSelectColumns,
    this.refActiveOnly = false,
    this.refRoleFilter,
    this.refRoleFilterFrom,
    this.refRoleFilterDependsOn,
    this.refLabelBuilder,
    this.defaultValue,
    this.maxMonthsFromNow,
    this.futureOnly = false,
    this.pastOnly = false,
    this.currency = false,
    this.listValueBuilder,
    this.listFormatter,
    this.restrictedToRoles,
    this.autoFillTargetKey,
    this.autoFillSourceColumn,
    this.autoFillPick,
    this.autoFillOnlyWhenEmpty = false,
    this.editableWhen,
    this.halfWidth = false,
    this.hiddenWhen,
    this.advanced = false,
    this.statusTrack,
    this.editOnly = false,
    this.lockOnEdit = false,
    this.maxLength,
    this.allowedChars,
    this.hint,
    this.yearPicker = false,
    this.imageFolder,
    this.yearsAhead = 1,
    this.firstYear = 1950,
    this.lockedWhenFilledBy,
    this.requiredWhen,
    this.validate,
    this.upperCase = false,
    this.lookupIdKey,
    this.attachmentFolder,
  });

  /// The text shown for one row in this field's reference picker.
  String refLabel(Map<String, dynamic> row) {
    if (refLabelBuilder != null) return refLabelBuilder!(row);
    final cols = (refSelectColumns ?? const ['id'])
        .where((c) => c != 'id')
        .map((c) => row[c]?.toString() ?? '')
        .where((s) => s.isNotEmpty);
    return cols.isEmpty ? '#${row['id']}' : cols.join(' ');
  }

  dynamic listValue(Map<String, dynamic> row) =>
      listValueBuilder != null ? listValueBuilder!(row) : row[key];

  /// This field's value as text for the list view.
  String listDisplay(Map<String, dynamic> row) {
    final raw = listValue(row);
    if (listFormatter != null) return listFormatter!(raw);
    if (raw == null) return '—';
    if (type == FieldType.boolean) return raw == true ? 'Yes' : 'No';
    if (type == FieldType.decimal) {
      final n = num.tryParse(raw.toString());
      return n == null ? raw.toString() : n.toStringAsFixed(2);
    }
    if (type == FieldType.date || type == FieldType.dateTime) {
      final s = raw.toString();
      return s.contains('T') ? s.split('T').first : s;
    }
    // Same helper as the form's picker, so list and form read alike.
    if (type == FieldType.select) return titleCase(raw.toString());
    return raw.toString();
  }
}

/// A list action that sets [field] to [value] after a confirm dialog. See
/// [ModuleConfig.retireAction].
class RetireAction {
  final String label;
  final String tooltip;
  final String confirmTitle;
  final String confirmBody;
  final String field;
  final String value;
  final List<String> doneValues;

  const RetireAction({
    required this.label,
    required this.tooltip,
    required this.confirmTitle,
    required this.confirmBody,
    required this.field,
    required this.value,
    required this.doneValues,
  });
}

/// One module: which table it uses, its fields, and how the generic list and
/// form treat it.
class ModuleConfig {
  /// Internal key, also used as the officer route suffix: `/admin/$key`.
  final String key;
  final String table;
  final String label;

  /// Singular noun for the form title ("New Incident"). Falls back to [label].
  final String? itemNoun;

  final List<FieldConfig> fields;

  /// Column driving the status badge, if any (must also be a field).
  final String? statusField;

  /// Field used as the primary line of each list row.
  final String titleField;

  /// Field used as the secondary line of each list row.
  final String? subtitleField;

  final bool allowCreate;
  final bool allowEdit;
  final bool allowDelete;

  final String orderBy;
  final bool orderDescending;

  /// Column searched with ilike when the list is given search text.
  final String? searchField;

  /// A live card shown in the form, right after the row holding
  /// [contextAfterField], or at the very top when that is null. It gets the
  /// current form values and loads its own data.
  final String? contextAfterField;
  final Widget Function(Map<String, dynamic> values)? contextBuilder;

  /// Wording of the form's fold-out section. Without it the label is built
  /// from the labels of the fields inside.
  final String? advancedLabel;

  /// The column holding who filed the record, and what to call them, for the
  /// form's read-only explanations.
  final String? filedByField;
  final String? filedByNoun;

  /// Statuses in which the person who filed the record can still edit their
  /// own account of it.
  final List<String> statusOpenValues;

  /// Optional row grouping in the list. [groupKey] gives the value rows are
  /// grouped under; [groupHeader] builds the tinted header row. Grouping
  /// runs after sorting, so column sorting still works.
  final String Function(Map<String, dynamic> row)? groupKey;
  final String Function(String key, List<Map<String, dynamic>> rows)?
      groupHeader;

  /// When set, filters `users` rows to this `roles.name` value via an
  /// inner join (`select=*,roles!inner(name)`). Only meaningful when
  /// [table] == 'users'.
  final String? roleFilter;

  /// Fixed equality filters always applied, e.g. {'status': 'published'}.
  final Map<String, dynamic>? filterEq;

  /// Raw select string override (for joins). Defaults to '*'.
  final String? selectOverride;

  final String idField;

  /// Permission module name, when it differs from [key] (e.g. key `billing`,
  /// permission module `bills`). See core/permissions.dart.
  final String? permissionModuleOverride;

  /// Edge Function called after a successful create with
  /// `{'id': <new row id>}`, to add an AI suggestion to the record. It never
  /// blocks or fails the create.
  final String? classifyFunctionName;

  /// An extra list action that moves a record to a final status, e.g. a
  /// resident retiring their own vehicle. Hidden on rows already in
  /// [RetireAction.doneValues].
  final RetireAction? retireAction;

  const ModuleConfig({
    required this.key,
    required this.table,
    required this.label,
    this.itemNoun,
    required this.fields,
    this.statusField,
    required this.titleField,
    this.subtitleField,
    this.allowCreate = true,
    this.allowEdit = true,
    this.allowDelete = true,
    this.orderBy = 'created_at',
    this.orderDescending = true,
    this.searchField,
    this.contextAfterField,
    this.contextBuilder,
    this.advancedLabel,
    this.filedByField,
    this.filedByNoun,
    this.statusOpenValues = const ['submitted'],
    this.groupKey,
    this.groupHeader,
    this.roleFilter,
    this.filterEq,
    this.selectOverride,
    this.idField = 'id',
    this.permissionModuleOverride,
    this.classifyFunctionName,
    this.retireAction,
  });

  String get route => '/admin/$key';
  String get memberRoute => '/me/$key';
  String get permissionModule => permissionModuleOverride ?? key;

  /// Noun shown in the create/edit dialog title.
  String get formNoun => itemNoun ?? label;

  List<FieldConfig> get formFields => fields.where((f) => f.editable).toList();
}
