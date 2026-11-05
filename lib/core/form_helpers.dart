import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthWeakPasswordException, PostgrestException;

/// Length of a PH mobile number, 09XXXXXXXXX.
const kPhoneMaxLength = 11;

/// Longest payment or transfer reference number (GCash, bank).
const kReferenceMaxLength = 30;

/// Hand-built name boxes: letters, spaces, hyphen, apostrophe, period only.
/// Keep the same set as kNameAllowedChars in field_rules.dart.
final List<TextInputFormatter> nameInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ .'\-]")),
];

/// Expected guests on a booking: digits only, at most 4.
final List<TextInputFormatter> guestCountInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(4),
];

/// Returns null for a valid guest count or an empty box (the field is
/// optional), otherwise the message to show.
String? guestCountError(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  if (t.length > 4) return 'That number is too large.';
  final n = int.tryParse(t);
  if (n == null) return 'Enter the number of guests.';
  if (n < 1) return 'There has to be at least 1 guest.';
  return null;
}

/// Official Receipt number typed at the desk: digits only, at most 6.
/// If left empty, the database issues one.
const kOrNumberMaxLength = 6;
final List<TextInputFormatter> orNumberInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(kOrNumberMaxLength),
];

/// Bank account number: digits only, at most 16.
const kAccountNumberMaxLength = 16;
final List<TextInputFormatter> accountNumberInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(kAccountNumberMaxLength),
];

/// Money boxes: at most 10 digits before the point and 2 after.
/// Must match the numeric(12,2) money columns, or a save can fail.
final List<TextInputFormatter> moneyInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  TextInputFormatter.withFunction((oldV, newV) =>
      RegExp(r'^\d{0,10}(\.\d{0,2})?$').hasMatch(newV.text) ? newV : oldV),
];

/// Hand-built phone boxes: digits only, at most 11.
final List<TextInputFormatter> phoneInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(kPhoneMaxLength),
];

