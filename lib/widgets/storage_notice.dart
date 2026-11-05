import 'package:flutter/material.dart';

import '../core/branding.dart';
import '../core/ui_prefs.dart';
import '../theme/app_theme.dart';
import '../core/safe_state.dart';

/// One-time bar saying what this site keeps in the browser and why.
///
/// It is a notice, not a consent choice: only the sign-in session and two
/// interface settings are stored, all needed. If tracking is ever added,
/// add a real choice here.
class StorageNotice extends StatefulWidget {
  /// Opens the privacy notice. The caller supplies it because this widget
  /// sits above the Navigator, where `context.push` cannot find a router.
  final VoidCallback? onReadMore;

  const StorageNotice({super.key, this.onReadMore});

  @override
  State<StorageNotice> createState() => _StorageNoticeState();
}

class _StorageNoticeState extends State<StorageNotice> with SafeSetState<StorageNotice> {
  // Read once here, not in build(), to avoid re-reading storage on rebuilds.
  late bool _dismissed = readStorageNoticeSeen();

  Widget _message(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 12.5, height: 1.5, color: Color(0xFFE8EAE9)),
      );

  void _dismiss() {
    writeStorageNoticeSeen();
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: AppBranding.instance,
      builder: (context, _) {
        final text = AppBranding.instance.storageNotice.trim();
        // No notice text published yet: show nothing.
        if (text.isEmpty) return const SizedBox.shrink();

        final narrow = MediaQuery.of(context).size.width < 700;
        return Material(
          color: const Color(0xFF1F2421),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment:
                    narrow ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  // Flexible only when horizontal: a flexible child asserts
                  // when the height is unbounded.
                  if (narrow)
                    _message(text)
                  else
                    Flexible(child: _message(text)),
                  SizedBox(width: narrow ? 0 : 16, height: narrow ? 8 : 0),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Only shown when there is a privacy notice to read.
                      if (widget.onReadMore != null &&
                          AppBranding.instance.hasPrivacy) ...[
                        TextButton(
                          onPressed: widget.onReadMore,
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFFE08A)),
                          child: const Text('Read more',
                              style: TextStyle(fontSize: 12.5)),
                        ),
                        const SizedBox(width: 4),
                      ],
                      FilledButton(
                        onPressed: _dismiss,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.sidebarActiveText,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        ),
                        child: const Text('Got it', style: TextStyle(fontSize: 12.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
