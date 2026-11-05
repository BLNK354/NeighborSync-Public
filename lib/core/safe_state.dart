import 'package:flutter/widgets.dart';

/// Makes `setState` do nothing once the widget has left the tree, so a late
/// `await` cannot throw "setState() called after dispose()".
/// Add `with SafeSetState<W>` to every new State class.
mixin SafeSetState<T extends StatefulWidget> on State<T> {
  @override
  void setState(VoidCallback fn) {
    if (!mounted) return;
    super.setState(fn);
  }
}
