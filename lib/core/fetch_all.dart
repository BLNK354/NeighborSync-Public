import 'package:supabase_flutter/supabase_flutter.dart';

/// Loads every row of a query, a page at a time (the server returns at
/// most 1000 per request). [page] builds the query for one range; give it
/// a stable order (e.g. created_at then id) so pages never overlap or skip.
Future<List<Map<String, dynamic>>> fetchAllRows(
  PostgrestTransformBuilder<PostgrestList> Function(int from, int to) page, {
  int pageSize = 1000,
  int maxRows = 10000,
}) async {
  final rows = <Map<String, dynamic>>[];
  for (var from = 0; from < maxRows; from += pageSize) {
    final chunk = await page(from, from + pageSize - 1);
    rows.addAll(chunk);
    if (chunk.length < pageSize) break;
  }
  return rows;
}
