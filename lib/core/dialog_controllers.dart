import 'package:flutter/foundation.dart';

/// Disposes a dialog's controllers after the dialog has finished closing.
/// Call this instead of `.dispose()` right after `await showDialog(...)`;
/// disposing earlier breaks fields still on screen during the exit animation.
void disposeAfterDialogCloses(List<ChangeNotifier> controllers) {
  Future<void>.delayed(const Duration(milliseconds: 600), () {
    for (final c in controllers) {
      c.dispose();
    }
  });
}
