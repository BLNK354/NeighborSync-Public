import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Shows a PDF full screen inside the app, with a close button.
/// Used instead of a new browser tab, which phones block as a pop-up.
/// Print and share stay on; share is how people save the file.
Future<void> showPdfViewer(
  BuildContext context, {
  required Uint8List bytes,
  String? name,
}) {
  final title = (name ?? '').trim();
  return showDialog<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            title.isEmpty ? 'Document' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        body: PdfPreview(
          build: (_) async => bytes,
          pdfFileName: title.isEmpty ? 'document.pdf' : title,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          useActions: true,
          allowPrinting: true,
          allowSharing: true,
        ),
      ),
    ),
  );
}