/// Turns any exception into a short sentence for the user. Anything
/// unrecognised becomes a generic line, so raw server errors never show.
String friendlyError(Object? e) {
  // Rules the database raises on purpose already carry a readable sentence.
  // Raw "violates check constraint ..." errors are replaced further down.
  if (e is PostgrestException &&
      e.code == '23514' &&
      !e.message.toLowerCase().contains('violates')) {
    return e.message;
  }
  // Name the field or record involved: 23502 empty required field,
  // 23505 duplicate value, 23503 missing or still-referenced record.
  if (e is PostgrestException) {
    final m = e.message;
    String nice(String raw) => raw
        .replaceAll('_id', '')
        .replaceAll('_', ' ')
        .trim()
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
    if (e.code == '23502') {
      final col = RegExp(r'column "([^"]+)"').firstMatch(m)?.group(1);
      return col == null
          ? 'A required field is empty.'
          : '"${nice(col)}" is required -- please fill it in.';
    }
    if (e.code == '23505') {
      var col = RegExp(r'Key \(([^)]+)\)').firstMatch(e.details?.toString() ?? '')?.group(1);
      // Details are not always sent; fall back to the constraint name in
      // the message, e.g. "payments_or_number_key".
      if (col == null) {
        final c = RegExp(r'constraint "([^"]+)"').firstMatch(m)?.group(1);
        if (c != null) {
          // "<table>_<column>_key": drop the suffix, then the table name.
          col = c.replaceAll(RegExp(r'_(key|pkey|unique)$'), '');
          final cut = col.indexOf('_');
          if (cut > 0) col = col.substring(cut + 1);
        }
      }
      if (col == 'or_number') {
        return 'That OR number is already used by another payment. '
            'Type a different one, or leave it blank to get the next number.';
      }
      return col == null || col.isEmpty
          ? 'That already exists -- it must be unique.'
          : 'That ${nice(col).toLowerCase()} is already used by another record. '
              'Change it and save again.';
    }
    if (e.code == '23503') {
      // On delete, details read 'Key (id)=(5) is still referenced from table "bills".'
      final tbl = RegExp(r'from table "([^"]+)"').firstMatch(e.details?.toString() ?? '')?.group(1);
      if (tbl != null) {
        return "This can't be deleted: it is still used by ${nice(tbl).toLowerCase()}. "
            'Remove or move those first, or turn it off instead.';
      }
      final col = RegExp(r'Key \(([^)]+)\)').firstMatch(e.details?.toString() ?? '')?.group(1);
      return col == null
          ? 'One of the chosen items no longer exists. Please pick it again.'
          : 'The chosen ${nice(col).toLowerCase()} no longer exists. Please pick it again.';
    }
  }
  // A "pwned" password may meet every length and character rule, so it
  // gets its own message rather than the usual password hint.
  if (e is AuthWeakPasswordException) {
    if (e.reasons.contains('pwned')) {
      return 'That password has appeared in a known data breach, so it is '
          'not allowed. Please choose a different one.';
    }
    return 'That password is too weak. $kPasswordHint';
  }
  final s = e.toString().toLowerCase();

  if (s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('network') ||
      s.contains('clientexception') ||
      s.contains('connection')) {
    return 'Network problem — check your connection and try again.';
  }
  if (s.contains('timeout') || s.contains('timed out') || s.contains('deadline')) {
    return 'The server took too long to respond. Please try again.';
  }
  // A suspended or deactivated account is banned at the login server.
  if (s.contains('user is banned') || s.contains('user_banned')) {
    return 'This account has been suspended. Please contact the HOA office.';
  }
  if (s.contains('invalid login credentials')) return 'Wrong email or password.';
  if (s.contains('email not confirmed')) return 'Please verify your email first.';
  if (s.contains('user already registered') ||
      s.contains('already been registered') ||
      s.contains('already registered')) {
    return 'That email is already registered. Try signing in instead.';
  }
  if (s.contains('weak password') || s.contains('password should be')) {
    return 'That password is too weak. Use at least 8 characters.';
  }
  if (s.contains('rate limit') || s.contains('too many requests') || s.contains('429')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (s.contains('row-level security') ||
      s.contains('permission denied') ||
      s.contains('not authorized') ||
      s.contains('unauthorized') ||
      s.contains('403')) {
    return "You don't have permission to do that.";
  }
  if (s.contains('not found') || s.contains('404') || s.contains('no rows')) {
    return "We couldn't find what you were looking for.";
  }
  if (s.contains('foreign key') || s.contains('violates') || s.contains('still referenced')) {
    return "That can't be done because the record is still in use.";
  }
  if (s.contains('duplicate') || s.contains('already exists') || s.contains('unique constraint')) {
    return 'That already exists.';
  }
  return 'Something went wrong. Please try again.';
}

/// Reserved domains that can never receive mail, so a password reset could
/// never reach them. This is a block list; do not turn it into an allow-list,
/// which would lock out real work and ISP addresses.
const _undeliverableDomains = <String>{
  'test', 'example', 'invalid', 'localhost', 'local',
  'example.com', 'example.net', 'example.org',
};

/// Throwaway-inbox providers, matched on the registrable part of the domain
/// so `mailinator.com` and `mailinator.net` are both refused.
/// The database copy (`email_domain_is_undeliverable`) is what enforces this;
/// this one only lets the form say so before the request is sent.
const _disposableDomains = <String>{
  'mailinator', 'guerrillamail', '10minutemail', 'tempmail', 'temp-mail',
  'throwawaymail', 'yopmail', 'trashmail', 'sharklasers', 'getnada',
  'dispostable', 'maildrop', 'fakeinbox', 'mailnesia', 'mintemail',
  'spamgourmet', 'discard', 'emailondeck', 'moakt', 'mohmal', 'inboxkitten',
};

/// Checks an email address, refusing junk like "a@b" and domains that cannot
/// receive mail. Returns null when valid, otherwise the message to show.
String? emailError(String? v) {
  final value = (v ?? '').trim();
  if (value.isEmpty) return 'Email is required';
  final re = RegExp(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$");
  if (!re.hasMatch(value)) return 'Enter a valid email (e.g. name@gmail.com)';

  final domain = value.split('@').last.toLowerCase();
  final tld = domain.split('.').last;
  if (_undeliverableDomains.contains(domain) || _undeliverableDomains.contains(tld)) {
    return 'That address cannot receive email. Use a real one so you can '
        'reset your password later.';
  }

  // "mailinator" out of "mail.mailinator.com". Match the whole label, not a
  // substring, or "name@mytempmailbox.com" is refused for containing "tempmail".
  final labels = domain.split('.');
  final registrable = labels.length >= 2 ? labels[labels.length - 2] : domain;
  if (_disposableDomains.contains(registrable)) {
    return 'Temporary inboxes are not accepted. Use a permanent address so '
        'the office can reach you and you can reset your password.';
  }
  return null;
}

/// Checks a Philippine mobile number, exactly 11 digits: 09XXXXXXXXX.
/// Returns null when valid, otherwise a message naming the wrong part.
String? phoneError(String? v) {
  final raw = (v ?? '').trim();
  if (raw.isEmpty) return 'Phone number is required';
  final digits = raw.replaceAll(RegExp(r'[\s\-()]'), '');
  if (RegExp(r'[^0-9]').hasMatch(digits)) {
    return 'Use numbers only, e.g. 09171234567';
  }
  if (!digits.startsWith('09')) {
    return 'A mobile number starts with 09, e.g. 09171234567';
  }
  if (digits.length != 11) {
    return 'That is ${digits.length} digits. A mobile number has 11 (09XXXXXXXXX)';
  }
  return null;
}

/// Longest free text any form accepts (descriptions, notes, names...).
const kMaxTextLength = 255;

/// Must match the minimum length in the Supabase Auth settings.
const kMinPasswordLength = 8;

/// Checks a password: at least 8 characters with lowercase, uppercase, a digit
/// and a symbol. Returns null when valid, otherwise the message to show.
/// Must match the Supabase Auth settings; if the form is laxer, the server
/// refuses the password after submit.
String? passwordError(String? v) {
  final value = v ?? '';
  if (value.isEmpty) return 'Password is required';
  if (value.length < kMinPasswordLength) {
    return 'Too short: ${value.length} of $kMinPasswordLength characters. '
        'Use at least $kMinPasswordLength.';
  }
  final missing = <String>[
    if (!RegExp(r'[a-z]').hasMatch(value)) 'a lowercase letter',
    if (!RegExp(r'[A-Z]').hasMatch(value)) 'an uppercase letter',
    if (!RegExp(r'\d').hasMatch(value)) 'a number',
    // Anything but a letter, digit or whitespace counts as a symbol.
    if (!RegExp(r'[^A-Za-z0-9\s]').hasMatch(value)) 'a symbol (e.g. ! @ #)',
  ];
  if (missing.isEmpty) return null;
  if (missing.length == 1) return 'Add ${missing.first}';
  final last = missing.removeLast();
  return 'Add ${missing.join(', ')} and $last';
}

/// One-line summary of the password rules, shown under the password field.
const kPasswordHint =
    'At least $kMinPasswordLength characters, with an uppercase letter, a '
    'lowercase letter, a number and a symbol.';

/// Converts a phone number to the stored 11-digit form, 09XXXXXXXXX.
/// Do not store +639...; it will not fit the 11-digit box when edited.
String normalizePhone(String v) {
  final digits = v.trim().replaceAll(RegExp(r'[\s\-()]'), '');
  if (RegExp(r'^\+?639\d{9}$').hasMatch(digits)) {
    return '0${digits.substring(digits.length - 10)}';
  }
  return digits;
}
