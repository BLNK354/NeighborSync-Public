import 'package:web/web.dart' as web;

/// Builds an "OS · Browser" label from the browser's user-agent text.
String currentDeviceLabel() {
  final ua = web.window.navigator.userAgent;
  final u = ua.toLowerCase();

  String os;
  if (u.contains('iphone')) {
    os = 'iPhone';
  } else if (u.contains('ipad')) {
    os = 'iPad';
  } else if (u.contains('android')) {
    os = 'Android';
  } else if (u.contains('windows')) {
    os = 'Windows PC';
  } else if (u.contains('macintosh') || u.contains('mac os')) {
    os = 'Mac';
  } else if (u.contains('linux')) {
    os = 'Linux';
  } else {
    os = 'Web';
  }

  String browser;
  if (u.contains('fban') || u.contains('fbav') || u.contains('messenger')) {
    browser = 'Facebook';
  } else if (u.contains('edg/')) {
    browser = 'Edge';
  } else if (u.contains('firefox')) {
    browser = 'Firefox';
  } else if (u.contains('crios') || (u.contains('chrome') && !u.contains('edg/'))) {
    browser = 'Chrome';
  } else if (u.contains('safari')) {
    browser = 'Safari';
  } else {
    browser = 'Browser';
  }

  return '$os · $browser';
}
