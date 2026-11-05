import 'package:flutter/material.dart';

/// Sizing helpers for `AlertDialog` content.
///
/// AlertDialog uses about 128px of width on padding, so a fixed-width box
/// overflows on a small phone. Use these instead. On wide screens the
/// preferred size is returned unchanged.

/// Horizontal inset for the dialog itself; smaller on narrow screens.
double dialogInsetH(double screenWidth) => screenWidth < 500 ? 16 : 40;

/// Pass the width the dialog wants; get back the width that fits.
/// The 48 is AlertDialog's own content padding (24 per side).
double dialogContentWidth(BuildContext context, double preferred) {
  final screen = MediaQuery.of(context).size.width;
  final available = screen - (dialogInsetH(screen) * 2) - 48;
  // Never hand a negative width to a SizedBox.
  if (available <= 0) return preferred;
  return available < preferred ? available : preferred;
}

/// Use as `insetPadding:` so the dialog narrows on a phone.
/// Do not add the keyboard inset here; Dialog already adds it, and doing it
/// twice squeezes the form.
EdgeInsets dialogInset(BuildContext context) => EdgeInsets.symmetric(
      horizontal: dialogInsetH(MediaQuery.of(context).size.width),
      vertical: 24,
    );

/// Caps a dialog's scrolling body to a share of the screen height, so it
/// still fits in landscape with the keyboard up.
double dialogMaxHeight(BuildContext context, double preferred) {
  final h = MediaQuery.of(context).size.height * 0.42;
  return h < preferred ? h : preferred;
}
