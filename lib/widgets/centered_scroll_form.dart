import 'package:flutter/material.dart';

/// Centers a form vertically and scrolls when the keyboard covers it, so the
/// focused field stays visible. Use instead of Center + SingleChildScrollView.
class CenteredScrollForm extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  const CenteredScrollForm({
    super.key,
    required this.child,
    this.maxWidth = 460,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
  });

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          // Bottom space the size of the keyboard, so the field can scroll up.
          padding: EdgeInsets.only(bottom: keyboard),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
