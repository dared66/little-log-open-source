import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../controller.dart';
import '../design.dart';
import '../quick_log.dart';

class QuickLogSettingsPage extends StatefulWidget {
  const QuickLogSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<QuickLogSettingsPage> createState() => _QuickLogSettingsPageState();
}

class _QuickLogSettingsPageState extends State<QuickLogSettingsPage> {
  bool saving = false;
  String? error;
  late List<String> availableOrder;

  @override
  void initState() {
    super.initState();
    availableOrder = quickLogActivities.keys.toList();
  }

  Future<void> toggle(String method) async {
    final choices = [...widget.controller.quickLog];
    if (choices.contains(method)) {
      if (choices.length == 1) return;
      choices.remove(method);
    } else {
      if (choices.length == maxQuickLogItems) return;
      choices.add(method);
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.setQuickLog(choices);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save quick log. Try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> setElapsedIcons(bool value) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.setShowElapsedInIcons(value);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save icon preference. Try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final selected = widget.controller.quickLog;
    final rows = [
      ...selected,
      '', // The divider between selected and available activities.
      ...availableOrder.where((method) => !selected.contains(method)),
    ];
    if (oldIndex == selected.length) return;
    final method = rows.removeAt(oldIndex);
    final insertion = newIndex > oldIndex ? newIndex - 1 : newIndex;
    rows.insert(insertion, method);
    final divider = rows.indexOf('');
    final choices = rows.take(divider).toList();
    if (choices.isEmpty || choices.length > maxQuickLogItems) return;
    availableOrder = [...rows.skip(divider + 1), ...choices];
    if (listEquals(choices, selected)) {
      setState(() {});
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.setQuickLog(choices);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save quick log order. Try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: logPageAppBar(context, 'Customize quick log'),
    body: LogPageFrame(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final selected = widget.controller.quickLog;
          final available = availableOrder
              .where((method) => !selected.contains(method))
              .toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  SwitchListTile.adaptive(
                    key: const ValueKey('show-elapsed-in-icons'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show time since last activity'),
                    value: widget.controller.showElapsedInIcons,
                    onChanged: saving ? null : setElapsedIcons,
                  ),
                  const SizedBox(height: LogSpacing.field),
                  SectionHeading(
                    title: 'In your quick log',
                    trailing: selected.length == maxQuickLogItems
                        ? const Text('Max 6')
                        : null,
                  ),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: selected.length + available.length + 1,
                    onReorderItem: saving ? (_, _) {} : reorder,
                    itemBuilder: (context, index) {
                      if (index == selected.length) {
                        return Padding(
                          key: const ValueKey('quick-log-divider'),
                          padding: const EdgeInsets.only(
                            top: LogSpacing.section,
                          ),
                          child: const SectionHeading(title: 'Add an activity'),
                        );
                      }
                      final isSelected = index < selected.length;
                      final method = isSelected
                          ? selected[index]
                          : available[index - selected.length - 1];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        horizontalTitleGap: LogSpacing.content,
                        key: ValueKey(
                          isSelected
                              ? 'quick-log-selected-$method'
                              : 'quick-log-add-$method',
                        ),
                        leading: ActivityBadge(method: method),
                        title: Text(quickLogActivities[method]!),
                        trailing: ReorderableDragStartListener(
                          key: ValueKey('quick-log-move-$method'),
                          index: index,
                          enabled: !saving,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                        enabled:
                            !saving &&
                            (isSelected
                                ? selected.length > 1
                                : selected.length < maxQuickLogItems),
                        onTap: () => toggle(method),
                      );
                    },
                  ),
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
          );
        },
      ),
    ),
  );
}
