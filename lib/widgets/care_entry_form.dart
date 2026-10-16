import 'selection_chip.dart';
import 'delete_entry_button.dart';
import 'toggle_pill.dart';
import '../models.dart';
import 'volume_field.dart';
import 'package:flutter/material.dart';
import '../controller.dart';
import '../design.dart';
import '../diaper_details.dart';

class BottleEntryForm extends StatelessWidget {
  const BottleEntryForm({super.key, required this.controller, this.original});
  final AppController controller;
  final Feeding? original;
  @override
  Widget build(BuildContext context) => _CareEntryForm(
    controller: controller,
    kind: _EntryKind.bottle,
    original: original,
  );
}

class NursingEntryForm extends StatelessWidget {
  const NursingEntryForm({
    super.key,
    required this.controller,
    this.original,
    this.onResume,
  });
  final AppController controller;
  final Feeding? original;
  final ValueChanged<String>? onResume;
  @override
  Widget build(BuildContext context) => _CareEntryForm(
    controller: controller,
    kind: _EntryKind.nursing,
    original: original,
    onResume: onResume,
  );
}

class DiaperEntryForm extends StatelessWidget {
  const DiaperEntryForm({super.key, required this.controller, this.original});
  final AppController controller;
  final Feeding? original;
  @override
  Widget build(BuildContext context) => _CareEntryForm(
    controller: controller,
    kind: _EntryKind.diaper,
    original: original,
  );
}

enum _EntryKind { bottle, nursing, diaper }

class _CareEntryForm extends StatefulWidget {
  const _CareEntryForm({
    required this.controller,
    required this.kind,
    this.original,
    this.onResume,
  });
  final AppController controller;
  final Feeding? original;
  final ValueChanged<String>? onResume;
  final _EntryKind kind;
  @override
  State<_CareEntryForm> createState() => _CareEntryFormState();
}

