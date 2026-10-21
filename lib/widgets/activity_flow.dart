import 'activity_glyph.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../activity_details.dart';
import '../controller.dart';
import '../design.dart';
import '../models.dart';
import 'activity_panel.dart';
import 'care_entry_form.dart';
import 'confirm_removal.dart';

const activityCatalog = {
  'bottle': 'Bottle',
  'nursing': 'Nursing',
  'diaper': 'Diaper',
  ...activityNames,
};

Future<void> openActivity(
  BuildContext context,
  AppController c,
  String method,
) async {
  final timed = ['nursing', 'sleep', 'pumping'].contains(method);
  final manual = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => timed
        ? TimedActivityFlow(controller: c, method: method)
        : _manual(c, method),
  );
  if (manual == true && context.mounted) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _manual(c, method),
    );
  }
}

/// Launcher actions start durable timers and open their existing controls.
/// An already-running activity is opened without restarting or switching sides.
Future<void> openHomeQuickAction(
  BuildContext context,
  AppController c,
  String action,
) async {
  final method = action.startsWith('nursing') ? 'nursing' : action;
  if (method == 'nursing' && c.nursing == null) {
    try {
      await c.nursingAction(action == 'nursing_left' ? 'left' : 'right');
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppController.friendlyError(error))),
        );
      }
      return;
    }
  } else if (method == 'sleep' &&
      !c.timers.any((timer) => timer.method == method)) {
    try {
      await c.startActivityTimer(method);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppController.friendlyError(error))),
        );
      }
      return;
    }
  }
  if (context.mounted) unawaited(openActivity(context, c, method));
}

Widget _manual(AppController c, String method) => switch (method) {
  'bottle' => BottleEntryForm(controller: c),
  'diaper' => DiaperEntryForm(controller: c),
  'nursing' => NursingEntryForm(controller: c),
  _ => ActivityForm(controller: c, method: method),
};

/// Nursing and pumping pause before finishing; sleep finishes directly.
class TimedActivityFlow extends StatefulWidget {
  const TimedActivityFlow({
    super.key,
    required this.controller,
    required this.method,
  });
  final AppController controller;
  final String method;
  @override
  State<TimedActivityFlow> createState() => _TimedActivityFlowState();
}

