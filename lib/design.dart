import 'widgets/confirm_removal.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'widgets/activity_glyph.dart';
import 'widgets/entry_time_picker.dart';
import 'volume.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'activity_details.dart';
import 'models.dart';
import 'record_validation.dart';
import 'diaper_details.dart';

/// Shared vertical rhythm for every page. Field labels sit 8 px above their
/// controls, section headings 12 px above content, and sections 24 px apart.
abstract final class LogSpacing {
  static const double page = 20;
  static const double detail = 4;
  static const double label = 8;
  static const double content = 12;
  static const double field = 16;
  static const double section = 24;
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: LogSpacing.label),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.trailing,
    this.compact = false,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      bottom: compact ? LogSpacing.detail : LogSpacing.content,
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 44 : 48),
      child: Row(
        children: [
          Expanded(
            flex: compact ? 3 : 1,
            child: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          ?trailing,
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.only(left: LogSpacing.content),
                alignment: Alignment.centerRight,
                textStyle: compact
                    ? Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      )
                    : null,
              ),
              child: Text(action!, textAlign: TextAlign.end),
            ),
        ],
      ),
    ),
  );
}

const logActionInk = Color(0xFF214B43);
const logActionTint = Color(0xFFE3EFE8);

const logInk = Color(0xFF293536);
const logSecondary = Color(0xFF626E6C);
const logBackground = Color(0xFFFAF8F4);

/// Device appearance colors. Activity identity remains in activityColors below.
class LogPalette {
  const LogPalette({this.dark = false, this.background = logBackground});
  final bool dark;
  final Color background;
  Color get ink => dark ? const Color(0xFFE7EFEB) : logInk;
  Color get secondary => dark ? const Color(0xFFB3C0BA) : logSecondary;
  Color get actionInk => dark ? const Color(0xFFA4D5C2) : logActionInk;
  Color get actionTint => dark ? const Color(0xFF253F35) : logActionTint;
  Color get surface => dark ? const Color(0xFF222B28) : Colors.white;
  Color get input => dark ? const Color(0xFF29332E) : const Color(0xFFF7F5F1);
  Color get warningTint =>
      dark ? const Color(0xFF483B24) : const Color(0xFFFFF0D6);
}

LogPalette logPalette(BuildContext context) => LogPalette(
  dark: Theme.of(context).brightness == Brightness.dark,
  background: Theme.of(context).scaffoldBackgroundColor,
);

/// Onboarding and invitation forms share the same control geometry and contrast.
ThemeData setupTheme(BuildContext context) {
  final theme = Theme.of(context);
  final palette = logPalette(context);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: palette.secondary),
  );
  return theme.copyWith(
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      fillColor: palette.surface,
      contentPadding: const EdgeInsets.all(16),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: palette.actionInk, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(
        shape: WidgetStatePropertyAll(shape),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(
        shape: WidgetStatePropertyAll(shape),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        side: WidgetStatePropertyAll(BorderSide(color: palette.secondary)),
      ),
    ),
    cardTheme: theme.cardTheme.copyWith(shape: shape),
  );
}

/// Standalone pages share the log's 680-point frame, including its gutters.
class LogPageFrame extends StatelessWidget {
  const LogPageFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: child,
      ),
    ),
  );
}

