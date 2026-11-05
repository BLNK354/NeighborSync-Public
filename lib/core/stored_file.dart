import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/supabase_service.dart';
import '../widgets/image_lightbox.dart';
import '../widgets/pdf_viewer_dialog.dart';
import 'browser_download.dart';

/// Opens a stored file without sending the browser to the storage address.
///
/// Pictures and PDFs open in the in-app viewer; anything else is downloaded.
/// This only hides the address; the Storage policies are what protect files.
///
/// Give either [path] (a file in [bucket], read with the caller's own
/// permissions) or [publicUrl] (a file in a public bucket). Throws when the
/// file cannot be fetched, so each caller can show its own error.
Future<void> openStoredFile(
  BuildContext context, {
  String bucket = 'documents',
  String? path,
  String? publicUrl,
  String? name,
  String? mimeType,
}) async {
  final pub = (publicUrl ?? '').trim();
  final hasPath = path != null && path.isNotEmpty;
  if (pub.isEmpty && !hasPath) return;

  final storage = SupabaseService.instance.client.storage.from(bucket);
  var kind = _kindFrom(mimeType) ?? _kindFromName(name) ?? _kindFromName(path) ?? _kindFromName(pub);

  // A known picture needs no download; the viewer loads it directly.
  if (kind == _Kind.image) {
    final url = pub.isNotEmpty ? pub : await storage.createSignedUrl(path!, 300);
    if (!context.mounted) return;
    await showImageLightbox(context, imageUrl: url, semanticLabel: name);
    return;
  }

  // Outside the browser, just open the link.
  if (!kIsWeb) {
    final url = pub.isNotEmpty ? pub : await storage.createSignedUrl(path!, 300);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return;
  }

  // Links to other sites cannot be fetched from here, so just open them.
  if (pub.isNotEmpty && !pub.contains('/storage/v1/object/')) {
    await launchUrl(Uri.parse(pub), webOnlyWindowName: '_blank');
    return;
  }

  final Uint8List bytes;
  if (pub.isNotEmpty) {
    try {
      bytes = await http.readBytes(Uri.parse(pub));
    } catch (_) {
      // If the in-app fetch fails, open the link so the button still works.
      await launchUrl(Uri.parse(pub), webOnlyWindowName: '_blank');
      return;
    }
  } else {
    bytes = await storage.download(path!);
  }
  kind ??= _sniff(bytes);

  if (kind == _Kind.image) {
    if (!context.mounted) return;
    await showImageLightbox(context, bytes: bytes, semanticLabel: name);
    return;
  }
  if (kind == _Kind.pdf) {
    if (!context.mounted) return;
    await showPdfViewer(context, bytes: bytes, name: _fileName(name, path, pub));
    return;
  }
  triggerBrowserDownload(
    _fileName(name, path, pub),
    bytes,
    mimeType: mimeType ?? 'application/octet-stream',
  );
}

enum _Kind { image, pdf, other }

_Kind? _kindFrom(String? mime) {
  final m = (mime ?? '').toLowerCase();
  if (m.isEmpty) return null;
  if (m.startsWith('image/')) return _Kind.image;
  if (m == 'application/pdf') return _Kind.pdf;
  return _Kind.other;
}

_Kind? _kindFromName(String? value) {
  var v = (value ?? '').toLowerCase();
  if (v.isEmpty) return null;
  // Drop a link's query string ("...photo.jpg?v=123") before reading the end.
  final q = v.indexOf('?');
  if (q >= 0) v = v.substring(0, q);
  final dot = v.lastIndexOf('.');
  if (dot < 0 || dot == v.length - 1) return null;
  switch (v.substring(dot + 1)) {
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
    case 'bmp':
      return _Kind.image;
    case 'pdf':
      return _Kind.pdf;
    case 'doc':
    case 'docx':
    case 'xls':
    case 'xlsx':
    case 'csv':
    case 'txt':
    case 'zip':
      return _Kind.other;
  }
  return null;
}

/// Guesses the file type from its first bytes.
_Kind _sniff(Uint8List b) {
  bool starts(List<int> sig) {
    if (b.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[i] != sig[i]) return false;
    }
    return true;
  }

  if (starts(const [0x25, 0x50, 0x44, 0x46])) return _Kind.pdf; // %PDF
  if (starts(const [0x89, 0x50, 0x4E, 0x47])) return _Kind.image; // PNG
  if (starts(const [0xFF, 0xD8, 0xFF])) return _Kind.image; // JPEG
  if (starts(const [0x47, 0x49, 0x46, 0x38])) return _Kind.image; // GIF
  if (b.length > 11 && starts(const [0x52, 0x49, 0x46, 0x46]) && b[8] == 0x57 && b[9] == 0x45) {
    return _Kind.image; // WEBP
  }
  return _Kind.other;
}

/// Picks a name for the download: the given name, else the end of the path or link.
String _fileName(String? name, String? path, String pub) {
  final n = (name ?? '').trim();
  if (n.isNotEmpty) return n;
  var tail = (path != null && path.isNotEmpty) ? path : pub;
  final q = tail.indexOf('?');
  if (q >= 0) tail = tail.substring(0, q);
  final slash = tail.lastIndexOf('/');
  final last = slash >= 0 ? tail.substring(slash + 1) : tail;
  return last.isEmpty ? 'file' : last;
}