class _TimedActivityFlowState extends State<TimedActivityFlow> {
  Timer? ticker;
  final note = TextEditingController();
  late final String familyId, babyName;
  bool saving = false;
  String? error;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    familyId = c.family!.id;
    babyName = c.family!.babyName;
    note.text = c.nursing?.note ?? '';
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    note.dispose();
    super.dispose();
  }

  Future<void> change(String action, {String? side}) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (c.family?.id != familyId) {
        throw StateError('The selected baby has changed. Reopen the activity.');
      }
      final session = widget.method == 'nursing' ? c.nursing : null;
      final timer = c.timers
          .where((t) => t.method == widget.method)
          .firstOrNull;
      if (action == 'start' || side != null) {
        if (widget.method == 'nursing') {
          await c.nursingAction(side ?? 'left', rethrowErrors: true);
        } else {
          await c.startActivityTimer(widget.method);
        }
      } else if (action == 'finish' && session != null) {
        await c.saveReviewedNursing(
          session: session,
          endedAt: session.segmentAt,
          note: note.text,
        );
      } else {
        await c.performLiveTimerAction(
          sessionId: session?.id ?? timer!.id,
          familyId: familyId,
          method: widget.method,
          action: action,
          at: DateTime.now(),
          expectedRevision: session?.revision ?? timer!.revision,
        );
      }
      if (!mounted) return;
      if (action == 'finish' && widget.method != 'pumping') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${activityCatalog[widget.method]} saved')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = AppController.friendlyError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> discard() async {
    final session = widget.method == 'nursing' ? c.nursing : null;
    final timer = c.timers.where((t) => t.method == widget.method).firstOrNull;
    if (saving || (session == null && timer == null)) return;
    final confirmed = await confirmRemoval(
      context,
      title: 'Discard ${widget.method} session?',
      message:
          'This session will be removed without saving it to your history.',
      confirmLabel: 'Discard session',
      cancelLabel: 'Keep session',
    );
    if (!confirmed || !mounted) return;
    setState(() => saving = true);
    try {
      if (session != null) {
        await c.discardNursingSession(session);
      } else {
        await c.discardActivityTimer(timer!);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = AppController.friendlyError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final session = widget.method == 'nursing' ? c.nursing : null;
      final timer = c.timers
          .where((t) => t.method == widget.method)
          .firstOrNull;
      final started = session?.startedAt ?? timer?.startedAt;
      final paused = session?.paused ?? timer?.paused ?? false;
      final busy = saving || c.recording || c.working;
      if (timer?.phase == 'review') {
        return ActivityForm(
          controller: c,
          method: widget.method,
          timer: timer,
          finishedAt: timer!.stoppedAt,
          onSaved: () {
            if (mounted) Navigator.pop(context);
          },
          onDiscarded: () {
            if (mounted) Navigator.pop(context);
          },
        );
      }
      final now = DateTime.now();
      final elapsed = session != null
          ? Duration(
              seconds:
                  session.secondsFor('left', now) +
                  session.secondsFor('right', now),
            )
          : timer?.elapsedAt(now) ?? Duration.zero;
      return EntrySheet(
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (started == null) ...[
              if (widget.method == 'nursing')
                for (final side in ['left', 'right'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton(
                      onPressed: busy
                          ? null
                          : () => change('start', side: side),
                      child: Text('Start $side'),
                    ),
                  )
              else
                FilledButton(
                  onPressed: busy ? null : () => change('start'),
                  child: Text('Start ${widget.method}'),
                ),
              const SizedBox(height: LogSpacing.label),
              OutlinedButton(
                onPressed: busy ? null : () => Navigator.pop(context, true),
                child: const Text('Enter manually'),
              ),
            ] else ...[
              if (widget.method == 'sleep')
                FilledButton(
                  onPressed: busy ? null : () => change('finish'),
                  child: const Text('Finish sleep'),
                )
              else if (paused) ...[
                FilledButton(
                  onPressed: busy ? null : () => change('finish'),
                  child: Text(saving ? 'Saving…' : 'Finish ${widget.method}'),
                ),
                const SizedBox(height: LogSpacing.label),
                OutlinedButton(
                  onPressed: busy ? null : () => change('resume'),
                  child: Text('Resume ${widget.method}'),
                ),
              ] else
                FilledButton(
                  onPressed: busy ? null : () => change('pause'),
                  child: Text('Pause ${widget.method}'),
                ),
              TextButton(
                onPressed: busy ? null : discard,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Discard session'),
              ),
            ],
          ],
        ),
        children: [
          FormHeading(
            method: widget.method,
            title: activityCatalog[widget.method]!,
            subtitle: babyName,
            enabled: !busy,
          ),
          if (started == null) ...[
            CareGlyph(
              method: widget.method,
              fallback: activityIcon(widget.method),
              size: 42,
              color: activityAccent(widget.method, context: context),
            ),
            const SizedBox(height: LogSpacing.section),
            Text(
              'Timers continue when the app is closed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: logPalette(context).secondary,
                height: 1.5,
              ),
            ),
          ] else ...[
            Text(
              paused
                  ? session != null
                        ? 'Paused · ${session.side == 'left' ? 'Left' : 'Right'} side'
                        : 'Paused'
                  : session != null
                  ? '${session.side == 'left' ? 'Left' : 'Right'} side running'
                  : 'Timer running',
              style: TextStyle(color: logPalette(context).secondary),
            ),
            Text(
              sessionDuration(elapsed),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w600,
                color: logPalette(context).ink,
              ),
            ),
            if (session != null) ...[
              const SizedBox(height: LogSpacing.content),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  for (final side in ['left', 'right'])
                    Text(
                      '${side == 'left' ? 'Left' : 'Right'} · ${sessionDuration(Duration(seconds: session.secondsFor(side, now)))}',
                      style: const TextStyle(fontSize: 18),
                    ),
                ],
              ),
              const SizedBox(height: LogSpacing.content),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => change(
                        'start',
                        side: session.side == 'left' ? 'right' : 'left',
                      ),
                child: Text(
                  '${paused ? 'Start' : 'Switch to'} ${session.side == 'left' ? 'right' : 'left'}',
                ),
              ),
              TextField(
                controller: note,
                enabled: !busy,
                maxLength: 2000,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: LogSpacing.field),
            EntryTime(label: 'Started', value: started),
          ],
          if (error ?? c.message case final String message)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    },
  );
}

