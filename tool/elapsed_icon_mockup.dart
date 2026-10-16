import 'dart:async';
import 'package:flutter/material.dart';
import 'package:little_log/design.dart';
import 'package:little_log/quick_log.dart';
import 'package:little_log/widgets/elapsed_activity_glyph.dart';

const sampleElapsed = <String, Duration?>{
  'bottle': Duration(hours: 2, minutes: 15),
  'nursing': Duration(minutes: 40),
  'diaper': Duration(hours: 1, minutes: 15),
  'sleep': Duration(hours: 7, minutes: 10),
  'pumping': Duration(hours: 3, minutes: 10),
  'solids': Duration(hours: 3, minutes: 35),
};

typedef ElapsedMockGlyphBuilder =
    Widget Function(BuildContext, String, Duration?, double);

// Dedicated local preview. No controller, real records, auth, or sync services.
void main() => runApp(const ElapsedIconsMockupApp());

class ElapsedIconsMockupApp extends StatelessWidget {
  const ElapsedIconsMockupApp({
    super.key,
    this.brightness = Brightness.dark,
    this.elapsed = sampleElapsed,
    this.design = const ElapsedGlyphDesign(),
    this.live = false,
    this.now = DateTime.now,
    this.pickerIconSize = 64,
    this.glyphBuilder,
  });
  final Brightness brightness;
  final Map<String, Duration?> elapsed;
  final ElapsedGlyphDesign design;
  final bool live;
  final DateTime Function() now;
  final double pickerIconSize;
  final ElapsedMockGlyphBuilder? glyphBuilder;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('elapsed-capture-root'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: littleLogTheme(brightness: brightness),
      home: _MockupPage(
        initialElapsed: elapsed,
        design: design,
        live: live,
        now: now,
        pickerIconSize: pickerIconSize,
        glyphBuilder: glyphBuilder,
      ),
    ),
  );
}

class _MockupPage extends StatefulWidget {
  const _MockupPage({
    required this.initialElapsed,
    required this.design,
    required this.live,
    required this.now,
    required this.pickerIconSize,
    required this.glyphBuilder,
  });
  final Map<String, Duration?> initialElapsed;
  final ElapsedGlyphDesign design;
  final bool live;
  final DateTime Function() now;
  final double pickerIconSize;
  final ElapsedMockGlyphBuilder? glyphBuilder;
  @override
  State<_MockupPage> createState() => _MockupPageState();
}

class _MockupPageState extends State<_MockupPage> {
  late final elapsed = Map<String, Duration?>.from(widget.initialElapsed);
  final lastPerformed = <String, DateTime?>{};
  Timer? timer;

  @override
  void initState() {
    super.initState();
    final now = widget.now();
    for (final entry in elapsed.entries) {
      lastPerformed[entry.key] = entry.value == null
          ? null
          : now.subtract(entry.value!);
    }
    if (widget.live) {
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final now = widget.now();
        var changed = false;
        for (final entry in lastPerformed.entries) {
          final duration = entry.value == null
              ? null
              : now.difference(entry.value!);
          if (elapsedIconLabel(elapsed[entry.key]) !=
              elapsedIconLabel(duration)) {
            changed = true;
          }
          elapsed[entry.key] = duration;
        }
        if (changed) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void log(String method) => setState(() {
    lastPerformed[method] = widget.now();
    elapsed[method] = Duration.zero;
  });

  Widget glyph(String method, {double size = 96}) =>
      widget.glyphBuilder?.call(context, method, elapsed[method], size) ??
      ElapsedActivityGlyph(
        method: method,
        label: quickLogActivities[method]!,
        fallback: activityIcon(method),
        elapsed: elapsed[method],
        color: activityAccent(method, context: context),
        size: size,
        design: widget.design,
      );

  String semanticLabel(String method) =>
      '${quickLogActivities[method]} · ${elapsedIconLabel(elapsed[method]).spoken}';

  Future<void> allActivities() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final palette = logPalette(sheetContext);
      return FractionallySizedBox(
        heightFactor: .9,
        child: LogPageFrame(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Log an activity',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: LogSpacing.content),
                  for (final method in elapsedIconActivities)
                    Padding(
                      padding: const EdgeInsets.only(bottom: LogSpacing.label),
                      child: TextButton(
                        key: ValueKey('picker-$method'),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          log(method);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: palette.ink,
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: activityTint(
                                  method,
                                  context: sheetContext,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ExcludeSemantics(
                                child: glyph(
                                  method,
                                  size: widget.pickerIconSize,
                                ),
                              ),
                            ),
                            const SizedBox(width: LogSpacing.field),
                            Expanded(
                              child: Text(
                                quickLogActivities[method]!,
                                semanticsLabel: semanticLabel(method),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: palette.secondary),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final palette = logPalette(context);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('Robin'),
        actions: [
          TextButton.icon(
            onPressed: () {},
            label: const Text('Today 14'),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LogPageFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            SectionHeading(
              compact: true,
              title: 'Quick log',
              action: 'Customize',
              onAction: () {},
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: LogSpacing.content),
              child: Text(
                'Since last log',
                style: TextStyle(fontSize: 12, color: palette.secondary),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                // Match the existing two-column Wrap. Allow one column when
                // scaled glyphs would otherwise lose legible interior text.
                final columns =
                    (constraints.maxWidth - 12) / 2 >= 96 * scale + 32 ? 2 : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final method in elapsedIconActivities)
                      SizedBox(
                        width: width,
                        child: OutlinedButton(
                          key: ValueKey('mock-log-$method'),
                          onPressed: () => log(method),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: activityTint(
                              method,
                              context: context,
                            ),
                            foregroundColor: activityAccent(
                              method,
                              context: context,
                            ),
                            padding: const EdgeInsets.all(16),
                            side: BorderSide.none,
                          ),
                          child: Column(
                            children: [
                              ExcludeSemantics(child: glyph(method)),
                              const SizedBox(height: LogSpacing.label),
                              Text(
                                quickLogActivities[method]!,
                                semanticsLabel: semanticLabel(method),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('mock-all-activities'),
                onPressed: allActivities,
                child: const Text('See all activities'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            label: 'Log',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
