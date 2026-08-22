import 'package:flutter/material.dart';

import '../../../shared/ui_kit.dart';

/// The window a ground is available each day, as two tappable hours.
///
/// ## Why this is a shared widget
///
/// Both guided creation flows — season and tournament — drew this as a plain
/// `Text` inside a bordered box: it looked exactly like the editable controls
/// beside it and could not be changed. The two numbers behind it were `final`
/// fields with no setter anywhere in either file, so every season and every
/// tournament in the product was scheduled 09:00–19:00 regardless of what the
/// organizer actually had the ground for.
///
/// Fixing it in one flow and leaving the other is how a defect gets reported
/// twice, so the control lives here and both flows use it.
///
/// Whole hours, because `ScheduleConfig` stores `dayStartHour` and
/// `dayEndHour` as integers. The picker opens in keyboard mode for the same
/// reason: a dial that accepts 09:37 for a field that keeps only the 9 is a
/// control that lies about what it saved.
class DailyHoursField extends StatelessWidget {
  const DailyHoursField({
    super.key,
    required this.startHour,
    required this.endHour,
    required this.onChanged,
  });

  final int startHour;
  final int endHour;

  /// Reported as a pair so the widget can keep the two in order — an end
  /// before a start is not a short day, it is a day with no slots in it.
  final void Function(int start, int end) onChanged;

  static String _label(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  Future<void> _pick(BuildContext context, {required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: isStart ? startHour : endHour, minute: 0),
      helpText: isStart ? 'Play may start from' : 'Play must finish by',
      initialEntryMode: TimePickerEntryMode.inputOnly,
    );
    if (picked == null) return;

    var start = isStart ? picked.hour : startHour;
    var end = isStart ? endHour : picked.hour;
    if (end <= start) {
      // Nudged rather than refused. Someone moving an evening league's start
      // to 18:00 against a default 19:00 close means to run into the night,
      // and rejecting the entry helps them less than giving them a day that
      // is at least one slot long.
      if (isStart) {
        end = start + 1 > 23 ? 23 : start + 1;
      } else {
        start = end - 1 < 0 ? 0 : end - 1;
      }
    }
    onChanged(start, end);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _HourChip(
            label: _label(startHour),
            onTap: () => _pick(context, isStart: true),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('–', style: TextStyle(color: Ps.muted)),
        ),
        Expanded(
          child: _HourChip(
            label: _label(endHour),
            onTap: () => _pick(context, isStart: false),
          ),
        ),
      ],
    );
  }
}

class _HourChip extends StatelessWidget {
  const _HourChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Ps.surface,
          borderRadius: BorderRadius.circular(Ps.radiusSm),
          border: Border.all(color: Ps.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Ps.ink,
          ),
        ),
      ),
    );
  }
}
