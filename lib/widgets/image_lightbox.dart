import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Full-screen image viewer with zoom and a close button.
/// Pass either [imageUrl] or [bytes].
Future<void> showImageLightbox(
  BuildContext context, {
  String? imageUrl,
  /// The picture itself, already downloaded. Used instead of [imageUrl] when
  /// the caller had to fetch the file to learn it was a picture.
  Uint8List? bytes,
  String? semanticLabel,
}) {
  assert(imageUrl != null || bytes != null);
  return showDialog<void>(
    context: context,
    useSafeArea: true,
    barrierColor: Colors.black87,
    builder: (context) {
      return Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            // Tapping anywhere outside the image closes the viewer.
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: SizedBox.expand(
                child: InteractiveViewer(
                  maxScale: 6,
                  child: Center(
                    child: bytes != null
                        ? Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            semanticLabel: semanticLabel,
                            errorBuilder: (_, __, ___) => const Text(
                              'Image could not be loaded.',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          )
                        : Image.network(
                            imageUrl!,
                            fit: BoxFit.contain,
                            semanticLabel: semanticLabel,
                            errorBuilder: (_, __, ___) => const Text(
                              'Image could not be loaded.',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Colors.white, size: 26),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Makes any thumbnail open [showImageLightbox] when tapped, with a hand
/// cursor and a small zoom badge so it reads as clickable.
class TapToPreview extends StatelessWidget {
  final String imageUrl;
  final String? semanticLabel;
  final Widget child;
  const TapToPreview({
    super.key,
    required this.imageUrl,
    required this.child,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Click to enlarge',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => showImageLightbox(context,
              imageUrl: imageUrl, semanticLabel: semanticLabel),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child,
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.zoom_in, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// The photo on an announcement or event, as a banner across the top of
/// its details: rounded, cropped to fill, tap to see it full-screen.
/// Renders nothing when there is no photo.
class PostPhotoBanner extends StatelessWidget {
  final String? url;
  final double height;
  const PostPhotoBanner(this.url, {super.key, this.height = 180});

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    if (u.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TapToPreview(
        imageUrl: u,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            u,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
