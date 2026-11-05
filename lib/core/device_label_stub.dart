import 'package:flutter/foundation.dart';

/// Labels the device by its platform, since there is no browser to read.
String currentDeviceLabel() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'Android device';
    case TargetPlatform.iOS:
      return 'iPhone / iPad';
    case TargetPlatform.windows:
      return 'Windows PC';
    case TargetPlatform.macOS:
      return 'Mac';
    case TargetPlatform.linux:
      return 'Linux';
    default:
      return 'This device';
  }
}
