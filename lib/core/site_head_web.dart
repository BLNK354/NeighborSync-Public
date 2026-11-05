import 'package:web/web.dart' as web;

/// Sets the browser tab icon to [url] (the community logo).
/// Does nothing when [url] is null or empty, so the default icon stays.
void applyFavicon(String? url) {
  if (url == null || url.isEmpty) return;
  final head = web.document.head;
  if (head == null) return;
  var link = web.document.querySelector("link[rel~='icon']") as web.HTMLLinkElement?;
  if (link == null) {
    link = web.document.createElement('link') as web.HTMLLinkElement;
    link.rel = 'icon';
    head.appendChild(link);
  }
  link.href = url;
}
