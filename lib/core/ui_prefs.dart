/// Per-device UI preferences: whether the officer sidebar is collapsed, and
/// whether this browser has seen the storage notice. Not stored on the account.
///
/// Picks the web or non-web version by import, since `web/web.dart` cannot
/// be imported on Android.
library;

export 'ui_prefs_io.dart' if (dart.library.js_interop) 'ui_prefs_web.dart';
