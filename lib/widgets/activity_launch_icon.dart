import 'package:flutter/material.dart';
import '../design.dart';
import 'activity_glyph.dart';
import 'elapsed_activity_glyph.dart';

/// Quick Log uses the same icon at the same size in both display modes.
class ActivityLaunchIcon extends StatelessWidget {
  static const double iconSize = 26;
  const ActivityLaunchIcon({super.key, required this.method});
  final String method;

  @override
  Widget build(BuildContext context) =>
      CareGlyph(method: method, fallback: activityIcon(method), size: iconSize);
}

class QuickLogElapsedTime extends StatelessWidget {
  const QuickLogElapsedTime({
    super.key,
    required this.method,
    required this.elapsed,
  });
  final String method;
  final Duration? elapsed;

  static String textFor(Duration? elapsed) {
    final value = elapsedIconLabel(elapsed);
    return switch (value.primary) {
      '—' => '—',
      'now' => 'Just now',
      '>1d' => '>1 day ago',
      '1d' => '1 day ago',
      _ =>
        '${value.primary}${value.secondary.isEmpty ? '' : ' ${value.secondary}'} ago',
    };
  }

  static TextStyle textStyle(BuildContext context, String method) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
        fontSize: 11,
        height: 1.15,
        letterSpacing: 0,
        color: activityAccent(method, context: context),
      );

  @override
  Widget build(BuildContext context) => Semantics(
    label: elapsedIconLabel(elapsed).spoken,
    child: ExcludeSemantics(
      child: Text(
        textFor(elapsed),
        key: ValueKey('quick-log-elapsed-$method'),
        textAlign: TextAlign.center,
        style: textStyle(context, method),
      ),
    ),
  );
}
