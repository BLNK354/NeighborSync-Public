/// Turns a stored timestamp into a local calendar day.
///
/// Timestamps parse as UTC, so always call `.toLocal()` before comparing
/// year/month/day to `DateTime.now()`; otherwise early-morning entries land
/// on the wrong day. (For writes, send `.toUtc()`.)
///
/// Do not use these on `date` columns (e.g. `bills.due_date`): they have no
/// zone and must not be converted.
library;

/// Parses a stored timestamp and moves it into the device's zone.
///
/// Returns null for null, empty or unparseable input.
DateTime? localTime(dynamic value) {
  final s = (value ?? '').toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

/// Whether a stored timestamp falls on today's local calendar day.
bool isToday(dynamic value, {DateTime? now}) {
  final t = localTime(value);
  if (t == null) return false;
  final n = now ?? DateTime.now();
  return t.year == n.year && t.month == n.month && t.day == n.day;
}

/// Whether a stored timestamp falls in the current local calendar month.
bool isThisMonth(dynamic value, {DateTime? now}) {
  final t = localTime(value);
  if (t == null) return false;
  final n = now ?? DateTime.now();
  return t.year == n.year && t.month == n.month;
}
