/// Sort order for addresses: phase, then block, then lot. Numbers compare as
/// numbers, so "Block 9" comes before "Block 10".
library;

/// Compares two strings, treating runs of digits as numbers.
int compareNatural(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final pa = re.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i], y = pb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

/// Phase, block, lot. Any of them may be null; blanks sort last.
int compareAddress(
  Object? phaseA, Object? blockA, Object? lotA,
  Object? phaseB, Object? blockB, Object? lotB,
) {
  int part(Object? x, Object? y) {
    final a = (x ?? '').toString().trim(), b = (y ?? '').toString().trim();
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;
    return compareNatural(a, b);
  }

  final p = part(phaseA, phaseB);
  if (p != 0) return p;
  final bl = part(blockA, blockB);
  if (bl != 0) return bl;
  return part(lotA, lotB);
}

/// Sorts lot rows shaped like `{lot_number, blocks: {block_name, phase}}`
/// (the embed every lot picker selects) or with `phase` on the lot itself.
int compareLotRows(Map<String, dynamic> a, Map<String, dynamic> b) {
  Map<String, dynamic>? bl(Map<String, dynamic> r) =>
      (r['blocks'] ?? r['block']) as Map<String, dynamic>?;
  return compareAddress(
    bl(a)?['phase'] ?? a['phase'], bl(a)?['block_name'], a['lot_number'],
    bl(b)?['phase'] ?? b['phase'], bl(b)?['block_name'], b['lot_number'],
  );
}

/// Sorts phase rows ('code' and/or 'number') so Phase 9 comes before Phase 10.
List<Map<String, dynamic>> sortPhaseRows(Iterable rows) {
  String key(Map m) => (m['code'] ?? m['number'] ?? '').toString();
  return [for (final r in rows) Map<String, dynamic>.from(r as Map)]
    ..sort((a, b) => compareNatural(key(a), key(b)));
}