class ActiveSessions extends StatefulWidget {
  const ActiveSessions({super.key, required this.controller});
  final AppController controller;
  @override
  State<ActiveSessions> createState() => _ActiveSessionsState();
}

class _ActiveSessionsState extends State<ActiveSessions> {
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  bool changing = false;
  Future<void> act(
    String familyId,
    String id,
    String method,
    int revision,
    String action,
  ) async {
    if (changing) return;
    setState(() => changing = true);
    final c = widget.controller;
    try {
      final accepted = await c.performLiveTimerAction(
        sessionId: id,
        familyId: familyId,
        method: method,
        action: action,
        at: DateTime.now(),
        expectedRevision: revision,
      );
      if (!mounted || !accepted) return;
      if (method == 'pumping' && ['finish', 'review'].contains(action)) {
        await openActivity(context, c, method);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppController.friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  Widget sessionTile({
    required String familyId,
    required String id,
    required String method,
    required String detail,
    required String phase,
    required int revision,
  }) {
    final c = widget.controller;
    final actions = phase == 'review'
        ? ['review']
        : phase == 'paused'
        ? ['resume', 'finish']
        : method == 'sleep'
        ? ['finish']
        : method == 'nursing'
        ? ['switch', 'pause']
        : ['pause'];
    final controls = Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      children: [
        for (final action in actions)
          Semantics(
            label:
                '${action == 'review'
                    ? 'Enter amount for'
                    : action == 'switch'
                    ? 'Switch sides for'
                    : action} $method',
            child: TextButton(
              key: ValueKey('$action-live-$method'),
              onPressed: changing || c.recording || c.working
                  ? null
                  : () => act(familyId, id, method, revision, action),
              child: Text(switch (action) {
                'review' => 'Add amount',
                'switch' => 'Switch sides',
                'pause' => 'Pause',
                'resume' => 'Resume',
                _ => 'Finish',
              }),
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < (method == 'nursing' ? 420 : 300) ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ActivityBadge(method: method),
              title: Text(activityCatalog[method]!),
              subtitle: Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: stacked ? null : controls,
              onTap: changing ? null : () => openActivity(context, c, method),
            ),
            if (stacked)
              Align(alignment: Alignment.centerRight, child: controls),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final nursing = c.nursing;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (nursing != null)
          sessionTile(
            familyId: nursing.familyId,
            id: nursing.id,
            method: 'nursing',
            phase: nursing.paused ? 'paused' : 'running',
            revision: nursing.revision,
            detail:
                '${sessionDuration(Duration(seconds: nursing.secondsFor('left', now) + nursing.secondsFor('right', now)))} · ${nursing.paused ? 'paused' : '${nursing.side == 'left' ? 'Left' : 'Right'} side running'}',
          ),
        for (final timer in c.timers)
          sessionTile(
            familyId: timer.familyId,
            id: timer.id,
            method: timer.method,
            phase: timer.phase,
            revision: timer.revision,
            detail:
                '${sessionDuration(timer.elapsedAt(now))} · ${timer.phase == 'running'
                    ? 'timer running'
                    : timer.phase == 'paused'
                    ? 'paused'
                    : 'add amount'}',
          ),
        const SizedBox(height: LogSpacing.content),
      ],
    );
  }
}

Future<void> editActivity(
  BuildContext context,
  AppController c,
  Feeding record,
) async {
  final resumeSide = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => switch (record.method) {
      'bottle' => BottleEntryForm(controller: c, original: record),
      'nursing' => NursingEntryForm(
        controller: c,
        original: record,
        onResume: (side) => Navigator.pop(sheetContext, side),
      ),
      'diaper' => DiaperEntryForm(controller: c, original: record),
      _ => ActivityForm(controller: c, method: record.method, original: record),
    },
  );
  if (resumeSide != null && context.mounted) {
    try {
      await c.reopenNursing(record, resumeSide);
      if (context.mounted) await openActivity(context, c, 'nursing');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppController.friendlyError(e))));
      }
    }
  }
}
