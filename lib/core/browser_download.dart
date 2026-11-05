// Saves a file from the browser on web; throws on other targets.
export 'browser_download_stub.dart' if (dart.library.html) 'browser_download_web.dart';
