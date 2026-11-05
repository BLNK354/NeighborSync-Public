/// Turns a raw DB-style value like `in_progress` or `pending_verification`
/// into a display string like "In Progress" or "Pending Verification".
/// For display only; never use the result as a stored value.
String titleCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}

/// Money, with thousands separators and two decimals: `₱1,250.00`.
///
/// Pass `symbol: 'PHP '` for PDFs, whose font has no ₱ glyph.
String formatPeso(Object? value, {String symbol = '₱'}) {
  final n = num.tryParse((value ?? '0').toString()) ?? 0;
  final parts = n.abs().toStringAsFixed(2).split('.');
  final digits = parts[0].split('').reversed.toList();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && i % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final whole = buf.toString().split('').reversed.join();
  return '${n < 0 ? '-' : ''}$symbol$whole.${parts[1]}';
}

/// `johnsmith123@example.com` -> `jo********23@example.com`.
///
/// Keeps the first two and last two characters of the name part and stars
/// the middle; the domain is left alone. Short names show less (3-4
/// characters keep one, 2 or fewer keep none) so nothing is fully revealed.
/// Hides the address from onlookers only; it is not a security control.
String maskEmail(String email) {
  final trimmed = email.trim();
  if (trimmed.isEmpty) return '';

  // lastIndexOf: a quoted name part may contain '@', and the first one would
  // leave part of the name unmasked.
  final at = trimmed.lastIndexOf('@');

  // No '@': mask everything.
  if (at <= 0) return '*' * trimmed.length;

  return '${_maskLocalPart(trimmed.substring(0, at))}${trimmed.substring(at)}';
}

/// Masks the part of an email before the '@'.
String _maskLocalPart(String local) {
  final n = local.length;
  if (n <= 2) return '*' * n;
  if (n <= 4) return '${local[0]}${'*' * (n - 1)}';
  return '${local.substring(0, 2)}${'*' * (n - 4)}${local.substring(n - 2)}';
}
