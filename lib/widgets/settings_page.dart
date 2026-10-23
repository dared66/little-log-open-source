import '../design.dart';
import 'toggle_pill.dart';
import 'package:flutter/material.dart';
import '../controller.dart';
import '../volume.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool saving = false;
  String? error;

  Future<void> choose(Future<void> Function() save) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await save();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save the setting. Try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget unitSetting(
    String title,
    List<String> options,
    String value,
    Future<void> Function(String) save,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: LogSpacing.section),
      FieldLabel(title),
      TogglePill<String>(
        options: options,
        value: value,
        label: (unit) => unit,
        semanticLabel: (unit) => '$title: $unit',
        optionKey: (unit) => ValueKey('default-${title.toLowerCase()}-$unit'),
        onChanged: saving ? null : (unit) => choose(() => save(unit)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: logPageAppBar(context, 'Units'),
    body: LogPageFrame(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Volume'),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TogglePill<VolumeUnit>(
                      options: const [VolumeUnit.oz, VolumeUnit.ml],
                      value: widget.controller.volumeUnit,
                      label: (unit) => unit.label,
                      semanticLabel: (unit) => unit == VolumeUnit.ml
                          ? 'Milliliters (ml)'
                          : 'US fluid ounces (oz)',
                      optionKey: (unit) =>
                          ValueKey('default-volume-${unit.name}'),
                      onChanged: saving
                          ? null
                          : (unit) => choose(
                              () => widget.controller.setVolumeUnit(unit),
                            ),
                    ),
                  ),
                  unitSetting(
                    'Weight',
                    const ['kg', 'lb'],
                    widget.controller.weightUnit,
                    widget.controller.setWeightUnit,
                  ),
                  unitSetting(
                    'Length',
                    const ['cm', 'in'],
                    widget.controller.lengthUnit,
                    widget.controller.setLengthUnit,
                  ),
                  unitSetting(
                    'Temperature',
                    const ['°C', '°F'],
                    widget.controller.temperatureUnit,
                    widget.controller.setTemperatureUnit,
                  ),
                  if (saving) ...[
                    const SizedBox(height: LogSpacing.field),
                    const Text(
                      'Saving…',
                      semanticsLabel: 'Saving default units',
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: LogSpacing.field),
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
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
