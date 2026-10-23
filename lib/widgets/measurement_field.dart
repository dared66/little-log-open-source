import '../design.dart';
import 'package:flutter/material.dart';
import 'toggle_pill.dart';

/// Converts through an exact base quantity so repeated unit switches do not
/// accumulate the rounding used to display the number.
double measurementToBase(double value, String unit) => switch (unit) {
  'lb' => value / 2.2046226218,
  'in' => value * 2.54,
  '°F' => (value - 32) * 5 / 9,
  _ => value,
};

double measurementFromBase(double value, String unit) => switch (unit) {
  'lb' => value * 2.2046226218,
  'in' => value / 2.54,
  '°F' => value * 9 / 5 + 32,
  _ => value,
};

class MeasurementField extends StatefulWidget {
  const MeasurementField({
    super.key,
    required this.label,
    required this.units,
    required this.initialUnit,
    required this.onChanged,
    this.initialValue,
    this.enabled = true,
    this.optional = false,
  });
  final String label, initialUnit;
  final List<String> units;
  final double? initialValue;
  final bool enabled, optional;
  final void Function(double? value, String unit) onChanged;

  @override
  State<MeasurementField> createState() => _MeasurementFieldState();
}

class _MeasurementFieldState extends State<MeasurementField> {
  final input = TextEditingController();
  final field = GlobalKey<FormFieldState<String>>();
  late String unit;
  double? base;

  @override
  void initState() {
    super.initState();
    unit = widget.initialUnit;
    base = widget.initialValue == null
        ? null
        : measurementToBase(widget.initialValue!, unit);
    if (widget.initialValue != null) input.text = '${widget.initialValue}';
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void edit(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    base = value == null ? null : measurementToBase(value, unit);
    widget.onChanged(value, unit);
  }

  void choose(String next) {
    if (unit == next) return;
    setState(() {
      unit = next;
      if (base != null && base!.isFinite) {
        input.text = measurementFromBase(
          base!,
          unit,
        ).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
      }
    });
    field.currentState?.didChange(input.text);
    widget.onChanged(
      base == null ? null : measurementFromBase(base!, unit),
      unit,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget amount({Widget? units}) => TextFormField(
      key: field,
      controller: input,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: '${widget.label} ($unit)',
        suffixIcon: units,
        suffixIconConstraints: const BoxConstraints(minHeight: 48),
        helperText: widget.optional ? 'Optional' : null,
        errorMaxLines: 3,
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: edit,
      validator: (_) {
        if (input.text.trim().isEmpty) {
          return widget.optional ? null : 'Enter ${widget.label} ($unit)';
        }
        final value = base == null ? null : measurementFromBase(base!, unit);
        if (value == null || !value.isFinite || value <= 0) {
          return 'Enter a positive number';
        }
        return null;
      },
    );
    final pill = TogglePill<String>(
      options: widget.units,
      value: unit,
      label: (unit) => unit,
      semanticLabel: (unit) => '${widget.label}: $unit',
      optionKey: (unit) => ValueKey('${widget.label}-unit-$unit'),
      onChanged: widget.enabled ? choose : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: LogSpacing.field),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(14) > 21) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                amount(),
                const SizedBox(height: LogSpacing.content),
                pill,
              ],
            );
          }
          return amount(
            units: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: pill,
              ),
            ),
          );
        },
      ),
    );
  }
}
