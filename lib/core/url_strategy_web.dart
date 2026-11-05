import 'package:flutter_web_plugins/url_strategy.dart';

/// Switches the web build from hash URLs (`/#/admin/billing`) to real paths.
/// Required: email reset and verification links are plain paths and would
/// lose their token under hash URLs. The server must serve index.html for
/// unknown paths (see vercel.json).
void useCleanUrls() {
  usePathUrlStrategy();
}
