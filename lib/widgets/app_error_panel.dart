import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Replaces the blank grey box Flutter shows for a widget that failed to
/// build (release builds only) with a short message.
/// Debug builds keep the red error screen, which names the broken widget.
void installAppErrorPanel() {
  if (kDebugMode) return;
  ErrorWidget.builder = (FlutterErrorDetails details) => const _AppErrorPanel();
}

class _AppErrorPanel extends StatelessWidget {
  const _AppErrorPanel();

  @override
  Widget build(BuildContext context) {
    // Must not use Theme, MediaQuery or Material: it is built when the tree is broken.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        color: const Color(0xFFF3F6F4),
        child: const Text(
          'This part of the page could not be shown.\n'
          'Go back and open it again, or reload the page.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: Color(0xFF5F6B66),
            decoration: TextDecoration.none,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
