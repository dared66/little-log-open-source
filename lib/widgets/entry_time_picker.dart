import 'package:flutter/material.dart';

/// A date-aware time picker shared by manual activity entry fields.
///
/// Ordinary time edits retain the supplied date. Now selects the current local
/// date as well, but neither selection reaches the form until OK is pressed.
Future<DateTime?> showEntryTimePicker({
  required BuildContext context,
  required DateTime initialValue,
  bool allowNow = true,
  DateTime Function()? now,
}) async {
  final local = initialValue.toLocal();
  var initialTime = TimeOfDay.fromDateTime(local);
  DateTime? selectedNow;
  var generation = 0;
  var mode = TimePickerEntryMode.dial;
  final chosen = await showDialog<TimeOfDay>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void useNow() {
          final current = (now ?? DateTime.now)().toLocal();
          setState(() {
            selectedNow = current;
            initialTime = TimeOfDay.fromDateTime(current);
            // TimePickerDialog owns its selection. Recreate it with the newly
            // sampled time while keeping the user's dial/keyboard entry mode.
            generation++;
          });
        }

        Icon entryModeAction(IconData icon) =>
            allowNow ? _EntryModeIcon(icon, onNow: useNow) : Icon(icon);

        return TimePickerDialog(
          key: ValueKey(generation),
          initialTime: initialTime,
          initialEntryMode: mode,
          onEntryModeChanged: (value) => mode = value,
          // The public entry-mode slot sits at the native footer's start.
          // Keeping the shortcut here leaves Cancel, OK and the native layout,
          // input validation and clock dial under Flutter's control.
          switchToInputEntryModeIcon: entryModeAction(Icons.keyboard_outlined),
          switchToTimerEntryModeIcon: entryModeAction(Icons.access_time),
        );
      },
    ),
  );
  if (chosen == null) return null;
  final date = selectedNow ?? local;
  // Preserve the exact sampled instant for Now, including seconds, so an end
  // in the same minute as its start cannot accidentally move before the start.
  if (selectedNow != null && chosen == TimeOfDay.fromDateTime(date)) {
    return date;
  }
  return DateTime(date.year, date.month, date.day, chosen.hour, chosen.minute);
}

// Flutter exposes the footer entry-mode slot as Icon rather than Widget.
// Extend that slot so the native dial, keyboard, Cancel and OK keep their
// behavior. The nested text button handles its own tap, independently of the
// surrounding entry-mode button.
class _EntryModeIcon extends Icon {
  const _EntryModeIcon(this.modeIcon, {required this.onNow}) : super(null);

  final IconData modeIcon;
  final VoidCallback onNow;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(modeIcon),
      NowTimeAction(onPressed: onNow),
    ],
  );
}

/// A quiet text action with a full touch target, reusable outside this picker.
class NowTimeAction extends StatelessWidget {
  const NowTimeAction({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    key: const ValueKey('entry-time-now'),
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    onPressed: onPressed,
    child: const Text('Now'),
  );
}
