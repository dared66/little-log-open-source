import 'package:flutter/material.dart';
import '../design.dart';

/// Compact, mutually exclusive choices shared by units and boolean controls.
class TogglePill<T> extends StatelessWidget {
  const TogglePill({
    super.key,
    required this.options,
    required this.value,
    required this.label,
    required this.onChanged,
    this.semanticLabel,
    this.optionKey,
  });
  final List<T> options;
  final T value;
  final String Function(T) label;
  final String Function(T)? semanticLabel;
  final Key Function(T)? optionKey;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          Semantics(
            button: true,
            selected: value == option,
            enabled: onChanged != null,
            onTap: onChanged == null ? null : () => onChanged!(option),
            label: semanticLabel?.call(option) ?? label(option),
            excludeSemantics: true,
            child: Material(
              color: value == option
                  ? logPalette(context).actionTint
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                key: optionKey?.call(option),
                borderRadius: BorderRadius.circular(999),
                onTap: onChanged == null ? null : () => onChanged!(option),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 32,
                    ),
                    child: Center(
                      child: Text(
                        label(option),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: value == option
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: logPalette(context).actionInk,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class BooleanSelection extends StatelessWidget {
  const BooleanSelection({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(label);
        final pill = TogglePill<bool>(
          options: const [false, true],
          value: value,
          label: (v) => v ? 'Yes' : 'No',
          semanticLabel: (v) => '$label: ${v ? 'Yes' : 'No'}',
          optionKey: (v) => ValueKey('$label-$v'),
          onChanged: onChanged,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(14) > 21) ...[
              title,
              const SizedBox(height: LogSpacing.label),
              pill,
            ] else
              Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  pill,
                ],
              ),
            if (subtitle != null) ...[
              const SizedBox(height: LogSpacing.label),
              Text(subtitle!),
            ],
          ],
        );
      },
    ),
  );
}
