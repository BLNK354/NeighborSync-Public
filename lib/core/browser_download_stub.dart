/// Non-web version of [triggerBrowserDownload]. Always throws, since
/// downloads only work in the web build.
void triggerBrowserDownload(String fileName, List<int> bytes, {String mimeType = 'application/octet-stream'}) {
  throw UnsupportedError('Local backup download is only available in the web build.');
}
