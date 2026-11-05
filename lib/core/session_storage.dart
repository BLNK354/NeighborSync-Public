/// Uses the web storage on web and the phone/desktop one elsewhere.
library;

export 'session_storage_io.dart'
    if (dart.library.js_interop) 'session_storage_web.dart';
