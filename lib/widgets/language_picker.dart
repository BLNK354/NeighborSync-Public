import 'package:flutter/material.dart';

import '../core/app_locale.dart';

/// Language dropdown used on the Settings screens. A change applies right
/// away and is saved only for the signed-in person.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, this.width = 260});

  final double width;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) => SizedBox(
        width: width,
        child: DropdownButtonFormField<String>(
          // Keyed on the value: the field reads initialValue only once.
          key: ValueKey(AppLocale.instance.language),
          initialValue: AppLocale.instance.language,
          decoration: InputDecoration(labelText: tr('Language')),
          items: [
            for (final l in AppLocale.options)
              DropdownMenuItem(value: l, child: Text(l)),
          ],
          onChanged: (v) {
            if (v != null) AppLocale.instance.setLanguage(v);
          },
        ),
      ),
    );
  }
}
