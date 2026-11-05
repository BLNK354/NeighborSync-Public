/// Visitor purposes, their default allotted time, and the overstay check.
///
/// The gate screen and the visitor lists share this so they agree on who is
/// overstaying. Times are generous on purpose.
library;

/// Category -> label shown in the UI.
const kVisitorPurposeLabels = <String, String>{
  'visitor': 'Visitor / Guest',
  'delivery': 'Delivery',
  'service': 'Home Service / Repair',
  'contractor': 'Contractor',
  'household_help': 'Household Help',
  'viewing': 'Property Viewing',
  'other': 'Other',
};

/// Category -> default allotted minutes (a delivery is short, a contractor
/// stays a work day).
const kVisitorAllottedMinutes = <String, int>{
  'delivery': 30,
  'viewing': 90,
  'service': 240,
  'contractor': 480, // a working day
  'household_help': 600,
  'visitor': 720, // most of a day -- guests are not clock-watched
  'other': 240,
};

/// Allotted minutes for a purpose; 240 when unknown.
int kAllottedMinutesFor(String? purposeType) =>
    kVisitorAllottedMinutes[purposeType] ?? 240;

/// Display label for a purpose; "Visitor" when unknown.
String visitorPurposeLabel(String? purposeType) =>
    kVisitorPurposeLabels[purposeType] ?? 'Visitor';

/// Whether the purpose is a delivery (shown separately in the gate list).
bool isDelivery(String? purposeType) => purposeType == 'delivery';

/// When this entry is due to leave, or null if it can't be determined.
DateTime? expectedOut(Map<String, dynamic> log) {
  final tIn = DateTime.tryParse((log['time_in'] ?? '').toString());
  if (tIn == null) return null;
  final mins = (log['expected_minutes'] as num?)?.toInt() ??
      kAllottedMinutesFor(log['purpose_type']?.toString());
  return tIn.add(Duration(minutes: mins));
}

/// True when the visitor is still inside and past their allotted time.
/// Anyone already checked out is never overstaying.
bool isOverstaying(Map<String, dynamic> log, {DateTime? now}) {
  if (log['time_out'] != null) return false;
  final due = expectedOut(log);
  if (due == null) return false;
  return (now ?? DateTime.now()).isAfter(due);
}

/// How long past the allotted time, or null when not overstaying.
Duration? overstayBy(Map<String, dynamic> log, {DateTime? now}) {
  if (!isOverstaying(log, now: now)) return null;
  final due = expectedOut(log)!;
  return (now ?? DateTime.now()).difference(due);
}

/// Short human label for an overstay, e.g. "2h 15m over".
String overstayLabel(Map<String, dynamic> log, {DateTime? now}) {
  final d = overstayBy(log, now: now);
  if (d == null) return '';
  if (d.inMinutes < 60) return '${d.inMinutes}m over';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return m == 0 ? '${h}h over' : '${h}h ${m}m over';
}
