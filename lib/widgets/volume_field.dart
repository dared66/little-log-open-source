import '../design.dart';
import 'package:flutter/material.dart';
import '../volume.dart';
import 'toggle_pill.dart';

/// Keeps an unrounded ml value while toggling units. Only editing the number
/// changes the quantity; rounding the displayed conversion never changes a save.
class VolumeField extends StatefulWidget {
  const VolumeField({
    super.key,
    required this.label,
    required this.initialUnit,
    required this.onChanged,
    this.onUnitChanged,
    this.initialMl,
    this.enabled = true,
  });
  final double? initialMl;
  final String label;
  final VolumeUnit initialUnit;
  final ValueChanged<double?> onChanged;
  final ValueChanged<VolumeUnit>? onUnitChanged;
  final bool enabled;
  @override
  State<VolumeField> createState() => _VolumeFieldState();
}

class _VolumeFieldState extends State<VolumeField> {
  final input = TextEditingController();
  final field = GlobalKey<FormFieldState<String>>();
  late VolumeUnit unit;
  double? amountMl;
  @override
  void initState() {
    super.initState();
    unit = widget.initialUnit;
    amountMl = widget.initialMl;
    if (amountMl != null) {
      input.text = unit
          .fromMl(amountMl!)
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'\.?0+$'), '');
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void edit(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    setState(() => amountMl = value == null ? null : unit.toMl(value));
    widget.onChanged(amountMl);
  }

  void choose(VolumeUnit next) {
    if (unit == next) return;
    setState(() {
      unit = next;
      if (amountMl != null && amountMl!.isFinite) {
        // Keep the entry readable; canonical ml remains exact across switches.
        input.text = unit
            .fromMl(amountMl!)
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'\.?0+$'), '');
      }
    });
    field.currentState?.didChange(input.text);
    widget.onUnitChanged?.call(unit);
  }

  @override
  Widget build(BuildContext context) {
    final amountField = TextFormField(
      key: field,
      controller: input,
      enabled: widget.enabled,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: '${widget.label} (${unit.label})',
        errorMaxLines: 3,
      ),
      onChanged: edit,
      validator: (_) {
        if (input.text.trim().isEmpty) {
          return 'Enter ${widget.label} (${unit.label})';
        }
        if (amountMl == null ||
            !amountMl!.isFinite ||
            amountMl! <= 0 ||
            amountMl! > 2000) {
          return unit == VolumeUnit.ml
              ? 'Enter more than 0, up to 2,000 ml.'
              : 'Enter more than 0, up to 67.62 US fl oz.';
        }
        return null;
      },
    );
    final pill = TogglePill<VolumeUnit>(
      key: const ValueKey('volume-unit-pill'),
      options: const [VolumeUnit.oz, VolumeUnit.ml],
      value: unit,
      label: (option) => option.label,
      semanticLabel: (option) =>
          option == VolumeUnit.oz ? 'US fluid ounces' : 'Milliliters',
      optionKey: (option) => ValueKey('volume-${option.name}'),
      onChanged: widget.enabled ? choose : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: LogSpacing.field),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
          if (constraints.maxWidth < 280 || largeText) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                amountField,
                const SizedBox(height: LogSpacing.content),
                pill,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: amountField),
              const SizedBox(width: 12),
              pill,
            ],
          );
        },
      ),
    );
  }
}
