import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../design.dart';

final firstLogDay = DateTime(2000);

Future<DateTime?> showLogDayPicker({
  required BuildContext context,
  required DateTime initialDay,
}) => showModalBottomSheet<DateTime>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _LogDayPicker(initialDay: initialDay),
);

class _LogDayPicker extends StatefulWidget {
  const _LogDayPicker({required this.initialDay});
  final DateTime initialDay;
  @override
  State<_LogDayPicker> createState() => _LogDayPickerState();
}

class _LogDayPickerState extends State<_LogDayPicker> {
  late DateTime day = DateUtils.dateOnly(widget.initialDay);
  final today = DateUtils.dateOnly(DateTime.now());
  final firstDay = firstLogDay;
  late DateTime month = DateTime(day.year, day.month);

  void choose(DateTime value, {bool moveCalendar = false}) => setState(() {
    day = DateUtils.dateOnly(value);
    if (moveCalendar) month = DateTime(day.year, day.month);
  });

  Future<void> pickYear() async {
    final year = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose year'),
        content: SizedBox(
          width: 320,
          height: 360,
          child: YearPicker(
            firstDate: firstDay,
            lastDate: today,
            selectedDate: month,
            onChanged: (date) => Navigator.pop(context, date.year),
          ),
        ),
      ),
    );
    if (year != null && mounted) {
      setState(() {
        month = DateTime(
          year,
          year == today.year && month.month > today.month
              ? today.month
              : month.month,
        );
      });
    }
  }

  Widget calendar(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final firstWeekday = localizations.firstDayOfWeekIndex;
    final offset = (month.weekday % 7 - firstWeekday + 7) % 7;
    final count = DateUtils.getDaysInMonth(month.year, month.month);
    final rows = (offset + count + 6) ~/ 7;
    final cellHeight = (MediaQuery.textScalerOf(context).scale(14) * 1.4 + 16)
        .clamp(48.0, 80.0);
    final thisMonth = DateTime(today.year, today.month);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: pickYear,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        DateFormat.yMMMM().format(month),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more, size: 18),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Previous month',
              onPressed: month == firstDay
                  ? null
                  : () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: month == thisMonth
                  ? null
                  : () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      localizations.narrowWeekdays[(i + firstWeekday) % 7],
                      style: TextStyle(
                        fontSize: 12,
                        color: logPalette(context).secondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: SizedBox(
                    height: cellHeight,
                    child: dayCell(row * 7 + column - offset + 1, count),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget dayCell(int number, int count) {
    if (number < 1 || number > count) return const SizedBox();
    final date = DateTime(month.year, month.month, number);
    final selected = date == day;
    final isToday = date == today;
    final enabled = !date.isAfter(today);
    return Semantics(
      label:
          '${MaterialLocalizations.of(context).formatFullDate(date)}${isToday ? ', Today' : ''}',
      selected: selected,
      button: true,
      enabled: enabled,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: enabled ? () => choose(date) : null,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            foregroundColor: selected
                ? Theme.of(context).colorScheme.onPrimary
                : logPalette(context).ink,
            disabledForegroundColor: logPalette(
              context,
            ).secondary.withValues(alpha: .45),
            backgroundColor: selected ? logPalette(context).actionInk : null,
            shape: CircleBorder(
              side: isToday && !selected
                  ? BorderSide(color: logPalette(context).actionInk)
                  : BorderSide.none,
            ),
          ),
          child: Text(
            '$number',
            maxLines: 1,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .9,
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choose day',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () => choose(today, moveCalendar: true),
                  child: const Text('Today'),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: logPalette(context).background,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous day',
                          onPressed: day == firstDay
                              ? null
                              : () => choose(
                                  DateTime(day.year, day.month, day.day - 1),
                                  moveCalendar: true,
                                ),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Column(
                              children: [
                                Text(
                                  DateFormat.EEEE().format(day),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: logPalette(context).secondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat.yMMMd().format(day),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: logPalette(context).ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next day',
                          onPressed: day == today
                              ? null
                              : () => choose(
                                  DateTime(day.year, day.month, day.day + 1),
                                  moveCalendar: true,
                                ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  calendar(context),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, day),
                    child: const Text('Show day'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
