import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../design.dart';
import '../controller.dart';
import '../models.dart';
import '../services/history_import.dart';
import '../services/import_file.dart';
import '../services/import_issue.dart';
import 'confirm_removal.dart';
import 'toggle_pill.dart';

ImportPlan _previewFile((String, Family, List<Feeding>, bool, bool) request) =>
    HistoryImport.preview(
      request.$1,
      request.$2,
      request.$3,
      includeUnassignedPumps: request.$4,
      allowPartial: request.$5,
    );

class ImportPage extends StatefulWidget {
  const ImportPage({
    super.key,
    required this.controller,
    this.pickFile = ImportFile.choose,
  });
  final AppController controller;
  final Future<ImportFile?> Function() pickFile;
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final Family family;
  ImportFile? file;
  ImportPlan? plan;
  bool busy = false, canUndo = false, includeUnassignedPumps = false;
  bool allowPartial = false;
  int naraCount = 0;
  List<Map<String, Object?>> reports = [];
  String? message;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    family = widget.controller.family!;
    loadRecovery();
  }

  Future<void> loadRecovery() async {
    try {
      final repo = widget.controller.repository;
      final available = await repo.canUndoImport(family.id);
      final history = await repo.importReports(family.id);
      final records = await repo.feeds(family.id);
      if (mounted) {
        setState(() {
          canUndo = available;
          reports = history;
          naraCount = records
              .where((r) => r.source['system'] == 'Nara Baby')
              .length;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          message = AppController.friendlyError(e);
        });
      }
    }
  }

  void checkFamily() {
    if (widget.controller.family?.id != family.id) {
      throw StateError(
        'The selected baby has changed. Reopen Import and recovery.',
      );
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
      failed = false;
    });
    try {
      checkFamily();
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          plan = null;
          failed = true;
          message = AppController.friendlyError(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> buildPreview() async {
    final selected = file!;
    final existing = await widget.controller.repository.feeds(
      family.id,
      includeDeleted: true,
    );
    checkFamily();
    final target = family;
    final next = await compute(_previewFile, (
      selected.contents,
      target,
      existing,
      includeUnassignedPumps,
      allowPartial,
    ));
    if (!mounted) return;
    checkFamily();
    setState(() => plan = next);
  }

  Future<void> chooseFile() => run(() async {
    final selected = await widget.pickFile();
    if (!mounted || selected == null) return;
    checkFamily();
    setState(() {
      file = selected;
      plan = null;
      includeUnassignedPumps = false;
      allowPartial = false;
    });
    await buildPreview();
  });

  String get syncRemovalScope => family.isLocal
      ? 'Changes apply to this device.'
      : 'Changes also apply to the shared log when it syncs.';

  Future<void> importEntries() => run(() async {
    final current = plan!;
    final deletes = current.additions.where((f) => f.deleted).length;
    if (current.removals.isNotEmpty || deletes > 0) {
      final confirmed = await confirmRemoval(
        context,
        title: 'Import changes to history?',
        message:
            'This import deletes or replaces ${current.removals.length + deletes} entries. $syncRemovalScope You can undo this import.',
        confirmLabel: 'Import changes',
      );
      if (!confirmed || !mounted) return;
    }
    checkFamily();
    await widget.controller.repository.applyImport(current);
    // The transaction is committed. Clear the preview before refresh/sync so
    // later failures cannot invite a second save or imply the import was lost.
    if (mounted) {
      setState(() {
        plan = null;
        file = null;
        canUndo = true;
        message = 'Import saved on this device.';
      });
    }
    await widget.controller.refresh();
    await widget.controller.sync();
    await loadRecovery();
  });

  bool get undoIsRemoval =>
      reports.isNotEmpty &&
      reports.first['label'] == 'Remove Nara Baby imports';

  Future<void> undoImport() => run(() async {
    final restoring = undoIsRemoval;
    final confirmed = await confirmRemoval(
      context,
      title: restoring ? 'Undo removal?' : 'Undo last import?',
      message: restoring
          ? 'Restore the removed Nara Baby entries? $syncRemovalScope'
          : 'Removes entries from the last import and restores entries it replaced. $syncRemovalScope',
      confirmLabel: restoring ? 'Restore imports' : 'Undo import',
      cancelLabel: restoring ? 'Keep removed' : 'Keep import',
    );
    if (!confirmed || !mounted) return;
    checkFamily();
    await widget.controller.repository.undoImport(family.id);
    if (mounted) {
      setState(() {
        plan = null;
        canUndo = false;
        message = restoring ? 'Nara Baby imports restored.' : 'Import undone.';
      });
    }
    await widget.controller.refresh();
    await widget.controller.sync();
    await loadRecovery();
  });

  Future<void> removeNaraImports() => run(() async {
    final before = await widget.controller.repository.feeds(
      family.id,
      includeDeleted: true,
    );
    final imported = before
        .where((r) => !r.deleted && r.source['system'] == 'Nara Baby')
        .toList();
    if (!mounted || imported.isEmpty) return;
    final confirmed = await confirmRemoval(
      context,
      title: 'Remove Nara Baby imports?',
      message:
          'Remove ${imported.length} Nara Baby entries, including any edits to them? $syncRemovalScope You can undo this removal.',
      confirmLabel: 'Remove imports',
    );
    if (!confirmed || !mounted) return;
    checkFamily();
    await widget.controller.repository.applyImport(
      ImportPlan(
        familyId: family.id,
        before: before,
        additions: [],
        removals: imported,
        duplicates: 0,
        label: 'Remove Nara Baby imports',
      ),
    );
    if (mounted) {
      setState(() {
        plan = null;
        canUndo = true;
        message = 'Nara Baby imports removed.';
      });
    }
    await widget.controller.refresh();
    await widget.controller.sync();
    await loadRecovery();
  });

  Widget issueList(List<ImportIssue> issues) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(
      '${issues.length} ${issues.length == 1 ? 'entry' : 'entries'} not imported',
    ),
    children: [
      for (final issue in issues)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Row ${issue.row} · ${issue.type}'),
          subtitle: Text(
            [
              if (issue.time.isNotEmpty) issue.time,
              issue.reason,
              'ID: ${issue.recordId}',
            ].join('\n'),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final preview = plan;
    final activities =
        preview?.additions
            .where((f) => f.method != 'profile' && !f.deleted)
            .toList() ??
        <Feeding>[];
    final counts = <String, int>{};
    const labels = {
      'bottle': 'Bottles',
      'nursing': 'Nursing',
      'diaper': 'Diapers',
      'sleep': 'Sleep',
      'pumping': 'Pumping',
      'solids': 'Solids',
      'growth': 'Growth',
      'health': 'Health',
      'routine': 'Routines',
      'milestone': 'Milestones',
    };
    for (final entry in activities) {
      counts.update(
        labels[entry.method] ?? entry.method,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    final dates = activities.map((f) => f.at).toList()..sort();
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: logPageAppBar(context, 'Import and recovery'),
        body: LogPageFrame(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Import for ${family.babyName}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: LogSpacing.label),
                const Text('Choose a Nara Baby export or Little Log backup.'),
                const SizedBox(height: LogSpacing.section),
                OutlinedButton.icon(
                  onPressed: busy ? null : chooseFile,
                  icon: const Icon(Icons.folder_open),
                  label: Text(file == null ? 'Choose file' : 'Change file'),
                ),
                if (file != null) ...[
                  const SizedBox(height: LogSpacing.content),
                  Text(
                    file!.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
                if (busy) ...[
                  const SizedBox(height: LogSpacing.field),
                  const LinearProgressIndicator(
                    semanticsLabel: 'Processing import',
                  ),
                ],
                if (preview != null) ...[
                  const SizedBox(height: LogSpacing.section),
                  Text(
                    'Review import',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: LogSpacing.content),
                  if (preview.unassignedPumps > 0) ...[
                    BooleanSelection(
                      label:
                          'Include ${preview.unassignedPumps} unassigned pumping ${preview.unassignedPumps == 1 ? 'record' : 'records'}',
                      value: includeUnassignedPumps,
                      onChanged: busy
                          ? null
                          : (value) {
                              setState(() => includeUnassignedPumps = value);
                              run(buildPreview);
                            },
                    ),
                    const SizedBox(height: LogSpacing.content),
                  ],
                  if (preview.issues.isNotEmpty) issueList(preview.issues),
                  if (preview.issues.any((i) => i.requiresConsent))
                    BooleanSelection(
                      label: 'Import supported entries only',
                      value: allowPartial,
                      onChanged: busy
                          ? null
                          : (value) {
                              setState(() => allowPartial = value);
                              run(buildPreview);
                            },
                    ),
                  if (dates.isNotEmpty)
                    Text(
                      '${DateFormat.yMMMd().format(dates.first.toLocal())} – ${DateFormat.yMMMd().format(dates.last.toLocal())}',
                    ),
                  for (final entry in counts.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: LogSpacing.label),
                      child: Row(
                        children: [
                          Expanded(child: Text(entry.key)),
                          Text('${entry.value}'),
                        ],
                      ),
                    ),
                  if (preview.additions.any((f) => f.method == 'profile')) ...[
                    const SizedBox(height: LogSpacing.label),
                    const Text('Baby profile included'),
                  ],
                  if (preview.duplicates > 0) ...[
                    const SizedBox(height: LogSpacing.content),
                    Text('${preview.duplicates} already imported'),
                  ],
                  if (preview.additions.isEmpty &&
                      preview.removals.isEmpty) ...[
                    const SizedBox(height: LogSpacing.content),
                    const Text('No new entries to import.'),
                  ] else ...[
                    const SizedBox(height: LogSpacing.field),
                    FilledButton(
                      onPressed: busy || preview.needsConsent
                          ? null
                          : importEntries,
                      child: const Text('Import these entries'),
                    ),
                  ],
                ],
                if (message != null) ...[
                  const SizedBox(height: LogSpacing.field),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      message!,
                      style: TextStyle(
                        color: failed
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ),
                ],
                if (failed && file != null) ...[
                  const SizedBox(height: LogSpacing.content),
                  TextButton(
                    onPressed: busy ? null : () => run(buildPreview),
                    child: const Text('Retry preview'),
                  ),
                ],
                if (naraCount > 0) ...[
                  const SizedBox(height: LogSpacing.section),
                  OutlinedButton(
                    onPressed: busy ? null : removeNaraImports,
                    child: const Text('Remove Nara Baby imports'),
                  ),
                ],
                if (reports.isNotEmpty) ...[
                  const SizedBox(height: LogSpacing.section),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Import history'),
                    children: [
                      for (final report in reports)
                        ExpansionTile(
                          title: Text(
                            '${report['label']}${report['undone'] == true ? ' · Undone' : ''}',
                          ),
                          subtitle: Text(
                            DateFormat.yMMMd().add_jm().format(
                              DateTime.parse(
                                report['createdAt'] as String,
                              ).toLocal(),
                            ),
                          ),
                          children: [
                            Text(
                              '${report['added']} activities added · ${report['duplicates']} duplicates skipped · ${report['removed']} removed',
                            ),
                            if ((report['issues'] as List).isNotEmpty)
                              issueList(
                                (report['issues'] as List)
                                    .map(
                                      (r) => ImportIssue.fromJson(
                                        Map<String, Object?>.from(r as Map),
                                      ),
                                    )
                                    .toList(),
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
                if (canUndo) ...[
                  const SizedBox(height: LogSpacing.section),
                  OutlinedButton(
                    onPressed: busy ? null : undoImport,
                    child: Text(
                      reports.isNotEmpty &&
                              reports.first['label'] ==
                                  'Remove Nara Baby imports'
                          ? 'Undo removal'
                          : 'Undo last import',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