class _CareEntryFormState extends State<_CareEntryForm> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController();
  final note = TextEditingController();
  final leftMinutes = TextEditingController(),
      rightMinutes = TextEditingController();
  final leftSeconds = TextEditingController(),
      rightSeconds = TextEditingController();
  bool perSide = false;
  bool get timedNursing => perSide;
  bool get legacyNursing =>
      widget.kind == _EntryKind.nursing &&
      widget.original != null &&
      widget.original!.leftSeconds == null;
  String contents = 'milk';
  double? breastMilkMl, formulaMl;
  final formulaName = TextEditingController();
  late final String familyId;
  late final String babyName;
  double? volumeMl;
  String diaperKind = 'wet';
  List<String> selectedColors = [], selectedConsistencies = [];
  bool? blowout, rash = false;
  DateTime at = DateTime.now();
  bool saving = false;
  String? error;
  String get method => widget.kind.name;
  bool get diaper => widget.kind == _EntryKind.diaper;
  bool get bottle => widget.kind == _EntryKind.bottle;
  String get title => switch (widget.kind) {
    _EntryKind.bottle => 'Bottle',
    _EntryKind.nursing => 'Nursing',
    _EntryKind.diaper => 'Diaper',
  };
  @override
  void initState() {
    super.initState();
    familyId = widget.controller.family!.id;
    babyName = widget.controller.family!.babyName;
    final old = widget.original;
    if (widget.kind == _EntryKind.nursing) {
      perSide = true;
      for (final field in [
        leftMinutes,
        rightMinutes,
        leftSeconds,
        rightSeconds,
      ]) {
        field.text = '0';
      }
    }
    if (old != null) {
      at = old.at.toLocal();
      note.text = old.note;
      volumeMl = old.amountMl;
      amount.text = '${old.minutes ?? 1}';
      leftMinutes.text = '${(old.leftSeconds ?? 0) ~/ 60}';
      rightMinutes.text = '${(old.rightSeconds ?? 0) ~/ 60}';
      leftSeconds.text = '${(old.leftSeconds ?? 0) % 60}';
      rightSeconds.text = '${(old.rightSeconds ?? 0) % 60}';
      diaperKind = old.diaperKind ?? 'wet';
      selectedColors = diaperValues(old.details, 'poopColor', 'poopColors');
      selectedConsistencies = diaperValues(
        old.details,
        'poopConsistency',
        'poopConsistencies',
      );
      perSide = old.leftSeconds != null;
      breastMilkMl = (old.details['breastMilkMl'] as num?)?.toDouble();
      formulaMl = (old.details['formulaMl'] as num?)?.toDouble();
      contents = breastMilkMl == null
          ? 'unknown'
          : breastMilkMl! > 0 && (formulaMl ?? 0) > 0
          ? 'mixed'
          : breastMilkMl! > 0
          ? 'milk'
          : 'formula';
      formulaName.text = old.details['formulaName'] as String? ?? '';
      blowout = old.details['blowout'] as bool?;
      rash = old.details['rash'] as bool?;
    }
  }

  @override
  void dispose() {
    formulaName.dispose();
    leftMinutes.dispose();
    rightMinutes.dispose();
    leftSeconds.dispose();
    rightSeconds.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  int? sideDuration(
    TextEditingController minutes,
    TextEditingController seconds,
  ) {
    final m = int.tryParse(minutes.text);
    final s = int.tryParse(seconds.text);
    if (m == null || s == null || m < 0 || s < 0 || s > 59) return null;
    return m * 60 + s;
  }

  String? validateSideDuration(String? _) {
    final l = sideDuration(leftMinutes, leftSeconds);
    final r = sideDuration(rightMinutes, rightSeconds);
    if (l == null || r == null) return 'Enter whole minutes and 0–59 seconds.';
    final unchanged =
        l == widget.original?.leftSeconds && r == widget.original?.rightSeconds;
    if (!unchanged && (l + r <= 0 || l + r > 14400)) {
      return 'Total must be 1–240 minutes.';
    }
    return null;
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (diaper) {
        await widget.controller.addDiaper(
          kind: diaperKind,
          at: at,
          note: note.text,
          selectedColors: selectedColors,
          selectedConsistencies: selectedConsistencies,
          blowout: blowout,
          rash: rash,
          original: widget.original,
          expectedFamilyId: familyId,
        );
      } else {
        await widget.controller.addFeed(
          at: at,
          method: method,
          amountMl: bottle
              ? (contents == 'mixed'
                    ? (breastMilkMl ?? 0) + (formulaMl ?? 0)
                    : volumeMl)
              : null,
          details: bottle && contents != 'unknown'
              ? {
                  'breastMilkMl': contents == 'milk'
                      ? volumeMl
                      : contents == 'mixed'
                      ? breastMilkMl
                      : 0.0,
                  'formulaMl': contents == 'formula'
                      ? volumeMl
                      : contents == 'mixed'
                      ? formulaMl
                      : 0.0,
                  if (contents != 'milk' && formulaName.text.trim().isNotEmpty)
                    'formulaName': formulaName.text.trim(),
                }
              : const {},
          minutes: bottle
              ? null
              : timedNursing
              ? ((sideDuration(leftMinutes, leftSeconds)! +
                            sideDuration(rightMinutes, rightSeconds)!) /
                        60)
                    .ceil()
              : int.parse(amount.text),
          leftSeconds: timedNursing
              ? sideDuration(leftMinutes, leftSeconds)
              : null,
          rightSeconds: timedNursing
              ? sideDuration(rightMinutes, rightSeconds)
              : null,
          note: note.text,
          original: widget.original,
          expectedFamilyId: familyId,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${bottle
                  ? 'Bottle'
                  : diaper
                  ? 'Diaper'
                  : 'Nursing session'} saved',
            ),
            behavior: SnackBarBehavior.fixed,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = AppController.friendlyError(e);
        });
      }
    }
  }

  Widget multiChoice(
    String label,
    List<String> values,
    Map<String, String> choices,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in choices.entries)
              SelectionChip(
                multiple: true,
                label: Text(e.value),
                selected: values.contains(e.key),
                onSelected: saving
                    ? null
                    : (selected) => setState(() {
                        if (selected) {
                          values.add(e.key);
                        } else {
                          values.remove(e.key);
                        }
                        values.sort();
                      }),
              ),
          ],
        ),
      ],
    ),
  );
  Widget observation(String label, bool? value, ValueChanged<bool?> changed) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value ?? false,
        onChanged: saving ? null : (v) => setState(() => changed(v)),
      );

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: EntrySheet(
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(
              saving
                  ? 'Saving…'
                  : widget.original == null
                  ? 'Save $method'
                  : 'Save changes',
            ),
          ),
          if (widget.original case final Feeding original)
            DeleteEntryButton(
              controller: widget.controller,
              record: original,
              busy: saving,
              onBusyChanged: (value) => setState(() => saving = value),
            ),
        ],
      ),
      children: [
        FormHeading(
          title: widget.original == null
              ? title
              : '${method[0].toUpperCase()}${method.substring(1)}',
          subtitle: babyName,
          enabled: !saving,
          method: method,
        ),
        if (method == 'nursing' &&
            widget.original?.leftSeconds != null &&
            widget.original?.rightSeconds != null &&
            widget.onResume != null) ...[
          const Text(
            'Continue this session',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: LogSpacing.label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final side in ['left', 'right'])
                OutlinedButton(
                  onPressed: saving ? null : () => widget.onResume!(side),
                  child: Text('Resume $side timer'),
                ),
            ],
          ),
          const SizedBox(height: LogSpacing.field),
        ],
        if (diaper) ...[
          const Text(
            'Diaper contents',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: LogSpacing.label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in ['wet', 'dirty'])
                SelectionChip(
                  multiple: true,
                  label: Text(kind == 'wet' ? 'Wet' : 'Dirty'),
                  selected: diaperKind == kind || diaperKind == 'both',
                  onSelected: saving
                      ? null
                      : (selected) => setState(() {
                          final wet = kind == 'wet'
                              ? selected
                              : diaperKind == 'wet' || diaperKind == 'both';
                          final dirty = kind == 'dirty'
                              ? selected
                              : hasPoop(diaperKind);
                          diaperKind = wet && dirty
                              ? 'both'
                              : wet
                              ? 'wet'
                              : dirty
                              ? 'dirty'
                              : 'dry';
                          if (dirty) blowout ??= false;
                          if (!dirty) {
                            selectedColors = [];
                            selectedConsistencies = [];
                            blowout = null;
                          }
                        }),
                ),
            ],
          ),
          if (diaperKind == 'dry')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Dry diaper'),
            ),
          const SizedBox(height: LogSpacing.section),
          if (hasPoop(diaperKind)) ...[
            const SectionHeading(title: 'Poop details'),
            multiChoice('Poop color', selectedColors, poopColors),
            multiChoice(
              'Consistency',
              selectedConsistencies,
              poopConsistencies,
            ),
            observation('Blowout', blowout, (v) => blowout = v),
          ],
          observation('Diaper rash', rash, (v) => rash = v),
        ] else ...[
          if (bottle) ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: contents,
              decoration: const InputDecoration(labelText: 'Bottle contents'),
              items: const [
                DropdownMenuItem(value: 'unknown', child: Text('Not recorded')),
                DropdownMenuItem(value: 'milk', child: Text('Breast milk')),
                DropdownMenuItem(value: 'formula', child: Text('Formula')),
                DropdownMenuItem(
                  value: 'mixed',
                  child: Text('Breast milk + formula'),
                ),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() => contents = value!),
            ),
            const SizedBox(height: LogSpacing.field),
            if (contents == 'mixed') ...[
              VolumeField(
                key: const ValueKey('milk-volume'),
                label: 'Breast milk amount',
                initialMl: breastMilkMl,
                initialUnit: widget.controller.volumeUnit,
                enabled: !saving,
                onChanged: (v) => breastMilkMl = v,
              ),
              const SizedBox(height: LogSpacing.content),
              VolumeField(
                key: const ValueKey('formula-volume'),
                label: 'Formula amount',
                initialMl: formulaMl,
                initialUnit: widget.controller.volumeUnit,
                enabled: !saving,
                onChanged: (v) => formulaMl = v,
              ),
            ] else
              VolumeField(
                key: const ValueKey('total-volume'),
                label: 'Amount',
                initialMl: volumeMl,
                initialUnit: widget.controller.volumeUnit,
                enabled: !saving,
                onChanged: (v) => volumeMl = v,
              ),
            if (contents == 'formula' || contents == 'mixed') ...[
              const SizedBox(height: LogSpacing.content),
              TextFormField(
                controller: formulaName,
                enabled: !saving,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Formula name (optional)',
                ),
              ),
            ],
          ],
          if (legacyNursing)
            BooleanSelection(
              label: 'Add side details',
              value: perSide,
              onChanged: saving
                  ? null
                  : (v) => setState(() {
                      perSide = v;
                      for (final field in [
                        leftMinutes,
                        rightMinutes,
                        leftSeconds,
                        rightSeconds,
                      ]) {
                        if (field.text.isEmpty) field.text = '0';
                      }
                    }),
            ),
          if (!bottle && !timedNursing)
            TextFormField(
              controller: amount,
              enabled: !saving,
              readOnly: legacyNursing,
              keyboardType: TextInputType.numberWithOptions(decimal: bottle),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: bottle ? 'Amount (ml)' : 'Duration (minutes)',
              ),
              validator: (v) {
                final n = num.tryParse(v ?? '');
                if (n == null ||
                    !n.isFinite ||
                    n <= 0 ||
                    n > (bottle ? 2000 : 240) ||
                    (!bottle && int.tryParse(v ?? '') == null)) {
                  return bottle
                      ? 'Enter more than 0, up to 2,000 ml.'
                      : 'Enter 1–240 whole minutes.';
                }
                return null;
              },
            ),
          if (legacyNursing && !timedNursing)
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 12),
              child: Text(
                'This older entry has no recorded side. Add side details to change its duration.',
              ),
            ),
          if (timedNursing)
            for (final side in [
              (leftMinutes, leftSeconds, 'Left'),
              (rightMinutes, rightSeconds, 'Right'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      side.$3,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: LogSpacing.label),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: side.$1,
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText: 'Minutes',
                            ),
                            keyboardType: TextInputType.number,
                            validator: validateSideDuration,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: side.$2,
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText: 'Seconds',
                            ),
                            keyboardType: TextInputType.number,
                            validator: validateSideDuration,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          const SizedBox(height: LogSpacing.label),
        ],
        EntryTime(
          label: diaper ? 'When' : 'Started',
          value: at,
          onChanged: saving ? null : (chosen) => setState(() => at = chosen),
        ),
        const SizedBox(height: LogSpacing.field),
        TextFormField(
          controller: note,
          enabled: !saving,
          maxLength: 2000,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            counterText: '',
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    ),
  );
}
