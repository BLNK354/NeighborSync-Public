/// A shared "pick from a long list" dialog with a search box, plus a form
/// field that opens it. Use these instead of a plain dropdown for long lists.
library;

import 'package:flutter/material.dart';

import '../core/dialog_sizing.dart';
import '../theme/app_theme.dart';

/// The search field only appears when there are more options than this.
const int kPickerSearchThreshold = 10;

/// Shows the picker and returns the chosen item, or null if dismissed.
///
/// [labelOf] is what is shown and what the search matches; put anything
/// searchable in it. [subtitleOf] is a second line that is searched too.
Future<T?> showSearchablePicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
  String Function(T)? subtitleOf,
  /// The current choice; shown with a tick and a tinted row.
  T? selected,
  String hintText = 'Search...',
  String emptyText = 'No matches.',
}) {
  return showDialog<T>(
    context: context,
    builder: (context) {
      var query = '';
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? items
              : items.where((o) {
                  if (labelOf(o).toLowerCase().contains(q)) return true;
                  final sub = subtitleOf?.call(o);
                  return sub != null && sub.toLowerCase().contains(q);
                }).toList();

          return AlertDialog(
            insetPadding: dialogInset(context),
            title: Text(title),
            content: SizedBox(
              width: dialogContentWidth(context, 380),
              // Capped so it fits a phone in landscape with the keyboard up.
              height: dialogMaxHeight(context, 380),
              child: Column(
                children: [
                  if (items.length > kPickerSearchThreshold) ...[
                    TextField(
                      autofocus: true,
                      onChanged: (v) => setDialogState(() => query = v),
                      decoration: InputDecoration(
                        hintText: hintText,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Shows how many options match the search.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        q.isEmpty
                            ? '${items.length} to choose from'
                            : '${filtered.length} of ${items.length}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(emptyText,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary)))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final item = filtered[i];
                              final isSelected =
                                  selected != null && item == selected;
                              final sub = subtitleOf?.call(item);
                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: AppColors.highlight,
                                title: Text(labelOf(item),
                                    style: const TextStyle(fontSize: 13)),
                                subtitle: sub == null
                                    ? null
                                    : Text(sub,
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.textSecondary)),
                                trailing: isSelected
                                    ? const Icon(Icons.check,
                                        size: 16,
                                        color: AppColors.badgeGreenText)
                                    : null,
                                onTap: () => Navigator.pop(context, item),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
            ],
          );
        },
      );
    },
  );
}

/// A read-only form field that opens [showSearchablePicker] when tapped.
///
/// Looks like a dropdown field (label, outline, chevron), but tapping opens
/// a list you can search.
class PickerField extends StatelessWidget {
  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  final bool enabled;

  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'Tap to choose',
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final empty = value == null || value!.isEmpty;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          enabled: enabled,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          empty ? placeholder : value!,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: empty ? AppColors.textMuted : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
