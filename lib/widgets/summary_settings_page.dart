import 'package:flutter/material.dart';
import '../controller.dart';
import '../design.dart';

class SummarySettingsPage extends StatefulWidget {
  const SummarySettingsPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<SummarySettingsPage> createState() => _SummarySettingsPageState();
}

class _SummarySettingsPageState extends State<SummarySettingsPage> {
  bool saving = false;
  String? error;

  Future<void> toggle(String metric) async {
    final choices = [...widget.controller.summaryMetrics];
    if (choices.contains(metric)) {
      if (choices.length == 1) return;
      choices.remove(metric);
    } else {
      choices.add(metric);
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.setSummaryMetrics(choices);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save summary. Try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: logPageAppBar(context, 'Customize summary'),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                const SectionHeading(title: 'At a glance'),
                for (final metric in [
                  'Nursing',
                  'Bottle',
                  'Diapers',
                  'Sleep',
                  'Pumped',
                ])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(metric),
                    value: widget.controller.summaryMetrics.contains(metric),
                    onChanged:
                        saving ||
                            (widget.controller.summaryMetrics.length == 1 &&
                                widget.controller.summaryMetrics.contains(
                                  metric,
                                ))
                        ? null
                        : (_) => toggle(metric),
                  ),
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
