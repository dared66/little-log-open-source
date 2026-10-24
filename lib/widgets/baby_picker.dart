import 'confirm_removal.dart';
import 'selection_chip.dart';
import 'package:flutter/material.dart';
import '../controller.dart';
import '../design.dart';
import '../models.dart';
import '../storage/repository.dart';
import 'onboarding.dart';

Future<bool?> _createBaby(BuildContext context, AppController controller) =>
    Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OnboardingPage(
          controller: controller,
          initialStage: OnboardingStage.create,
          addingBaby: true,
        ),
      ),
    );

class BabyPickerButton extends StatelessWidget {
  const BabyPickerButton({
    super.key,
    required this.controller,
    this.identity,
    this.showChevron = true,
  });
  final AppController controller;
  final Widget? identity;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      controller.family!.babyName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
    );
    final identity = this.identity ?? label;
    if (controller.families.length < 2) return identity;
    return Semantics(
      label: 'Switch baby',
      child: TextButton(
        key: const ValueKey('baby-switcher'),
        onPressed: controller.babyPickerBusy
            ? null
            : () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _BabyPicker(controller: controller),
              ),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(48, 48),
          alignment: Alignment.centerLeft,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: identity),
            if (showChevron) ...[
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: logPalette(context).actionTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const SizedBox.square(
                  dimension: 28,
                  child: Icon(Icons.expand_more, size: 24),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BabyPicker extends StatefulWidget {
  const _BabyPicker({required this.controller});
  final AppController controller;
  @override
  State<_BabyPicker> createState() => _BabyPickerState();
}

class _BabyPickerState extends State<_BabyPicker> {
  String? error;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Switch baby',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: LogSpacing.content),
            for (final baby in c.families)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.child_care),
                title: Text(baby.babyName),
                subtitle: Text(baby.ownerLabel),
                selected: baby.id == c.family?.id,
                trailing: baby.id == c.family?.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: c.babyPickerBusy
                    ? null
                    : () async {
                        try {
                          await c.select(baby);
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (mounted) {
                            setState(
                              () => error = AppController.friendlyError(e),
                            );
                          }
                        }
                      },
              ),
            if (c.families.length < Repository.maxBabies) ...[
              const SizedBox(height: LogSpacing.content),
              OutlinedButton.icon(
                onPressed: c.babyPickerBusy
                    ? null
                    : () async {
                        final created = await _createBaby(context, c);
                        if (created == true && context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                icon: const Icon(Icons.add),
                label: const Text('Add baby'),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: LogSpacing.content),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class ManageBabyTile extends StatelessWidget {
  const ManageBabyTile({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.child_care),
      title: const Text('Manage baby'),
      trailing: const Icon(Icons.chevron_right),
      onTap: controller.babyPickerBusy
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => _ManageBabies(controller: controller),
            ),
    ),
  );
}

class _ManageBabies extends StatelessWidget {
  const _ManageBabies({required this.controller});
  final AppController controller;

  Future<void> delete(BuildContext context, Family baby) async {
    final confirmed = await confirmRemoval(
      context,
      title: 'Delete ${baby.babyName}?',
      message:
          'This removes this baby’s history and any running timers from this device. This cannot be undone.${baby.isLocal ? '' : ' The shared Google Drive log and caregivers’ copies will remain.'}',
      confirmLabel: 'Delete baby',
    );
    if (confirmed != true || !context.mounted) return;
    await controller.run(() => controller.deleteBaby(baby));
    if (context.mounted && controller.family == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Manage baby',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          for (final baby in controller.families)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    baby.babyName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: LogSpacing.detail),
                  Text(
                    baby.storageLabel,
                    style: TextStyle(color: logPalette(context).secondary),
                  ),
                  const SizedBox(height: LogSpacing.label),
                  Text(
                    'Background color',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: LogSpacing.label),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final choice in babyBackgrounds.entries)
                        SelectionChip(
                          key: ValueKey(
                            'baby-background-${baby.id}-${choice.key}',
                          ),
                          label: Text(choice.value.label),
                          avatar: CircleAvatar(
                            backgroundColor: choice.value.color,
                            radius: 10,
                          ),
                          selected:
                              controller.backgroundChoice(baby.id) ==
                              choice.key,
                          onSelected: controller.babyPickerBusy
                              ? null
                              : (_) => controller.run(
                                  () => controller.setBabyBackground(
                                    baby.id,
                                    choice.key,
                                  ),
                                ),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton.icon(
                        key: ValueKey('rename-${baby.id}'),
                        onPressed: controller.babyPickerBusy
                            ? null
                            : () => showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder: (_) => _RenameBaby(
                                  controller: controller,
                                  baby: baby,
                                ),
                              ),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit name'),
                      ),
                      TextButton.icon(
                        key: ValueKey('delete-${baby.id}'),
                        onPressed: controller.babyPickerBusy
                            ? null
                            : () => delete(context, baby),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete baby'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (controller.families.length < Repository.maxBabies)
            OutlinedButton.icon(
              onPressed: controller.babyPickerBusy
                  ? null
                  : () => _createBaby(context, controller),
              icon: const Icon(Icons.add),
              label: const Text('Add baby'),
            )
          else
            const Text('3 of 3 babies added'),
          if (controller.message != null)
            Text(
              controller.message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}

class _RenameBaby extends StatefulWidget {
  const _RenameBaby({required this.controller, required this.baby});
  final AppController controller;
  final Family baby;
  @override
  State<_RenameBaby> createState() => _RenameBabyState();
}

class _RenameBabyState extends State<_RenameBaby> {
  late final name = TextEditingController(text: widget.baby.babyName);
  final form = GlobalKey<FormState>();
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final c = widget.controller;
    if (c.babyPickerBusy || !form.currentState!.validate()) return;
    await c.run(() => c.renameBaby(widget.baby, name.text));
    if (!mounted) return;
    if (c.message == null) {
      Navigator.pop(context);
    } else {
      setState(() => error = c.message);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit baby name',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text('Name changes apply on this device.'),
            const SizedBox(height: LogSpacing.field),
            TextFormField(
              controller: name,
              autofocus: true,
              enabled: !widget.controller.babyPickerBusy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Baby’s name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your baby’s name.'
                  : null,
              onFieldSubmitted: (_) => save(),
            ),
            const SizedBox(height: LogSpacing.field),
            FilledButton(
              onPressed: widget.controller.babyPickerBusy ? null : save,
              child: Text(widget.controller.working ? 'Saving…' : 'Save name'),
            ),
            if (error != null) ...[
              const SizedBox(height: LogSpacing.content),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
