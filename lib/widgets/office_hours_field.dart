import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../core/safe_state.dart';

/// Day and time pickers for the office's opening hours.
///
/// The value stays one plain string in [controller], e.g.
/// "Mon–Sat, 8:00 AM – 5:00 PM"; other screens read it as a sentence.
/// Saved text is parsed back into the pickers. If it cannot be read, it is
/// kept untouched until a picker is changed (see [_dirty]).
class OfficeHoursField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;

  const OfficeHoursField({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  @override
  State<OfficeHoursField> createState() => _OfficeHoursFieldState();
}

class _OfficeHoursFieldState extends State<OfficeHoursField> with SafeSetState<OfficeHoursField> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late int _fromDay;
  late int _toDay;
  late TimeOfDay _open;
  late TimeOfDay _close;

  /// True once a picker is touched. Until then the controller keeps the
  /// saved text, so saving other fields does not rewrite the hours.
  bool _dirty = false;

  /// Saved text the pickers could not read. Null once parsed or edited.
  String? _unparsed;

  @override
  void initState() {
    super.initState();
    final parsed = _parse(widget.controller.text);
    _fromDay = parsed?.fromDay ?? 0; // Mon
    _toDay = parsed?.toDay ?? 4; // Fri
    _open = parsed?.open ?? const TimeOfDay(hour: 8, minute: 0);
    _close = parsed?.close ?? const TimeOfDay(hour: 17, minute: 0);
    if (parsed == null && widget.controller.text.trim().isNotEmpty) {
      _unparsed = widget.controller.text.trim();
    }
  }

  /// Writes the picked values into the controller as text.
  void _emit() {
    setState(() {
      _dirty = true;
      _unparsed = null;
      widget.controller.text = _compose();
    });
  }

  String _compose() {
    final days = _fromDay == _toDay
        ? _days[_fromDay]
        : '${_days[_fromDay]}–${_days[_toDay]}';
    return '$days, ${_fmt(_open)} – ${_fmt(_close)}';
  }

  /// Always 12-hour. Do not use the device's format: the text is saved, so
  /// it would differ from one laptop to another.
  static String _fmt(TimeOfDay t) {
    final suffix = t.hour < 12 ? 'AM' : 'PM';
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m $suffix';
  }

  Future<void> _pickTime({required bool opening}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: opening ? _open : _close,
      helpText: opening ? 'Office opens at' : 'Office closes at',
    );
    if (picked == null) return;
    if (opening) {
      _open = picked;
    } else {
      _close = picked;
    }
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    // Closing at or before opening is treated as a mistake.
    final backwards = _close.hour * 60 + _close.minute <=
        _open.hour * 60 + _open.minute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _dayDropdown(isFrom: true)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('to', style: TextStyle(fontSize: 12)),
            ),
            Expanded(child: _dayDropdown(isFrom: false)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _timeButton(_open, opening: true)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('–', style: TextStyle(fontSize: 12)),
            ),
            Expanded(child: _timeButton(_close, opening: false)),
          ],
        ),
        const SizedBox(height: 8),
        if (backwards)
          _note(
            Icons.error_outline,
            'The closing time is not after the opening time.',
            const Color(0xFFA82F2F),
          )
        else if (_unparsed != null)
          // Saved text the pickers could not read; kept until replaced.
          _note(
            Icons.info_outline,
            'Currently showing "$_unparsed". Change a control above to '
            'replace it with "${_compose()}".',
            AppColors.textMuted,
          )
        else
          _note(
            Icons.schedule,
            _dirty ? 'Will be saved as "${_compose()}"' : _compose(),
            AppColors.textMuted,
          ),
      ],
    );
  }

  Widget _note(IconData icon, String text, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 11, color: color, height: 1.4)),
          ),
        ],
      );

  Widget _dayDropdown({required bool isFrom}) {
    final value = isFrom ? _fromDay : _toDay;
    return DropdownButtonFormField<int>(
      // initialValue is read once; the key rebuilds the field when the
      // value changes from code.
      key: ValueKey('day-${isFrom ? 'from' : 'to'}-$value'),
      initialValue: value,
      isDense: true,
      decoration: const InputDecoration(isDense: true),
      items: [
        for (var i = 0; i < _days.length; i++)
          DropdownMenuItem(
              value: i,
              child: Text(_days[i], style: const TextStyle(fontSize: 13))),
      ],
      onChanged: !widget.enabled
          ? null
          : (v) {
              if (v == null || v == value) return;
              if (isFrom) {
                _fromDay = v;
                // Keeps the range from running backwards.
                if (_toDay < _fromDay) _toDay = _fromDay;
              } else {
                _toDay = v;
                if (_fromDay > _toDay) _fromDay = _toDay;
              }
              _emit();
            },
    );
  }

  Widget _timeButton(TimeOfDay value, {required bool opening}) {
    return OutlinedButton.icon(
      onPressed: widget.enabled ? () => _pickTime(opening: opening) : null,
      icon: const Icon(Icons.access_time, size: 15),
      label: Text(_fmt(value), style: const TextStyle(fontSize: 12.5)),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  // ---------------- parsing ----------------

  /// Reads saved text like "Mon-Sat, 8:00 AM - 5:00 PM". Null if it
  /// does not fit.
  static _ParsedHours? _parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    // Days: "Mon-Sat", "Mon – Sat", "Monday to Saturday", or a single day.
    int? dayIndex(String token) {
      final t = token.toLowerCase();
      for (var i = 0; i < _days.length; i++) {
        if (t.startsWith(_days[i].toLowerCase())) return i;
      }
      return null;
    }

    final dayMatch = RegExp(
            r'([A-Za-z]{3,9})\s*(?:[-–—]|to)\s*([A-Za-z]{3,9})',
            caseSensitive: false)
        .firstMatch(s);
    int? from;
    int? to;
    if (dayMatch != null) {
      from = dayIndex(dayMatch.group(1)!);
      to = dayIndex(dayMatch.group(2)!);
    } else {
      final single =
          RegExp(r'^([A-Za-z]{3,9})', caseSensitive: false).firstMatch(s);
      if (single != null) {
        from = dayIndex(single.group(1)!);
        to = from;
      }
    }
    if (from == null || to == null) return null;

    // Times: "9am", "9:30 AM", "17:00". Needs two of them.
    final times = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?',
            caseSensitive: false)
        .allMatches(s)
        .where((m) => m.group(3) != null || m.group(2) != null)
        .toList();
    if (times.length < 2) return null;

    TimeOfDay? toTime(RegExpMatch m) {
      var h = int.tryParse(m.group(1) ?? '');
      final min = int.tryParse(m.group(2) ?? '0') ?? 0;
      if (h == null || h > 23 || min > 59) return null;
      final period = m.group(3)?.toLowerCase();
      if (period == 'pm' && h < 12) h += 12;
      if (period == 'am' && h == 12) h = 0;
      return TimeOfDay(hour: h, minute: min);
    }

    final open = toTime(times[0]);
    final close = toTime(times[1]);
    if (open == null || close == null) return null;

    return _ParsedHours(fromDay: from, toDay: to, open: open, close: close);
  }
}

/// Days and times read from saved text.
class _ParsedHours {
  final int fromDay;
  final int toDay;
  final TimeOfDay open;
  final TimeOfDay close;
  const _ParsedHours({
    required this.fromDay,
    required this.toDay,
    required this.open,
    required this.close,
  });
}
