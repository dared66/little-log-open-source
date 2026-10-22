import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../design.dart';
import 'log_day_picker.dart';

class EmptyLogDay extends StatelessWidget {
  const EmptyLogDay({
    super.key,
    required this.day,
    required this.onChanged,
    required this.canNavigate,
  });

  final DateTime day;
  final ValueChanged<DateTime> onChanged;
  final bool canNavigate;

  @override
  Widget build(BuildContext context) {
    final previous = DateTime(day.year, day.month, day.day - 1);
    final next = DateTime(day.year, day.month, day.day + 1);
    final today = DateUtils.dateOnly(DateTime.now());

    Widget arrow(bool forward) {
      final destination = forward ? next : previous;
      final available = forward
          ? !destination.isAfter(today)
          : !destination.isBefore(firstLogDay);
      if (!available) return const SizedBox(width: 44, height: 44);
      return IconButton(
        key: ValueKey(forward ? 'empty-day-next' : 'empty-day-previous'),
        tooltip:
            '${forward ? 'Next day' : 'Previous day'}, ${DateFormat.yMMMMd().format(destination)}',
        onPressed: () => onChanged(destination),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        padding: EdgeInsets.zero,
        color: logPalette(context).actionInk,
        icon: Icon(forward ? Icons.chevron_right : Icons.chevron_left),
      );
    }

    final message = Text(
      canNavigate ? 'No entries' : 'No entries on this day',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome_outlined, color: logPalette(context).secondary),
        const SizedBox(height: LogSpacing.content),
        message,
      ],
    );
    return Container(
      padding: const EdgeInsets.all(LogSpacing.content),
      decoration: BoxDecoration(
        color: logPalette(context).surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: canNavigate
          ? Row(
              children: [
                arrow(false),
                Expanded(child: content),
                arrow(true),
              ],
            )
          : content,
    );
  }
}
