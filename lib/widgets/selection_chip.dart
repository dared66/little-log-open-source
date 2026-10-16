import 'package:flutter/material.dart';
import '../design.dart';

/// Shared visual language for single- and multiple-selection options.
/// Native chip semantics retain selected, disabled and radio-group states.
class SelectionChip extends StatelessWidget {
  const SelectionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.avatar,
    this.multiple = false,
  });

  final Widget label;
  final Widget? avatar;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool multiple;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: selected ? logPalette(context).actionInk : logPalette(context).ink,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );
    final border = BorderSide(
      color: selected
          ? logPalette(context).actionInk.withValues(alpha: 0.35)
          : Theme.of(context).colorScheme.outlineVariant,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    if (multiple) {
      return FilterChip(
        label: label,
        avatar: avatar,
        selected: selected,
        onSelected: onSelected,
        showCheckmark: false,
        selectedColor: logPalette(context).actionTint,
        backgroundColor: logPalette(context).surface,
        disabledColor: logPalette(context).background,
        labelStyle: textStyle,
        side: border,
        shape: shape,
      );
    }
    return ChoiceChip(
      label: label,
      avatar: avatar,
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: logPalette(context).actionTint,
      backgroundColor: logPalette(context).surface,
      disabledColor: logPalette(context).background,
      labelStyle: textStyle,
      side: border,
      shape: shape,
    );
  }
}
