import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [bytes] as a file named [fileName] through the browser's
/// download, with no server involved.
void triggerBrowserDownload(String fileName, List<int> bytes, {String mimeType = 'application/octet-stream'}) {
  final jsBytes = Uint8List.fromList(bytes).toJS;
  final blob = web.Blob(<JSAny>[jsBytes].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
