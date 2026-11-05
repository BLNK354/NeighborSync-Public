import 'package:flutter/material.dart';
import '../core/branding.dart';

/// The community logo in a circle: the uploaded image, or a letter monogram
/// if none is set or the image fails to load.
class CommunityLogo extends StatelessWidget {
  final double size;
  final Color monogramColor;
  final Color backgroundColor;

  const CommunityLogo({
    super.key,
    required this.size,
    required this.monogramColor,
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final branding = AppBranding.instance;
    final imageUrl = branding.logoImageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    Widget monogram() => Text(
          branding.logoMonogram,
          style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: monogramColor),
        );

    // Same screen-reader label for image and monogram; the raw letters are hidden.
    return Semantics(
      image: true,
      label: '${branding.communityName} logo',
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: hasImage
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => monogram(),
                )
              : monogram(),
        ),
      ),
    );
  }
}
