/// Format rules for [FieldConfig.validate]. Top-level so module configs can
/// stay `const`. Each returns an error message, or null when the value is
/// fine. Empty values pass -- whether a field is required is checked
/// separately, so the same rule works on optional fields.
library;

String _s(Object? v) => (v ?? '').toString().trim();

/// Longest plate the rule accepts: 4 letters, a separator, 4 numbers
/// ("ABCD 1234"). Plate boxes stop accepting input here.
const int kPlateMaxLength = 9;

/// Characters a plate box will take at all: letters, digits, space, dash.
/// A pattern string rather than a RegExp so module configs can stay
/// `const`; callers wrap it in RegExp().
const String kPlateAllowedChars = r'[A-Za-z0-9 \-]';

/// Vehicle plate, Philippine style: 1-4 letters then 1-4 numbers, with an
/// optional space or dash -- "ABC 0123", "ABC-123", "AB 1234".
String? plateRule(Object? value, Map<String, dynamic> _) {
  final v = _s(value).toUpperCase();
  if (v.isEmpty) return null;
  if (!RegExp(r'^[A-Z]{1,4}[ -]?[0-9]{1,4}$').hasMatch(v)) {
    // Kept short so it fits the half-width plate box.
    return 'Enter a valid plate #';
  }
  return null;
}

/// Philippine phone number: mobile (09XX XXX XXXX / +639XX XXX XXXX) or a
/// landline with its area code. Spaces, dashes and brackets are ignored.
String? phoneRule(Object? value, Map<String, dynamic> _) {
  final v = _s(value).replaceAll(RegExp(r'[\s\-()]'), '');
  if (v.isEmpty) return null;
  if (!RegExp(r'^09\d{9}$').hasMatch(v)) {
    // Same wording as phoneError() in form_helpers.dart.
    if (!v.startsWith('09')) return 'A mobile number starts with 09, e.g. 09171234567';
    if (v.length != 11) return 'That is ${v.length} digits. A mobile number has 11 (09XXXXXXXXX)';
    return 'Use numbers only, e.g. 09171234567';
  }
  return null;
}

DateTime? _date(Object? v) {
  if (v is DateTime) return v;
  final s = _s(v);
  return s.isEmpty ? null : DateTime.tryParse(s);
}

/// For an end_date field: may not be earlier than start_date.
String? endNotBeforeStartRule(Object? value, Map<String, dynamic> values) {
  final end = _date(value), start = _date(values['start_date']);
  if (end == null || start == null) return null;
  final e = DateTime(end.year, end.month, end.day);
  final st = DateTime(start.year, start.month, start.day);
  if (e.isBefore(st)) return 'End date cannot be before the start date';
  return null;
}

/// Characters a person's NAME may contain: letters (including accented
/// ones like "ñ" and "é"), spaces, hyphen, apostrophe and period --
/// "Ma. Cristina", "De la Cruz", "O'Neil", "Peña". No digits, no other
/// symbols. Used as [FieldConfig.allowedChars] and by [nameInputFormatters].
const String kNameAllowedChars = r"[A-Za-zÀ-ÖØ-öø-ÿ .'\-]";

/// A person's name: must contain a letter, and only [kNameAllowedChars].
String? nameRule(Object? value, Map<String, dynamic> _) {
  final v = _s(value);
  if (v.isEmpty) return null;
  if (!RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ .'\-]+$").hasMatch(v) ||
      !RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').hasMatch(v)) {
    return 'Use letters only';
  }
  return null;
}

/// Vehicle make and colour: words only -- "Toyota", "Mercedes-Benz",
/// "Pearl White". Same character set as a name.
const String kWordAllowedChars = r"[A-Za-zÀ-ÖØ-öø-ÿ .'\-]";

/// Words only (letters and [kWordAllowedChars] symbols), with at least one letter.
String? lettersOnlyRule(Object? value, Map<String, dynamic> _) {
  final v = _s(value);
  if (v.isEmpty) return null;
  if (!RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ .'\-]+$").hasMatch(v) ||
      !RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').hasMatch(v)) {
    return 'Use letters only';
  }
  return null;
}

/// Characters a vehicle model may contain. Digits are allowed ("L300",
/// "F-150") but a model of only numbers is refused.
const String kModelAllowedChars = r'[A-Za-z0-9 .\-]';

/// Vehicle model: must have a letter and only [kModelAllowedChars].
String? modelRule(Object? value, Map<String, dynamic> _) {
  final v = _s(value);
  if (v.isEmpty) return null;
  if (!RegExp(r'^[A-Za-z0-9 .\-]+$').hasMatch(v) ||
      !RegExp(r'[A-Za-z]').hasMatch(v)) {
    return 'Enter the model name, not just numbers';
  }
  return null;
}