/// Keep long page names readable with accessibility text, and keep the back
/// control in the same centered frame as the page on wider displays.
AppBar logPageAppBar(
  BuildContext context,
  String title, {
  VoidCallback? onBack,
  bool? showBackButton,
}) {
  final showBack = showBackButton ?? Navigator.of(context).canPop();
  final media = MediaQuery.of(context);
  final style =
      (Theme.of(context).appBarTheme.titleTextStyle ??
              Theme.of(context).textTheme.titleLarge!)
          .copyWith(color: Theme.of(context).appBarTheme.foregroundColor);
  final width = (media.size.width - media.padding.horizontal)
      .clamp(0.0, 680.0)
      .toDouble();
  final painter =
      TextPainter(
        text: TextSpan(text: title, style: style),
        textScaler: media.textScaler,
        textDirection: Directionality.of(context),
        maxLines: 3,
      )..layout(
        maxWidth: (width - 40 - (showBack ? 56 : 0)).clamp(
          1.0,
          double.infinity,
        ),
      );
  final height = (painter.height + 16)
      .clamp(kToolbarHeight, double.infinity)
      .toDouble();
  painter.dispose();
  return AppBar(
    automaticallyImplyLeading: false,
    centerTitle: false,
    titleSpacing: 0,
    toolbarHeight: height,
    title: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              if (showBack) ...[
                BackButton(onPressed: onBack),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: style,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Color darkBabyBackground(String choice) => switch (choice) {
  'sky' => const Color(0xFF171F27),
  'lilac' => const Color(0xFF211C28),
  'peach' => const Color(0xFF271E1A),
  'sage' => const Color(0xFF18241D),
  _ => const Color(0xFF191F1C),
};

ThemeData littleLogTheme({
  Brightness brightness = Brightness.light,
  Color? background,
}) {
  background ??= brightness == Brightness.dark
      ? darkBabyBackground('linen')
      : logBackground;
  final p = LogPalette(
    dark: brightness == Brightness.dark,
    background: background,
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: logActionInk,
    brightness: brightness,
    primary: p.actionInk,
    onPrimary: p.dark ? const Color(0xFF15372A) : Colors.white,
    primaryContainer: p.actionTint,
    onPrimaryContainer: p.actionInk,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.secondary,
    outlineVariant: p.dark ? const Color(0xFF4C5B52) : const Color(0xFFD7E0D9),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: p.actionInk,
    ),
    textTheme: ThemeData(
      brightness: brightness,
    ).textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.actionTint,
      height: 60,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        alignment: Alignment.center,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.input,
      errorMaxLines: 3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.actionInk, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}

// Baby backgrounds are a device preference, separate from synced activity colors.
const babyBackgrounds = <String, ({String label, Color color})>{
  'linen': (label: 'Linen', color: logBackground),
  'sky': (label: 'Sky', color: Color(0xFFF3F8FC)),
  'lilac': (label: 'Lilac', color: Color(0xFFF8F5FC)),
  'peach': (label: 'Peach', color: Color(0xFFFCF6F2)),
  'sage': (label: 'Sage', color: Color(0xFFF3F9F5)),
};

IconData activityIcon(String method) => switch (method) {
  'bottle' => Icons.local_drink_outlined,
  'nursing' => Icons.baby_changing_station,
  'diaper' => Icons.dry_cleaning_outlined,
  'sleep' => Icons.bedtime_outlined,
  'pumping' => Icons.water_drop_outlined,
  'solids' => Icons.restaurant_outlined,
  'growth' => Icons.straighten_outlined,
  'health' => Icons.medical_services_outlined,
  'routine' => Icons.checklist_rounded,
  _ => Icons.auto_awesome_outlined,
};
// Category color identifies an activity; it never means success, error, or
// whether a control is selected. Global actions retain the app's evergreen.
// Dark pairs follow the light-mode category hues with soft pastel accents
// and smoky tints, preserving activity identity and the app's gentle appearance.
const activityColors =
    <String, ({Color accent, Color tint, Color darkAccent, Color darkTint})>{
      'bottle': (
        accent: Color(0xFF365F8C),
        tint: Color(0xFFE8F0FA),
        darkAccent: Color(0xFFA9C8E7),
        darkTint: Color(0xFF30465B),
      ),
      'nursing': (
        accent: Color(0xFF974F6C),
        tint: Color(0xFFFAEAF0),
        darkAccent: Color(0xFFE1ADC2),
        darkTint: Color(0xFF503A43),
      ),
      'diaper': (
        accent: Color(0xFF2E7068),
        tint: Color(0xFFE5F3EF),
        darkAccent: Color(0xFF9CCFC9),
        darkTint: Color(0xFF2D4B47),
      ),
      'sleep': (
        accent: Color(0xFF5C568D),
        tint: Color(0xFFEEECF9),
        darkAccent: Color(0xFFBAB5E3),
        darkTint: Color(0xFF3C3952),
      ),
      'pumping': (
        accent: Color(0xFF855787),
        tint: Color(0xFFF4EAF6),
        darkAccent: Color(0xFFDCB3DE),
        darkTint: Color(0xFF4D3B4E),
      ),
      'solids': (
        accent: Color(0xFF955737),
        tint: Color(0xFFFBEDDF),
        darkAccent: Color(0xFFE0B199),
        darkTint: Color(0xFF503F36),
      ),
      'growth': (
        accent: Color(0xFF637238),
        tint: Color(0xFFF0F2DD),
        darkAccent: Color(0xFFC2CF96),
        darkTint: Color(0xFF434934),
      ),
      'health': (
        accent: Color(0xFF266B82),
        tint: Color(0xFFE4F3F8),
        darkAccent: Color(0xFFA0CEDC),
        darkTint: Color(0xFF304A52),
      ),
      'routine': (
        accent: Color(0xFF82631D),
        tint: Color(0xFFFAF1D8),
        darkAccent: Color(0xFFDCC78F),
        darkTint: Color(0xFF4C4533),
      ),
      'milestone': (
        accent: Color(0xFF5A6478),
        tint: Color(0xFFEDF0F5),
        darkAccent: Color(0xFFB9C4DC),
        darkTint: Color(0xFF3B4352),
      ),
    };
Color activityTint(String method, {BuildContext? context}) {
  final tint = activityColors[method]?.tint ?? const Color(0xFFF1F2F0);
  if (context == null || Theme.of(context).brightness != Brightness.dark) {
    return tint;
  }
  return activityColors[method]?.darkTint ?? const Color(0xFF303630);
}

Color activityAccent(String method, {BuildContext? context}) {
  final accent = activityColors[method]?.accent ?? logSecondary;
  if (context == null || Theme.of(context).brightness != Brightness.dark) {
    return accent;
  }
  return activityColors[method]?.darkAccent ?? logPalette(context).secondary;
}

class ActivityBadge extends StatelessWidget {
  const ActivityBadge({super.key, required this.method});
  final String method;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: activityTint(method, context: context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: CareGlyph(
        method: method,
        fallback: activityIcon(method),
        color: activityAccent(method, context: context),
        size: 22,
      ),
    ),
  );
}

String sessionDuration(Duration d) {
  final seconds = d.inSeconds.clamp(0, 99999999);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String compactNumber(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
String recordLabel(Feeding record, {required VolumeUnit unit}) {
  if (record.isExtended) return activityLabel(record, unit: unit);
  if (record.isDiaper) {
    return 'Diaper · ${switch (record.diaperKind) {
      'both' => 'Wet & dirty',
      'dirty' => 'Dirty',
      'dry' => 'Dry',
      _ => 'Wet',
    }}';
  }
  if (record.method == 'bottle') {
    return [
      'Bottle',
      volumeLabel(record.amountMl ?? 0, unit: unit),
      bottleContentsLabel(record),
    ].where((s) => s.isNotEmpty).join(' · ');
  }
  if (record.leftSeconds != null) {
    String duration(int s) => '${s ~/ 60}m ${s % 60}s';
    return 'Nursing · L ${duration(record.leftSeconds!)} · R ${duration(record.rightSeconds ?? 0)}';
  }
  return 'Nursing · ${record.minutes} min';
}

int newestRecordFirst(Feeding a, Feeding b) {
  final time = b.at.compareTo(a.at);
  return time != 0 ? time : b.id.compareTo(a.id);
}

Set<String> latestActivityIds(Iterable<Feeding> records) {
  final latest = <String, Feeding>{};
  for (final record in records) {
    if (record.deleted || record.method == 'profile') continue;
    final previous = latest[record.method];
    if (previous == null || newestRecordFirst(record, previous) < 0) {
      latest[record.method] = record;
    }
  }
  return latest.values.map((record) => record.id).toSet();
}

String elapsedActivityTime(DateTime at, DateTime now) {
  final elapsed = now.difference(at);
  if (elapsed.isNegative) return 'In the future';
  if (elapsed.inMinutes == 0) return 'Just now';
  if (elapsed.inHours == 0) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays == 0) {
    final minutes = elapsed.inMinutes % 60;
    return '${elapsed.inHours}h${minutes == 0 ? '' : ' ${minutes}m'} ago';
  }
  final hours = elapsed.inHours % 24;
  return '${elapsed.inDays}d${hours == 0 ? '' : ' ${hours}h'} ago';
}

const _recordTitleStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
TextStyle _recordSecondaryStyle(BuildContext context) =>
    TextStyle(color: logPalette(context).secondary, fontSize: 12);

String _recordTitle(RecordRow row) {
  final record = row.record;
  if (record.method == 'growth' && record.details['measurement'] == 'Weight') {
    final value = (record.details['value'] as num).toDouble();
    final kg = record.details['unit'] == 'lb' ? value / 2.2046226218 : value;
    return 'Weight · ${compactNumber(row.weightUnit == 'lb' ? kg * 2.2046226218 : kg)} ${row.weightUnit}';
  }
  final label = recordLabel(record, unit: row.volumeUnit);
  return record.method == 'nursing'
      ? label.replaceAllMapped(
          RegExp(r'(\d+m) (\d+s)'),
          (m) => '${m[1]}${m[2]}',
        )
      : label;
}

String _recordTimestamp(RecordRow row) =>
    (row.record.method == 'nursing' || row.record.endedAt != null
        ? 'Started '
        : '') +
    DateFormat('MMM d · h:mm a').format(row.record.at.toLocal()) +
    (row.showElapsed
        ? ' · ${elapsedActivityTime(row.record.at, DateTime.now())}'
        : '') +
    (row.record.source['system'] == 'Nara Baby' ? ' · Nara Baby' : '');

/// Shared record list: compact rows grow with their own text at large font sizes.
class RecordList extends StatelessWidget {
  const RecordList({super.key, required this.children});
  final List<RecordRow> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Column(children: children),
  );
}

