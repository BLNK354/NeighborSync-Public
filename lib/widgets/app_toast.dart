import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../core/safe_state.dart';

/// Small pop-up card with a green check or red X, a title and a message.
/// It closes itself after a few seconds.
/// Use: `AppToast.success(context, message: 'Settings saved.')`.
class AppToast {
  AppToast._();

  static OverlayEntry? _current;

  /// Green check-circle toast for a completed action.
  static void success(BuildContext context, {required String message, String title = 'Done!'}) {
    _show(context, title: title, message: message, isError: false);
  }

  /// Red X-circle toast for a failed action.
  static void error(BuildContext context, {required String message, String title = 'Something went wrong'}) {
    _show(context, title: title, message: message, isError: true);
  }

  static void _show(
    BuildContext context, {
    required String title,
    required String message,
    required bool isError,
  }) {
    // Only one toast shows at a time; a new one replaces the old.
    _current?.remove();
    _current = null;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastCard(
        title: title,
        message: message,
        isError: isError,
        onDismiss: () {
          entry.remove();
          if (identical(_current, entry)) _current = null;
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _ToastCard extends StatefulWidget {
  final String title;
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  const _ToastCard({
    required this.title,
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with SafeSetState<_ToastCard>, SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _slide = Tween<Offset>(begin: const Offset(0, -0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    if (mounted) await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isError ? AppColors.badgeRedBg : AppColors.badgeGreenBg;
    final fg = widget.isError ? AppColors.badgeRedText : AppColors.badgeGreenText;
    return Positioned(
      top: 24,
      right: 24,
      child: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 320, maxWidth: 380),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Color(0x260D2617), blurRadius: 28, offset: Offset(0, 10)),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Icon(
                          widget.isError ? Icons.close_rounded : Icons.check_rounded,
                          color: fg,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.title,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(widget.message,
                                style: const TextStyle(
                                    fontSize: 12.5, color: AppColors.textSecondary, height: 1.3)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _dismiss,
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.close, size: 16, color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
