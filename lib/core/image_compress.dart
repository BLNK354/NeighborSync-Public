import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Shrinks an image before upload so large phone photos do not eat storage
/// or time out on slow connections.
///
/// Best-effort: if anything fails (unsupported format, corrupt file) the
/// original bytes are returned instead of throwing.

/// Longest-edge size caps for each kind of image, in pixels.
const int kMaxAvatarEdge = 512;
const int kMaxPhotoEdge = 1600;
const int kMaxSurveyPlanEdge = 2400;

/// Longest-edge cap for payment QR codes. Use with `lossless: true`: JPEG
/// blurs the hard edges and can make a QR code unscannable.
const int kMaxQrEdge = 1000;

/// Files at or below this size are passed through untouched.
const int kSkipCompressionBelowBytes = 300 * 1024;

/// True when the filename looks like an image this can handle. Checked by
/// name because callers also pass PDFs, which must be uploaded unchanged.
bool isCompressibleImage(String filename) {
  final f = filename.toLowerCase();
  return f.endsWith('.jpg') ||
      f.endsWith('.jpeg') ||
      f.endsWith('.png') ||
      f.endsWith('.webp') ||
      f.endsWith('.bmp') ||
      f.endsWith('.tif') ||
      f.endsWith('.tiff');
}

/// The bytes to upload and the filename to store them under. The extension
/// follows the encoded format, so the content type matches.
class CompressedImage {
  final Uint8List bytes;
  final String filename;

  /// False when the original was returned unchanged.
  final bool wasCompressed;

  const CompressedImage(this.bytes, this.filename, this.wasCompressed);
}

/// Resizes [bytes] so the longest edge is at most [maxEdge] and re-encodes
/// as JPEG at [quality]. Images with transparency, or any image when
/// [lossless] is true, are kept as PNG.
///
/// Returns the original when the file is small, not an image, cannot be
/// decoded, or the result is not smaller.
CompressedImage compressImageBytes(
  Uint8List bytes,
  String filename, {
  int maxEdge = kMaxPhotoEdge,
  int quality = 82,
  bool lossless = false,
}) {
  if (!isCompressibleImage(filename)) {
    return CompressedImage(bytes, filename, false);
  }
  if (bytes.lengthInBytes <= kSkipCompressionBelowBytes) {
    return CompressedImage(bytes, filename, false);
  }

  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return CompressedImage(bytes, filename, false);

    // Only scales down, never up.
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longest > maxEdge
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxEdge : null,
            height: decoded.height > decoded.width ? maxEdge : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    // JPEG cannot hold transparency (a logo would get a black background),
    // so anything with alpha stays PNG. Alpha is channel 2 (grey+alpha) or
    // channel 4 (RGBA); check both. [lossless] also forces PNG.
    final hasAlpha = resized.numChannels == 2 || resized.numChannels == 4;
    final asPng = lossless || hasAlpha;

    // Widen greyscale to RGB before JPEG: the encoder reads r, g and b, and
    // a one-channel image gives zero for g and b, so it would come out red.
    final forJpeg =
        resized.numChannels < 3 ? resized.convert(numChannels: 3) : resized;

    final out = asPng
        ? img.encodePng(resized, level: 6)
        : img.encodeJpg(forJpeg, quality: quality);

    if (out.lengthInBytes >= bytes.lengthInBytes) {
      // No saving: keep the original.
      return CompressedImage(bytes, filename, false);
    }
    return CompressedImage(
      out,
      asPng ? _withExtension(filename, 'png') : _withExtension(filename, 'jpg'),
      true,
    );
  } catch (_) {
    // Could not process it: upload the original.
    return CompressedImage(bytes, filename, false);
  }
}

/// Swaps the extension to match what was actually encoded.
String _withExtension(String filename, String ext) {
  final dot = filename.lastIndexOf('.');
  final stem = dot <= 0 ? filename : filename.substring(0, dot);
  return '$stem.$ext';
}
