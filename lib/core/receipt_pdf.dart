import 'phase_contacts.dart';
import '../widgets/phase_scope.dart' show phaseNumberOf;
import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'branding.dart';
import 'text_utils.dart';

/// Builds and opens the printable slip for one bill.
///
/// It is an Official Receipt when a verified payment exists, otherwise a
/// Statement of Account (same layout, no OR number).
/// Layout: brand header, big amount, dotted divider, then the details.
class ReceiptPdf {
  /// A5 portrait page with no margin.
  static const _page = PdfPageFormat(
    148 * PdfPageFormat.mm,
    210 * PdfPageFormat.mm,
    marginAll: 0,
  );

  /// Converts a Flutter color (r/g/b are 0..1 doubles) to a PDF color.
  static PdfColor _pdf(Color c) => PdfColor(c.r, c.g, c.b);

  /// Uses `PHP`, not `₱`: the PDF font has no peso glyph (prints a blank box).
  static String _peso(Object? v) => formatPeso(v, symbol: 'PHP ');

  /// Date part only, or a dash when empty.
  static String _date(Object? v) {
    final s = (v ?? '').toString();
    if (s.isEmpty) return '—';
    return s.split('T').first;
  }

  /// [bill] is the row from `bills` (with `resident` and `lot` embedded).
  /// [payments] is that bill's payment rows, newest first.
  static Future<void> open({
    required Map<String, dynamic> bill,
    required List<Map<String, dynamic>> payments,
  }) async {
    final b = AppBranding.instance;
    final brand = _pdf(b.primaryColor);

    // Contact lines: the bill's phase office first, the subdivision's for blanks.
    var contact = [b.contactAddress, b.contactPhone, b.contactEmail];
    final billPhase = (bill['phase'] ?? '').toString();
    if (billPhase.isNotEmpty) {
      try {
        final pc = (await loadPhaseContacts())[phaseNumberOf(billPhase)];
        if (pc != null) {
          String pick(String own, String sub) =>
              own.trim().isNotEmpty ? own : sub;
          contact = [
            pick(pc.address, b.contactAddress),
            pick(pc.phone, b.contactPhone),
            pick(pc.email, b.contactEmail),
          ];
        }
      } catch (_) {
        // A receipt must not fail over a contact line.
      }
    }

    // Only verified payments count as paid; unverified ones give no receipt.
    final settled =
        payments.where((p) => (p['status'] ?? '') == 'verified').toList();
    final paid = settled.fold<double>(
        0, (s, p) => s + (num.tryParse('${p['amount_paid'] ?? 0}') ?? 0));

    final amount = num.tryParse('${bill['amount'] ?? 0}') ?? 0;
    final penalty = num.tryParse('${bill['penalty_amount'] ?? 0}') ?? 0;
    final discount = num.tryParse('${bill['discount_amount'] ?? 0}') ?? 0;
    final total = amount + penalty - discount;
    final balance = total - paid;

    final isReceipt = settled.isNotEmpty;
    final latest = settled.isEmpty ? null : settled.first;

    final resident = bill['resident'] as Map<String, dynamic>?;
    final name = resident == null
        ? '—'
        : [resident['first_name'], resident['last_name']]
            .where((s) => s != null)
            .join(' ');
    final lotNo = (bill['lot'] as Map<String, dynamic>?)?['lot_number'];

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: _page,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _header(b, brand, isReceipt),
            _amountBlock(brand, isReceipt, isReceipt ? paid : balance,
                isReceipt ? 'Amount paid' : 'Amount due'),
            _tornEdge(brand),
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(28, 20, 28, 0),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    if (isReceipt)
                      _row('OR number', (latest?['or_number'] ?? '—').toString(),
                          bold: true),
                    _row('Bill number', (bill['bill_number'] ?? '—').toString(),
                        bold: !isReceipt),
                    _row('Billed to', name),
                    if (lotNo != null) _row('Lot', 'Lot #$lotNo'),
                    _row('For', (bill['description'] ?? '—').toString()),
                    _row('Due date', _date(bill['due_date'])),
                    if (isReceipt) ...[
                      _row('Paid on', _date(latest?['payment_date'])),
                      _row('Method',
                          (latest?['payment_method'] ?? '—').toString()),
                      if ((latest?['reference_number'] ?? '')
                          .toString()
                          .isNotEmpty)
                        _row('Reference',
                            (latest?['reference_number']).toString()),
                    ],
                    pw.SizedBox(height: 10),
                    pw.Divider(color: PdfColors.grey300, height: 1),
                    pw.SizedBox(height: 10),
                    _row('Amount', _peso(amount)),
                    if (penalty > 0) _row('Penalty', _peso(penalty)),
                    if (discount > 0) _row('Discount', '-${_peso(discount)}'),
                    _row('Total', _peso(total), bold: true),
                    if (paid > 0) _row('Paid', _peso(paid)),
                    _row(isReceipt && balance <= 0 ? 'Balance' : 'Balance due',
                        _peso(balance < 0 ? 0 : balance),
                        bold: true,
                        color: balance > 0 ? PdfColors.red800 : brand),
                  ],
                ),
              ),
            ),
            _footer(contact, isReceipt),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: isReceipt
          ? 'Receipt-${latest?['or_number'] ?? bill['bill_number']}'
          : 'Statement-${bill['bill_number']}',
    );
  }

  /// Coloured top band with the monogram, community name and title.
  static pw.Widget _header(AppBranding b, PdfColor brand, bool isReceipt) {
    return pw.Container(
      // Full width is needed or the band stops short of the page edge.
      width: double.infinity,
      color: brand,
      padding: const pw.EdgeInsets.fromLTRB(28, 26, 28, 22),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Monogram, not the logo image, so printing works offline.
          pw.Container(
            width: 34,
            height: 34,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(b.logoMonogram,
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold, color: brand)),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(b.communityName,
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white)),
                pw.SizedBox(height: 2),
                pw.Text(
                    isReceipt ? 'OFFICIAL RECEIPT' : 'STATEMENT OF ACCOUNT',
                    style: const pw.TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.4,
                        color: PdfColors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Large amount with a PAID / UNPAID tag.
  static pw.Widget _amountBlock(
      PdfColor brand, bool isReceipt, num value, String label) {
    return pw.Container(
      width: double.infinity,
      color: brand,
      padding: const pw.EdgeInsets.only(bottom: 26),
      child: pw.Column(
        children: [
          pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 9, letterSpacing: 0.8, color: PdfColors.white)),
          pw.SizedBox(height: 6),
          pw.Text(_peso(value),
              style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white)),
          pw.SizedBox(height: 10),
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              // Keep the radius under half the box height or the corners cross.
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(isReceipt ? 'PAID' : 'UNPAID',
                style: pw.TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.2,
                    fontWeight: pw.FontWeight.bold,
                    color: brand)),
          ),
        ],
      ),
    );
  }

  /// Dotted divider under the header. Kept as small dots because the PDF
  /// library does not clip oversized shapes.
  static pw.Widget _tornEdge(PdfColor brand) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 34; i++)
            pw.Container(
              width: 3,
              height: 3,
              decoration: pw.BoxDecoration(
                color: brand,
                borderRadius: pw.BorderRadius.circular(1.5),
              ),
            ),
        ],
      ),
    );
  }

  /// One label and value line.
  static pw.Widget _row(String label, String value,
      {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Text(label,
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey600)),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Text(value,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: color ?? PdfColors.black,
                )),
          ),
        ],
      ),
    );
  }

  /// Contact line, disclaimer and the time it was generated.
  static pw.Widget _footer(List<String> lines, bool isReceipt) {
    final contact = [
      for (final l in lines)
        if (l.trim().isNotEmpty) l.trim(),
    ].join('  ·  ');

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(28, 14, 28, 22),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Divider(color: PdfColors.grey300, height: 1),
          pw.SizedBox(height: 10),
          if (contact.isNotEmpty) ...[
            pw.Text(contact,
                textAlign: pw.TextAlign.center,
                style:
                    const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
            pw.SizedBox(height: 6),
          ],
          pw.Text(
            isReceipt
                ? 'This is a system-generated receipt. Keep it for your records.'
                : 'This is a statement of account, not a receipt. It is not '
                    'proof of payment.',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
              'Generated '
              '${DateTime.now().toIso8601String().split('.').first.replaceFirst('T', ' ')}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
        ],
      ),
    );
  }
}
