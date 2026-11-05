/// Reads the first worksheet of an .xlsx file into the same
/// `List<List<String>>` shape the roster importer's CSV parser produces.
///
/// Built on `archive` and `xml`; the `excel` package needs an older `archive`.
///
/// Reads values only: no formatting, merged cells or charts. A formula
/// cell gives its last saved value.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Thrown when the bytes are not a workbook this can read. The message is
/// shown to the officer, so it says what to do rather than what broke.
class XlsxReadException implements Exception {
  final String message;
  const XlsxReadException(this.message);
  @override
  String toString() => message;
}

/// Returns the rows of the first sheet. Files that are not a ZIP (old
/// `.xls`, renamed `.csv`) are refused with a message saying how to fix it.
List<List<String>> readXlsxSheet(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const XlsxReadException(
      'That file is not a readable .xlsx workbook. If it is an older .xls '
      'file, open it in Excel and use Save As to make it .xlsx or .csv.',
    );
  }

  final parts = <String, Uint8List>{};
  for (final f in archive.files) {
    if (f.isFile) {
      final data = f.readBytes();
      if (data != null) parts[f.name] = data;
    }
  }

  final sheetPath = _firstSheetPath(parts);
  if (sheetPath == null) {
    throw const XlsxReadException('That workbook has no worksheets in it.');
  }

  final shared = _sharedStrings(parts);
  return _readSheet(_utf8(parts[sheetPath]!), shared);
}

/// Decodes bytes as UTF-8, tolerating bad bytes.
String _utf8(Uint8List b) =>
    const Utf8Decoder(allowMalformed: true).convert(b);

/// Finds the first sheet (tab order) via `xl/workbook.xml` and its rels.
/// Do not assume `sheet1.xml`: file numbers do not follow tab order.
/// Falls back to the lowest-numbered worksheet.
String? _firstSheetPath(Map<String, Uint8List> parts) {
  try {
    final wb = parts['xl/workbook.xml'];
    final rels = parts['xl/_rels/workbook.xml.rels'];
    if (wb != null && rels != null) {
      final sheet = XmlDocument.parse(_utf8(wb))
          .findAllElements('sheet')
          .cast<XmlElement?>()
          .firstWhere((_) => true, orElse: () => null);
      // Match r:id by local name so the namespace prefix does not matter.
      final rid = sheet?.attributes
          .cast<XmlAttribute?>()
          .firstWhere((a) => a?.name.local == 'id', orElse: () => null)
          ?.value;
      if (rid != null) {
        for (final r in XmlDocument.parse(_utf8(rels))
            .findAllElements('Relationship')) {
          if (r.getAttribute('Id') != rid) continue;
          var target = r.getAttribute('Target') ?? '';
          if (target.isEmpty) break;
          target = target.startsWith('/')
              ? target.substring(1)
              : (target.startsWith('xl/') ? target : 'xl/$target');
          if (parts.containsKey(target)) return target;
          break;
        }
      }
    }
  } catch (_) {
    // Fall through to the numeric fallback below.
  }

  final sheets = parts.keys
      .where((k) => k.startsWith('xl/worksheets/') && k.endsWith('.xml'))
      .toList()
    ..sort();
  return sheets.isEmpty ? null : sheets.first;
}

/// Shared text values, indexed by cells. One entry's text is every `<t>`
/// under it joined, since styled text is split into several runs.
List<String> _sharedStrings(Map<String, Uint8List> parts) {
  final raw = parts['xl/sharedStrings.xml'];
  if (raw == null) return const [];
  try {
    return XmlDocument.parse(_utf8(raw))
        .findAllElements('si')
        .map((si) => si.findAllElements('t').map((t) => t.innerText).join())
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Turns sheet XML into rows, skipping fully blank rows.
List<List<String>> _readSheet(String xml, List<String> shared) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } catch (_) {
    throw const XlsxReadException('That worksheet could not be read.');
  }

  final rows = <List<String>>[];
  for (final row in doc.findAllElements('row')) {
    // Place cells by column letter: empty cells are missing from the file.
    final cells = <int, String>{};
    var widest = -1;
    for (final c in row.findAllElements('c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? cells.length : _columnIndex(ref);
      final value = _cellText(c, shared);
      if (value.isNotEmpty) {
        cells[col] = value;
        if (col > widest) widest = col;
      }
    }
    if (widest < 0) continue; // entirely blank row
    rows.add(List<String>.generate(widest + 1, (i) => cells[i] ?? ''));
  }
  return rows;
}

/// "B" -> 1, "AA" -> 26. Row digits are ignored.
int _columnIndex(String ref) {
  var n = 0;
  for (final unit in ref.toUpperCase().codeUnits) {
    if (unit < 65 || unit > 90) break; // stop at the row digits
    n = n * 26 + (unit - 64);
  }
  return n - 1;
}

/// Returns one cell's value as text.
String _cellText(XmlElement c, List<String> shared) {
  final type = c.getAttribute('t');

  if (type == 's') {
    final i = int.tryParse(c.getElement('v')?.innerText.trim() ?? '');
    return (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
  }
  if (type == 'inlineStr') {
    return c.findAllElements('t').map((t) => t.innerText).join();
  }
  if (type == 'b') {
    return c.getElement('v')?.innerText.trim() == '1' ? 'TRUE' : 'FALSE';
  }

  // 'str' is a formula's cached string result; no type at all is a number.
  final raw = c.getElement('v')?.innerText.trim() ?? '';
  if (type == 'str' || raw.isEmpty) return raw;

  // Print whole numbers without an exponent or ".0" (phone columns).
  final n = double.tryParse(raw);
  if (n != null && n == n.roundToDouble() && n.abs() < 1e15) {
    return n.toStringAsFixed(0);
  }
  return raw;
}
