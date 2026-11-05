/// Teardrop map marker, shared by the officer Community Map and the public
/// visitor map.
///
/// The point at the bottom is the location. Place a [MapPin] by its tip
/// using [offsetForTip].
library;

import 'package:flutter/material.dart';

/// Pin height as a multiple of its width.
const double kMapPinHeightFactor = 1.32;

/// A teardrop pin filled with [color]; tappable when [onTap] is set.
class MapPin extends StatelessWidget {
  final Color color;
  final VoidCallback? onTap;

  /// Width, already divided by the map zoom so the pin stays the same size on screen.
  final double size;

  /// The map's current zoom. Outline and shadow are divided by it, or they
  /// look [scale] times too heavy.
  final double scale;

  const MapPin({
    super.key,
    required this.color,
    this.onTap,
    this.size = 28,
    this.scale = 1,
  });

  /// Where to place the widget's top-left so its tip lands on [tip].
  static Offset offsetForTip(Offset tip, double size) =>
      Offset(tip.dx - size / 2, tip.dy - size * kMapPinHeightFactor);

  @override
  Widget build(BuildContext context) {
    final h = size * kMapPinHeightFactor;
    // See [scale].
    final onScreen = size * scale;
    final stroke = ((onScreen / 12).clamp(1.5, 3.5)) / scale;
    final pin = CustomPaint(
      size: Size(size, h),
      painter: _TeardropPainter(
        color: color,
        stroke: stroke,
        blur: 4 / scale,
        dy: 1.5 / scale,
      ),
    );
    if (onTap == null) return SizedBox(width: size, height: h, child: pin);
    return SizedBox(
      width: size,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: pin,
      ),
    );
  }
}

/// Draws the teardrop with a white outline, shadow and centre hole.
class _TeardropPainter extends CustomPainter {
  final Color color;
  final double stroke;
  final double blur;
  final double dy;

  _TeardropPainter({
    required this.color,
    required this.stroke,
    required this.blur,
    required this.dy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Inset by the outline so it isn't clipped at the edges.
    final r = (w / 2) - stroke / 2;
    final cx = w / 2;
    final cy = r + stroke / 2;
    final tipY = h - stroke / 2;

    final path = Path()..moveTo(cx, tipY);
    // Left side, tip up to the head.
    path.cubicTo(cx - r * 0.62, tipY - r * 0.95, cx - r, cy + r * 0.78, cx - r, cy);
    // Head.
    path.arcToPoint(Offset(cx + r, cy), radius: Radius.circular(r), clockwise: true);
    // Right side, back down to the tip.
    path.cubicTo(cx + r, cy + r * 0.78, cx + r * 0.62, tipY - r * 0.95, cx, tipY);
    path.close();

    canvas.drawShadow(path.shift(Offset(0, dy)), const Color(0x66000000), blur, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    // Centre hole, so the pin stays readable on a busy map.
    canvas.drawCircle(Offset(cx, cy), r * 0.36, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _TeardropPainter old) =>
      old.color != color || old.stroke != stroke || old.blur != blur || old.dy != dy;
}