class RecordRow extends StatefulWidget {
  const RecordRow({
    super.key,
    required this.record,
    required this.volumeUnit,
    this.local = true,
    this.weightUnit = 'kg',
    this.onDelete,
    this.onEdit,
    this.showElapsed = false,
    this.swipeDemoEnabled = false,
    this.onSwipeAction,
    this.onSwipeDemoStart,
    this.onSwipeDemoEnd,
  });
  final Feeding record;
  final VolumeUnit volumeUnit;
  final bool local;
  final String weightUnit;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onEdit;
  final bool showElapsed;
  final bool swipeDemoEnabled;
  final Future<void> Function()? onSwipeAction;
  final bool Function()? onSwipeDemoStart;
  final Future<void> Function(bool completed)? onSwipeDemoEnd;
  @override
  State<RecordRow> createState() => _RecordRowState();
}

class _RecordRowState extends State<RecordRow> {
  bool expanded = false;
  Future<void> remove() async {
    final confirmed = await confirmRemoval(
      context,
      title: 'Delete this entry?',
      message: widget.local
          ? 'Deletes this entry from this device.'
          : 'Deletes this entry from this device and the shared log when it syncs.',
      confirmLabel: 'Delete',
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.onDelete?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete the entry. Try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final diaperDescription = [
      ...diaperValues(
        record.details,
        'poopColor',
        'poopColors',
      ).map((v) => poopColors[v]),
      ...diaperValues(
        record.details,
        'poopConsistency',
        'poopConsistencies',
      ).map((v) => poopConsistencies[v]),
    ].whereType<String>().join(' · ');
    final diaperObservations = [
      for (final flag in [('blowout', 'Blowout'), ('rash', 'Rash')])
        if (record.details[flag.$1] is bool)
          (flag.$2, record.details[flag.$1] == true),
    ];
    final detailStyle = _recordSecondaryStyle(
      context,
    ).copyWith(fontWeight: FontWeight.w400);
    final label = _recordTitle(widget);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: LogSpacing.label),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => expanded = !expanded),
            child: Padding(
              padding: EdgeInsets.only(
                top: LogSpacing.label,
                bottom: expanded ? 0 : LogSpacing.label,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ActivityBadge(method: record.method),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          child: Text(
                            label,
                            maxLines: expanded ? null : 2,
                            overflow: expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: _recordTitleStyle,
                          ),
                        ),
                        const SizedBox(height: LogSpacing.detail),
                        SizedBox(
                          child: Text(
                            _recordTimestamp(widget),
                            style: _recordSecondaryStyle(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: LogSpacing.label),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    semanticLabel: expanded ? 'Collapse entry' : 'Expand entry',
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              // Badge (22 + 2 * 11) plus its 12 px gap.
              padding: const EdgeInsets.fromLTRB(
                56,
                LogSpacing.label,
                20 + LogSpacing.label,
                LogSpacing.label,
              ),
              child: DefaultTextStyle.merge(
                style: detailStyle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (record.endedAt != null)
                      Text(
                        'Ended ${DateFormat.jm().format(record.endedAt!.toLocal())}',
                      ),
                    if (record.isDiaper) ...[
                      if (diaperDescription.isNotEmpty)
                        Text(diaperDescription, style: detailStyle),
                      if (diaperObservations.isNotEmpty)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final scaler = MediaQuery.textScalerOf(context);
                            final painter = TextPainter(
                              text: TextSpan(
                                text: diaperObservations
                                    .map((f) => f.$1)
                                    .join(' · '),
                                style: DefaultTextStyle.of(context).style,
                              ),
                              textDirection: Directionality.of(context),
                              textScaler: scaler,
                            )..layout();
                            final inline =
                                painter.width +
                                    diaperObservations.length *
                                        scaler.scale(15) <=
                                constraints.maxWidth;
                            painter.dispose();
                            return Wrap(
                              spacing: inline ? 0 : LogSpacing.content,
                              children: [
                                for (
                                  var i = 0;
                                  i < diaperObservations.length;
                                  i++
                                )
                                  Semantics(
                                    label:
                                        '${diaperObservations[i].$1}: ${diaperObservations[i].$2 ? 'Yes' : 'No'}',
                                    excludeSemantics: true,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (inline && i > 0)
                                          Text(' · ', style: detailStyle),
                                        Text(
                                          diaperObservations[i].$1,
                                          style: detailStyle,
                                        ),
                                        const SizedBox(width: 3),
                                        Icon(
                                          diaperObservations[i].$2
                                              ? Icons.check
                                              : Icons.close,
                                          size: scaler.scale(12),
                                          color: detailStyle.color,
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                    ],
                    if (record.method == 'nursing' && record.endedAt == null)
                      const Text('End time not recorded'),
                    if (record.method == 'bottle' &&
                        record.details.isNotEmpty) ...[
                      Text(
                        'Breast milk: ${volumeLabel((record.details['breastMilkMl'] as num).toDouble(), unit: widget.volumeUnit)}',
                      ),
                      Text(
                        'Formula: ${volumeLabel((record.details['formulaMl'] as num).toDouble(), unit: widget.volumeUnit)}',
                      ),
                      if (record.details['formulaName'] != null)
                        Text(record.details['formulaName'] as String),
                    ],
                    if (record.source.isNotEmpty &&
                        record.source['system'] != 'Little Log')
                      Text('Imported from ${record.source['system']}'),
                    if (record.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: LogSpacing.detail),
                        child: Text(record.note),
                      ),
                    if (record.author.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: LogSpacing.label),
                        child: Text('Logged by ${record.author}'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (widget.onDelete == null) return content;
    final dismissible = Dismissible(
      key: ValueKey('${record.familyId}/${record.id}'),
      direction: widget.onEdit == null
          ? DismissDirection.endToStart
          : DismissDirection.horizontal,
      background: widget.onEdit == null
          ? Container(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Icon(Icons.delete_outline),
            )
          : Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              color: logPalette(context).actionTint,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_outlined),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline),
            SizedBox(width: 8),
            Text('Delete'),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        // Discovery bookkeeping must not delay opening the requested action.
        unawaited(widget.onSwipeAction?.call());
        if (direction == DismissDirection.startToEnd && widget.onEdit != null) {
          await widget.onEdit!();
        } else {
          await remove();
        }
        return false;
      },
      child: Semantics(
        customSemanticsActions: {
          if (widget.onEdit != null)
            const CustomSemanticsAction(label: 'Edit entry'): () {
              widget.onEdit!();
            },
          const CustomSemanticsAction(label: 'Delete entry'): remove,
        },
        child: content,
      ),
    );
    return _SwipeDiscovery(
      enabled: widget.swipeDemoEnabled && widget.onEdit != null,
      onStart: widget.onSwipeDemoStart,
      onEnd: widget.onSwipeDemoEnd,
      child: dismissible,
    );
  }
}

/// A visual preview of both swipe directions; it never dismisses the entry.
class _SwipeDiscovery extends StatefulWidget {
  const _SwipeDiscovery({
    required this.enabled,
    required this.child,
    this.onStart,
    this.onEnd,
  });
  final bool enabled;
  final Widget child;
  final bool Function()? onStart;
  final Future<void> Function(bool completed)? onEnd;

  @override
  State<_SwipeDiscovery> createState() => _SwipeDiscoveryState();
}

class _SwipeDiscoveryState extends State<_SwipeDiscovery>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  late final Animation<double> _offset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 15),
    TweenSequenceItem(tween: ConstantTween(1), weight: 20),
    TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0, end: -1), weight: 15),
    TweenSequenceItem(tween: ConstantTween(-1), weight: 20),
    TweenSequenceItem(tween: Tween(begin: -1, end: 0), weight: 15),
  ]).animate(CurvedAnimation(parent: _animation, curve: Curves.linear));
  ScrollPosition? _position;
  Timer? _delay;
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (_position != position) {
      _position?.removeListener(_schedule);
      _position = position;
      _position?.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(_SwipeDiscovery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _cancel();
    if (widget.enabled && !oldWidget.enabled) _schedule();
  }

  void _schedule() {
    _delay?.cancel();
    if (_running &&
        ((_position?.isScrollingNotifier.value ?? false) ||
            !(ModalRoute.of(context)?.isCurrent ?? true))) {
      _cancel();
    }
    if (!widget.enabled || _running) return;
    _delay = Timer(const Duration(milliseconds: 700), _tryDemo);
  }

  Future<void> _tryDemo() async {
    if (!mounted ||
        !widget.enabled ||
        !(ModalRoute.of(context)?.isCurrent ?? true) ||
        MediaQuery.disableAnimationsOf(context) ||
        (_position?.isScrollingNotifier.value ?? false)) {
      return;
    }
    final row = context.findRenderObject();
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (row is! RenderBox ||
        viewport is! RenderBox ||
        !row.hasSize ||
        !viewport.hasSize) {
      return;
    }
    final top = row.localToGlobal(Offset.zero).dy;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    if (top < viewportTop ||
        top + math.min(row.size.height, 80) >
            viewportTop + viewport.size.height) {
      return;
    }
    if (widget.onStart?.call() != true) return;
    _running = true;
    try {
      await _animation.forward(from: 0).orCancel;
      if (!mounted || !_running) return;
      _running = false;
      await widget.onEnd?.call(true);
    } on TickerCanceled {
      // Interaction/navigation cancels the preview without changing a record.
    }
  }

  void _cancel() {
    _delay?.cancel();
    if (!_running) return;
    _running = false;
    _animation.stop(canceled: true);
    _animation.value = 0;
    unawaited(widget.onEnd?.call(false));
  }

  @override
  void dispose() {
    _cancel();
    _position?.removeListener(_schedule);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _cancel(),
    child: AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, child) => LayoutBuilder(
        builder: (context, size) {
          final shift =
              _offset.value *
              math.min(
                112.0 * MediaQuery.textScalerOf(context).scale(16) / 16,
                size.maxWidth * .65,
              );
          return ClipRect(
            child: Stack(
              children: [
                if (shift != 0)
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: Container(
                        color: shift > 0
                            ? logPalette(context).actionTint
                            : Theme.of(context).colorScheme.errorContainer,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: shift > 0
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              shift > 0
                                  ? Icons.edit_outlined
                                  : Icons.delete_outline,
                            ),
                            const SizedBox(width: 8),
                            Text(shift > 0 ? 'Edit' : 'Delete'),
                          ],
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(shift, 0),
                  child: ColoredBox(
                    color: logPalette(context).surface,
                    child: child!,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class FormHeading extends StatelessWidget {
  const FormHeading({
    super.key,
    required this.title,
    this.subtitle = '',
    this.enabled = true,
    this.method,
  });
  final String title, subtitle;
  final bool enabled;
  final String? method;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: LogSpacing.section),
    padding: method == null ? EdgeInsets.zero : const EdgeInsets.all(16),
    decoration: method == null
        ? null
        : BoxDecoration(
            color: activityTint(method!, context: context),
            borderRadius: BorderRadius.circular(20),
          ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.7,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: LogSpacing.label),
                Text(
                  method == null ? subtitle : 'For $subtitle',
                  style: TextStyle(color: logPalette(context).secondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Close',
          onPressed: enabled ? () => Navigator.maybePop(context) : null,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class EntrySheet extends StatelessWidget {
  const EntrySheet({super.key, required this.children, required this.footer});
  final List<Widget> children;
  final Widget footer;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              LogSpacing.page,
              8,
              LogSpacing.page,
              12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LogSpacing.page,
              8,
              LogSpacing.page,
              16,
            ),
            child: SizedBox(width: double.infinity, child: footer),
          ),
        ),
      ],
    ),
  );
}

class EntryTime extends StatelessWidget {
  const EntryTime({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
    this.allowNow = true,
    this.now,
  });
  final String label;
  final DateTime value;
  final ValueChanged<DateTime>? onChanged;
  final bool allowNow;
  final DateTime Function()? now;

  Future<void> chooseDate(BuildContext context) async {
    final local = value.toLocal();
    final today = DateUtils.dateOnly(DateTime.now());
    final earliest = DateTime(2000);
    // Imported records may fall outside the entry range. Keep the picker
    // usable without changing the saved value unless the user confirms.
    final initial = local.isBefore(earliest)
        ? earliest
        : local.isAfter(today)
        ? today
        : local;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: today,
    );
    if (date == null || !context.mounted) return;
    onChanged?.call(
      DateTime(
        date.year,
        date.month,
        date.day,
        local.hour,
        local.minute,
        local.second,
        local.millisecond,
        local.microsecond,
      ),
    );
  }

  Future<void> chooseTime(BuildContext context) async {
    final chosen = await showEntryTimePicker(
      context: context,
      initialValue: value,
      allowNow: allowNow,
      now: now,
    );
    if (chosen == null || !context.mounted) return;
    onChanged?.call(chosen);
  }

  @override
  Widget build(BuildContext context) {
    if (onChanged == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          Icons.schedule_outlined,
          color: logPalette(context).secondary,
        ),
        title: Text(label),
        subtitle: Text(DateFormat('MMM d · h:mm a').format(value.toLocal())),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('$label-date'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () => chooseDate(context),
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      DateFormat.yMMMd().format(value.toLocal()),
                      textAlign: TextAlign.center,
                      semanticsLabel:
                          'Date: ${DateFormat.yMMMd().format(value.toLocal())}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('$label-time'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () => chooseTime(context),
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    label: Text(
                      TimeOfDay.fromDateTime(value.toLocal()).format(context),
                      textAlign: TextAlign.center,
                      semanticsLabel:
                          'Time: ${TimeOfDay.fromDateTime(value.toLocal()).format(context)}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
