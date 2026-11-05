// Short label for this device, like "iPhone · Safari", used to tag login
// sessions. Web reads the browser; other builds use the platform name.
export 'device_label_stub.dart' if (dart.library.html) 'device_label_web.dart';
