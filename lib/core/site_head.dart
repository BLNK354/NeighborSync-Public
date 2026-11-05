// Sets the browser tab icon to the community logo. Does nothing outside
// web, so callers need no platform check.
export 'site_head_stub.dart' if (dart.library.html) 'site_head_web.dart';
