import 'package:flutter/material.dart';
import '../controller.dart';
import '../models.dart';
import 'confirm_removal.dart';

class DeleteEntryButton extends StatefulWidget {
  const DeleteEntryButton({
    super.key,
    required this.controller,
    required this.record,
    required this.busy,
    required this.onBusyChanged,
  });
  final AppController controller;
  final Feeding record;
  final bool busy;
  final ValueChanged<bool> onBusyChanged;
  @override
  State<DeleteEntryButton> createState() => _DeleteEntryButtonState();
}

class _DeleteEntryButtonState extends State<DeleteEntryButton> {
  Future<void> remove() async {
    if (widget.busy) return;
    final local = widget.controller.family?.isLocal ?? true;
    final confirmed = await confirmRemoval(
      context,
      title: 'Delete this entry?',
      message: local
          ? 'Deletes this entry from this device.'
          : 'Deletes this entry from this device and the shared log when it syncs.',
      confirmLabel: 'Delete entry',
    );
    if (!confirmed || !mounted || widget.busy) return;
    widget.onBusyChanged(true);
    try {
      await widget.controller.deleteRecord(widget.record);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppController.friendlyError(e))));
      }
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton(
    key: const ValueKey('delete-saved-entry'),
    onPressed: widget.busy ? null : remove,
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.error,
    ),
    child: const Text('Delete entry'),
  );
}
