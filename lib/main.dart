import 'widgets/care_entry_form.dart';
import 'services/assistant_actions.dart';
import 'services/assistant_history.dart';
import 'services/home_quick_actions.dart';
import 'widgets/appearance_page.dart';
import 'widgets/tip_jar_page.dart';
import 'services/tip_jar.dart';
import 'widgets/log_header.dart';
import 'widgets/baby_picker.dart';
import 'volume.dart';
import 'widgets/settings_page.dart';
import 'widgets/profile_page.dart';
import 'widgets/import_page.dart';
import 'widgets/quick_log_settings_page.dart';
import 'widgets/activity_launch_icon.dart';
import 'widgets/elapsed_activity_glyph.dart' show elapsedIconActivities;
import 'widgets/assistant_help_page.dart';
import 'widgets/summary_settings_page.dart';
import 'widgets/log_day_picker.dart';
import 'quick_log.dart';
import 'widgets/activity_flow.dart';
import 'design.dart';
import 'activity_details.dart';
import 'widgets/activity_panel.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'controller.dart';
import 'services/google_auth.dart';
import 'services/google_drive.dart';
import 'services/invitation_link.dart';
import 'services/invitation_link_bridge.dart';
import 'storage/open_database.dart';
import 'storage/repository.dart';
import 'widgets/google_button.dart';
import 'widgets/onboarding.dart';
import 'widgets/invite_caregiver.dart';
import 'widgets/monthly_probe_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (TipJar.supported) TipJar.shared.start();
  try {
    final repo = Repository(await openLocalDatabase());
    final auth = GoogleAuth();
    final controller = AppController(repo, auth, GoogleDrive(auth));
    runApp(LittleLogApp(controller: controller));
    unawaited(controller.initialize());
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Little Log could not open local storage. '
                'Allow storage for this app and reopen it. Existing records have not been removed.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const ink = logActionInk;
const paper = logBackground;
const mint = logActionTint;

class LittleLogApp extends StatefulWidget {
  const LittleLogApp({super.key, required this.controller});
  final AppController controller;
  @override
  State<LittleLogApp> createState() => _LittleLogAppState();
}

class _LittleLogAppState extends State<LittleLogApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _invitationBridge = InvitationLinkBridge();
  final _assistantActions = AssistantActions();
  String? _activeInvitationFile;
  bool _openingPumpingReview = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_reviewStoppedPumping);
    unawaited(_invitationBridge.listen(_openInvitation));
    unawaited(_assistantActions.listen(_executeAssistantRequest));
  }

  void _reviewStoppedPumping() {
    final c = widget.controller;
    if (c.loading || c.pendingPumpingReview == null || _openingPumpingReview) {
      return;
    }
    _openingPumpingReview = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final request = c.pendingPumpingReview;
        c.pendingPumpingReview = null;
        if (!mounted || request == null) return;
        final baby = c.families
            .where((baby) => baby.id == request.familyId)
            .firstOrNull;
        if (baby == null) return;
        if (c.family?.id != baby.id) await c.select(baby);
        final context = _navigatorKey.currentState?.overlay?.context;
        if (!mounted ||
            context == null ||
            !context.mounted ||
            !c.timers.any(
              (timer) =>
                  timer.id == request.sessionId && timer.stoppedAt != null,
            )) {
          return;
        }
        await openActivity(context, c, 'pumping');
      } finally {
        _openingPumpingReview = false;
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<String> _executeAssistantRequest(AssistantRequest request) async {
    final c = widget.controller;
    final message = await executeAssistantRequest(c, request);
    if (!mounted) return message;
    if (assistantHistoryQuestions.containsKey(request.action)) {
      final familyId = c.family?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _navigatorKey.currentState?.overlay?.context;
        if (!mounted || context == null || c.family?.id != familyId) return;
        unawaited(
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(assistantHistoryQuestions[request.action]!),
              content: SingleChildScrollView(child: SelectableText(message)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        );
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    if ([
      'open_diaper',
      'open_nursing',
      'review_pumping',
    ].contains(request.action)) {
      final familyId = c.family?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _navigatorKey.currentState?.overlay?.context;
        if (!mounted || context == null || familyId != c.family?.id) return;
        final timer = c.timers.where((t) => t.method == 'pumping').firstOrNull;
        if (request.action == 'review_pumping' && timer == null) return;
        unawaited(
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => switch (request.action) {
              'open_diaper' => DiaperEntryForm(controller: c),
              'open_nursing' => TimedActivityFlow(
                controller: c,
                method: 'nursing',
              ),
              _ => ActivityForm(
                controller: c,
                method: 'pumping',
                timer: timer,
                finishedAt: timer?.stoppedAt ?? request.at,
              ),
            },
          ),
        );
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    return message;
  }

  void _openInvitation(InvitationLink invitation) {
    if (!mounted || _activeInvitationFile == invitation.fileId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      _activeInvitationFile = invitation.fileId;
      navigator
          .push(
            MaterialPageRoute<bool>(
              builder: (_) => OnboardingPage(
                controller: widget.controller,
                initialStage: OnboardingStage.join,
                invitation: invitation,
              ),
            ),
          )
          .whenComplete(() => _activeInvitationFile = null);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed && TipJar.supported) {
      unawaited(TipJar.shared.recover());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reviewStoppedPumping);
    WidgetsBinding.instance.removeObserver(this);
    _invitationBridge.dispose();
    _assistantActions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final babyId = widget.controller.family?.id;
      final background = babyId == null
          ? paper
          : babyBackgrounds[widget.controller.backgroundChoice(babyId)]!.color;
      return MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Little Log',
        debugShowCheckedModeBanner: false,
        themeMode: widget.controller.themeMode,
        theme: littleLogTheme(background: background),
        darkTheme: littleLogTheme(
          brightness: Brightness.dark,
          background: darkBabyBackground(
            widget.controller.backgroundChoice(babyId ?? ''),
          ),
        ),
        home: HomePage(controller: widget.controller),
      );
    },
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final logScroll = ScrollController();
  final _quickActions = HomeQuickActions();
  String? _pendingQuickAction;
  bool _openingQuickAction = false;

  void _receiveQuickAction(String action) {
    _pendingQuickAction = action;
    _tryQuickAction();
  }

  void _tryQuickAction() {
    if (!mounted ||
        _pendingQuickAction == null ||
        _openingQuickAction ||
        c.loading ||
        c.family == null ||
        c.onboardingSyncedSetup ||
        c.joiningFromOnboarding ||
        c.recording ||
        c.working ||
        c.switchingBaby) {
      return;
    }
    _openingQuickAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        final action = _pendingQuickAction!;
        _pendingQuickAction = null;
        Navigator.of(context).popUntil((route) => route.isFirst);
        setState(() {
          tab = 0;
          selectedDay = DateUtils.dateOnly(DateTime.now());
          viewAll = false;
          activityFilter = 'all';
        });
        await openHomeQuickAction(context, c, action);
      } finally {
        _openingQuickAction = false;
        _tryQuickAction();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    c.removeListener(_tryQuickAction);
    _quickActions.dispose();
    logScroll.dispose();
    super.dispose();
  }

  int tab = 0;
  DateTime selectedDay = DateUtils.dateOnly(DateTime.now());
  bool viewAll = false;
  String activityFilter = 'all';
  bool get isToday => DateUtils.isSameDay(selectedDay, DateTime.now());

  Future<void> pickDay() async {
    final chosen = await showLogDayPicker(
      context: context,
      initialDay: selectedDay,
    );
    if (chosen != null && mounted) {
      setState(() {
        if (logScroll.hasClients) logScroll.jumpTo(0);
        selectedDay = chosen;
        viewAll = false;
        activityFilter = 'all';
      });
    }
  }

  final visited = <int>{0};
  @override
  void initState() {
    super.initState();
    c.enterActivityVisit();
    c.addListener(_tryQuickAction);
    unawaited(_quickActions.listen(_receiveQuickAction));
  }

  void selectTab(int value) => setState(() {
    if (tab != value && value == 0) c.enterActivityVisit();
    tab = value;
    visited.add(value);
  });
  AppController get c => widget.controller;
  Future<void> log(String method) => openActivity(context, c, method);

  void customizeQuickLog() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => QuickLogSettingsPage(controller: c),
    ),
  );

  Future<void> allActivities() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FormHeading(title: 'Log an activity'),
            for (final entry in activityCatalog.entries)
              ListTile(
                key: ValueKey('activity-picker-${entry.key}'),
                contentPadding: EdgeInsets.zero,
                leading: ActivityBadge(method: entry.key),
                title: Text(entry.value),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (choice != null && mounted) await log(choice);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (c.loading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (c.family == null ||
          c.onboardingSyncedSetup ||
          c.joiningFromOnboarding) {
        return OnboardingPage(controller: c);
      }
      if (c.onboardingInvitePending) {
        c.onboardingInvitePending = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            showDialog<void>(
              context: context,
              builder: (_) => _FirstInvite(controller: c),
            );
          }
        });
      }
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 24 + MediaQuery.textScalerOf(context).scale(26) * 1.2,
          centerTitle: false,
          titleSpacing: 20,
          title: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: LogHeader(
                controller: c,
                day: selectedDay,
                onChooseDay: tab == 0 ? pickDay : null,
              ),
            ),
          ),
        ),
        body: AbsorbPointer(
          absorbing: c.switchingBaby,
          child: IndexedStack(
            index: tab,
            children: [
              today(),
              visited.contains(1)
                  ? SafeArea(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: FamilyPanel(
                            key: ValueKey(c.family!.id),
                            controller: c,
                            embedded: true,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: 'Log',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      );
    },
  );
  Widget today() {
    const cardPadding = EdgeInsets.all(LogSpacing.content);
    const cardRadius = BorderRadius.all(Radius.circular(18));
    final day = DaySummary(c.feeds, selectedDay);
    final values = <String, String>{
      'Nursing': historyDuration(day.nursingSeconds),
      'Bottle': volumeLabel(day.bottleMl, unit: c.volumeUnit),
      'Diapers': '${day.diapers}',
      'Sleep': historyDuration(day.sleepSeconds),
      'Pumped': volumeLabel(day.pumpedMl, unit: c.volumeUnit),
    };
    final metrics = [
      for (final label in c.summaryMetrics) (values[label]!, label),
    ];
    final sorted =
        c.feeds
            .where(
              (record) =>
                  DateUtils.isSameDay(record.at.toLocal(), selectedDay) &&
                  (activityFilter == 'all' || record.method == activityFilter),
            )
            .toList()
          ..sort(newestRecordFirst);
    final latest = latestActivityIds(c.feeds);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await c.sync(manual: true);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                c.message ??
                    (c.canSync && c.pendingCount == 0
                        ? 'All entries saved to Google Drive.'
                        : 'Entries are saved on this device.'),
              ),
            ),
          );
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              key: const PageStorageKey('today'),
              controller: logScroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                if (!isToday)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() {
                        selectedDay = DateUtils.dateOnly(DateTime.now());
                        viewAll = false;
                        activityFilter = 'all';
                      }),
                      child: const Text('Back to today'),
                    ),
                  ),
                if (c.driveFileUnavailable) ...[
                  const SizedBox(height: LogSpacing.field),
                  _DriveUnavailableNotice(controller: c),
                ],
                if (c.nursing != null || c.timers.isNotEmpty) ...[
                  const SizedBox(height: LogSpacing.field),
                  ActiveSessions(controller: c),
                ],
                SectionHeading(
                  key: const ValueKey('quick-log-heading'),
                  compact: true,
                  title: 'Quick log',
                  action: 'Customize',
                  onAction: customizeQuickLog,
                ),
                LayoutBuilder(
                  builder: (context, size) {
                    final halfWidth = (size.maxWidth - 12) / 2;
                    final elapsedMode = c.showElapsedInIcons;
                    var widestText = 0.0;
                    if (elapsedMode) {
                      for (final method in c.quickLog) {
                        final texts = [
                          (
                            quickLogActivities[method]!,
                            Theme.of(context).textTheme.labelLarge!,
                          ),
                          if (elapsedIconActivities.contains(method))
                            (
                              QuickLogElapsedTime.textFor(
                                c.timeSinceLastActivity(method),
                              ),
                              QuickLogElapsedTime.textStyle(context, method),
                            ),
                        ];
                        for (final (text, style) in texts) {
                          final painter = TextPainter(
                            text: TextSpan(text: text, style: style),
                            textDirection: Directionality.of(context),
                            textScaler: MediaQuery.textScalerOf(context),
                          )..layout();
                          if (painter.width > widestText) {
                            widestText = painter.width;
                          }
                          painter.dispose();
                        }
                      }
                    }
                    final singleColumn =
                        elapsedMode &&
                        ActivityLaunchIcon.iconSize +
                                LogSpacing.content +
                                widestText +
                                cardPadding.horizontal >
                            halfWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final method in c.quickLog)
                          SizedBox(
                            width: singleColumn ? size.maxWidth : halfWidth,
                            child: OutlinedButton(
                              key: ValueKey('quick-log-button-$method'),
                              onPressed: () => log(method),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: activityTint(
                                  method,
                                  context: context,
                                ),
                                foregroundColor: activityAccent(
                                  method,
                                  context: context,
                                ),
                                padding: cardPadding,
                                minimumSize: const Size(44, 78),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: cardRadius,
                                ),
                                side: BorderSide.none,
                              ),
                              child: elapsedMode
                                  ? Row(
                                      children: [
                                        ActivityLaunchIcon(method: method),
                                        const SizedBox(
                                          width: LogSpacing.content,
                                        ),
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                quickLogActivities[method]!,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  height: 1.2,
                                                ),
                                              ),
                                              if (elapsedIconActivities
                                                  .contains(method)) ...[
                                                const SizedBox(height: 2),
                                                QuickLogElapsedTime(
                                                  method: method,
                                                  elapsed: c
                                                      .timeSinceLastActivity(
                                                        method,
                                                      ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ActivityLaunchIcon(method: method),
                                        const SizedBox(
                                          height: LogSpacing.label,
                                        ),
                                        Text(quickLogActivities[method]!),
                                      ],
                                    ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: allActivities,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('See all activities'),
                  ),
                ),
                if (metrics.isNotEmpty) ...[
                  SectionHeading(
                    compact: true,
                    title: 'At a glance',
                    action: 'Customize',
                    onAction: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SummarySettingsPage(controller: c),
                      ),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, size) {
                      final cellWidth =
                          (size.maxWidth - 12) / 2 - cardPadding.horizontal;
                      final compact =
                          cellWidth < 130 &&
                          MediaQuery.textScalerOf(context).scale(22) >= 34;
                      final valueSize = compact
                          ? 16.0
                          : summaryValueSize(
                              context,
                              cellWidth,
                              metrics.map((m) => m.$1),
                            );
                      Widget card((String, String) metric) => Container(
                        key: ValueKey('today-metric-${metric.$2}'),
                        padding: cardPadding,
                        decoration: BoxDecoration(
                          color: logPalette(context).surface,
                          borderRadius: cardRadius,
                        ),
                        child: metric.$2 == 'Nursing'
                            ? nursingSummaryMetric(
                                day,
                                context: context,
                                cellWidth: cellWidth,
                                compact: compact,
                                valueSize: valueSize,
                              )
                            : summaryMetric(
                                metric.$1,
                                metric.$2,
                                valueSize: valueSize,
                              ),
                      );
                      return Column(
                        key: const ValueKey('today-summary'),
                        children: [
                          for (var i = 0; i < metrics.length; i += 2) ...[
                            if (i > 0)
                              const SizedBox(height: LogSpacing.content),
                            summaryRow(
                              card(metrics[i]),
                              i + 1 < metrics.length
                                  ? card(metrics[i + 1])
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: LogSpacing.content),
                SectionHeading(
                  key: const ValueKey('log-activity-heading'),
                  compact: true,
                  title: 'Activity',
                  action: viewAll ? 'Show less' : 'View all',
                  onAction: () => setState(() {
                    viewAll = !viewAll;
                    activityFilter = 'all';
                  }),
                ),
                if (viewAll) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('activity-filter-$activityFilter'),
                    initialValue: activityFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Activity'),
                    items: {'all': 'All activities', ...activityCatalog}.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => activityFilter = value!),
                  ),
                  const SizedBox(height: LogSpacing.label),
                ],
                if (sorted.isEmpty)
                  Container(
                    padding: cardPadding,
                    decoration: BoxDecoration(
                      color: logPalette(context).surface,
                      borderRadius: cardRadius,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          color: logPalette(context).secondary,
                        ),
                        SizedBox(height: LogSpacing.content),
                        Text(
                          'No entries on this day',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: logPalette(context).surface,
                      borderRadius: cardRadius,
                    ),
                    child: RecordList(
                      children: [
                        for (final record in sorted.take(
                          viewAll ? sorted.length : 5,
                        ))
                          RecordRow(
                            key: ValueKey(record.id),
                            record: record,
                            showElapsed: latest.contains(record.id),
                            swipeDemoEnabled:
                                tab == 0 &&
                                record.id == sorted.first.id &&
                                c.swipeDemoEligible,
                            onSwipeAction: c.learnSwipeActions,
                            onSwipeDemoStart: c.beginSwipeDemo,
                            onSwipeDemoEnd: c.endSwipeDemo,
                            weightUnit: c.weightUnit,
                            onDelete: () => c.deleteRecord(record),
                            onEdit: () => editActivity(context, c, record),
                            volumeUnit: c.volumeUnit,
                            local: c.family!.isLocal,
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: LogSpacing.field),
                _SyncStatus(controller: c, openFamily: () => selectTab(1)),
                if (c.message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _Notice(c.message!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FirstInvite extends StatefulWidget {
  const _FirstInvite({required this.controller});
  final AppController controller;
  @override
  State<_FirstInvite> createState() => _FirstInviteState();
}

class _FirstInviteState extends State<_FirstInvite> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Invite a caregiver'),
      content: SizedBox(
        width: 380,
        child: InviteCaregiverForm(
          controller: widget.controller,
          family: widget.controller.family!,
          onBusy: (value) => setState(() => busy = value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.controller, this.openFamily});
  final AppController controller;
  final VoidCallback? openFamily;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final local = c.family!.isLocal;
    final title = c.syncing
        ? 'Saving to Google Drive…'
        : local
        ? 'Saved on this device'
        : c.driveFileUnavailable
        ? 'Drive log unavailable · saved on this device'
        : !c.canSync
        ? 'Reconnect your baby’s Google account'
        : c.pendingCount > 0
        ? '${c.pendingCount} waiting to sync'
        : c.lastSync == null
        ? 'Ready to sync'
        : 'Synced ${DateFormat.jm().format(c.lastSync!.toLocal())}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        color: logPalette(context).actionInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    local ? Icons.phone_iphone : Icons.cloud_outlined,
                    size: 18,
                    color: logPalette(context).actionInk,
                  ),
                ],
              ),
            ),
            if (c.syncing)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (c.canSync || openFamily != null)
              TextButton(
                onPressed: local || !c.canSync
                    ? openFamily
                    : () => c.sync(manual: true),
                child: Text(
                  local
                      ? 'Share'
                      : !c.canSync
                      ? 'Connect'
                      : 'Refresh',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
        if (!local)
          Text(
            c.family!.ownerLabel,
            style: TextStyle(
              fontSize: 12,
              color: logPalette(context).secondary,
            ),
          ),
      ],
    );
  }
}

class _DriveUnavailableNotice extends StatelessWidget {
  const _DriveUnavailableNotice({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final baby = controller.family!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: logPalette(context).warningTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${baby.babyName}’s Drive log is unavailable',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'It may be in Trash, deleted, or no longer shared with you. '
            'You can keep recording; new entries stay on this device until sync works again.',
          ),
          if (controller.lastSync != null) ...[
            const SizedBox(height: 6),
            Text(
              'Last synced ${DateFormat.yMMMd().add_jm().format(controller.lastSync!.toLocal())}',
            ),
          ],
          const SizedBox(height: LogSpacing.label),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: controller.syncing
                    ? null
                    : () => controller.sync(manual: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry sync'),
              ),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://drive.google.com/file/d/${baby.driveFileId}/view',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in Google Drive'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: logPalette(context).warningTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Semantics(
      liveRegion: true,
      child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
    ),
  );
}

class FamilyPanel extends StatefulWidget {
  const FamilyPanel({
    super.key,
    required this.controller,
    this.embedded = false,
  });
  final bool embedded;
  final AppController controller;
  @override
  State<FamilyPanel> createState() => _FamilyPanelState();
}

class _FamilyPanelState extends State<FamilyPanel> {
  List<Map<String, String>>? collaborators;
  String? collaboratorFileId;
  String? collaboratorError;
  bool loadingCollaborators = false;
  String? success;

  String collaboratorRole(String role) => switch (role) {
    'owner' => 'Owner',
    'writer' => 'Can edit',
    'commenter' => 'Can comment',
    _ => 'Can view',
  };

  Future<void> loadCollaborators() async {
    final family = widget.controller.family;
    if (family == null || family.driveFileId == null) return;
    setState(() {
      loadingCollaborators = true;
      collaboratorError = null;
    });
    try {
      final result = await widget.controller.drive.listCollaborators(family);
      if (!mounted ||
          widget.controller.family?.driveFileId != family.driveFileId) {
        return;
      }
      await widget.controller.refreshSharingIdentity(result);
      if (!mounted ||
          widget.controller.family?.driveFileId != family.driveFileId) {
        return;
      }
      setState(() => collaborators = result);
    } catch (error) {
      if (!mounted ||
          widget.controller.family?.driveFileId != family.driveFileId) {
        return;
      }
      setState(() => collaboratorError = AppController.friendlyError(error));
    } finally {
      if (mounted &&
          widget.controller.family?.driveFileId == family.driveFileId) {
        setState(() => loadingCollaborators = false);
      }
    }
  }

  Future<void> export() async {
    final c = widget.controller;
    final data = await c.repository.export(c.family!);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export your baby log'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(data, style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: data));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Copy JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final busy = c.working || c.syncing;
      final user = c.auth.user;
      final fileId = c.family?.driveFileId;
      if (fileId != null && c.canSync && collaboratorFileId != fileId) {
        collaboratorFileId = fileId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) loadCollaborators();
        });
      }
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.embedded ? 'Settings' : 'Baby & sharing',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                if (!widget.embedded)
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: LogSpacing.content),
            Card(
              child: ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Units'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(controller: c),
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('Appearance'),
                subtitle: Text(appearanceLabel(c.themeMode)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AppearancePage(controller: c),
                  ),
                ),
              ),
            ),
            if (c.family != null) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.child_care_outlined),
                  title: const Text('Baby profile'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProfilePage(controller: c),
                    ),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('Import and recovery'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ImportPage(controller: c),
                    ),
                  ),
                ),
              ),
            ],
            if (widget.embedded && c.family != null)
              ManageBabyTile(controller: c),
            if (widget.embedded && TipJar.supported)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.favorite_outline),
                  title: const Text('Support Little Log'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TipJarPage(jar: TipJar.shared),
                    ),
                  ),
                ),
              ),
            if (widget.embedded) const AssistantHelpTile(),
            const SizedBox(height: LogSpacing.section),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: logPalette(context).surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    c.family?.isLocal == false
                        ? Icons.cloud_done_outlined
                        : Icons.phone_iphone,
                    color: logPalette(context).actionInk,
                    size: 28,
                  ),
                  const SizedBox(height: LogSpacing.content),
                  Text(
                    c.family?.storageLabel ?? 'Device storage',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: LogSpacing.label),
                  Text(
                    c.family?.isLocal == false
                        ? 'Completed entries sync to Google Drive.'
                        : 'Entries are stored on this device until Google Drive is connected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: logPalette(context).secondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: LogSpacing.field),
                  if (!AppConfig.configured)
                    const _Notice(
                      'Google Drive is unavailable in this build. Entries are stored locally.',
                    )
                  else if (!c.auth.ready)
                    _Notice(c.auth.error ?? 'Preparing sign-in…')
                  else if (user == null)
                    Align(
                      alignment: Alignment.center,
                      child: googleButton(() => c.run(c.auth.signIn)),
                    )
                  else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(user.displayName ?? 'Google account'),
                      subtitle: Text(user.email),
                    ),
                    if (!c.auth.driveConnected)
                      FilledButton(
                        onPressed: busy || c.auth.checkingDrive
                            ? null
                            : () => c.run(() async {
                                await c.auth.authorize();
                                if (mounted) {
                                  setState(() => success = null);
                                }
                                await c.sync(manual: true);
                                if (mounted &&
                                    c.message == null &&
                                    c.lastSync != null) {
                                  setState(
                                    () => success =
                                        'All entries saved to Google Drive.',
                                  );
                                }
                              }),
                        child: Text(
                          c.auth.connectingDrive
                              ? 'Connecting…'
                              : c.auth.checkingDrive
                              ? 'Checking Google Drive…'
                              : 'Connect Google Drive',
                        ),
                      )
                    else
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 18),
                          SizedBox(width: 6),
                          Flexible(child: Text('Google Drive connected')),
                        ],
                      ),
                    if (c.family?.isLocal == true && c.auth.driveConnected) ...[
                      const SizedBox(height: LogSpacing.field),
                      FilledButton(
                        onPressed: busy ? null : () => c.run(c.publishFamily),
                        child: const Text('Save log to Google Drive'),
                      ),
                      const SizedBox(height: LogSpacing.label),
                      Text(
                        'Saved in the Little Log folder. Private until shared.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: logPalette(context).secondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: LogSpacing.content),
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => c.run(c.auth.signOut),
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text('Sign out of Google'),
                    ),
                  ],
                ],
              ),
            ),
            if (c.family != null && !c.family!.isLocal && c.canSync) ...[
              const SizedBox(height: LogSpacing.section),
              SectionHeading(
                title: 'People with access to ${c.family!.babyName}',
                trailing: IconButton(
                  tooltip: 'Refresh sharing list',
                  onPressed: loadingCollaborators ? null : loadCollaborators,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              Text(
                'Log reference: ${c.family!.logReference}\nThese permissions apply only to this log.',
                style: TextStyle(
                  color: logPalette(context).secondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: LogSpacing.label),
              if (loadingCollaborators)
                const LinearProgressIndicator()
              else if (collaboratorError != null)
                _Notice(collaboratorError!)
              else if (collaborators?.isEmpty == true)
                Text(
                  'No sharing details are available.',
                  style: TextStyle(color: logPalette(context).secondary),
                )
              else
                for (final person in collaborators ?? const [])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(
                      person['email']!.toLowerCase() ==
                              user!.email.toLowerCase()
                          ? person['name'] == person['email']
                                ? 'You'
                                : '${person['name']} (You)'
                          : person['name']!,
                    ),
                    subtitle: Text(
                      [
                        if (person['email']!.isNotEmpty &&
                            person['email'] != person['name'])
                          person['email']!,
                        collaboratorRole(person['role']!),
                      ].join(' · '),
                    ),
                  ),
              const SizedBox(height: LogSpacing.section),
              const SectionHeading(title: 'Invite a caregiver'),
              InviteCaregiverForm(
                key: ValueKey(c.family!.id),
                controller: c,
                family: c.family!,
                onSent: loadCollaborators,
              ),
            ],
            ...[
              const SizedBox(height: LogSpacing.section),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<bool>(
                          builder: (_) => OnboardingPage(
                            controller: c,
                            initialStage: OnboardingStage.join,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.people_outline),
                label: const Text('Join an existing baby log'),
              ),
            ],
            if (c.family != null) ...[
              const SizedBox(height: LogSpacing.content),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Data & storage',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                children: [
                  Text(
                    'Drive location: Little Log. Exports include all local entries and active timers.',
                    style: TextStyle(
                      color: logPalette(context).secondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: LogSpacing.content),
                  if (c.family!.driveFileId != null)
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(
                          'https://drive.google.com/file/d/${c.family!.driveFileId}/view',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open file in Google Drive'),
                    ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => c.run(export),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Export baby log'),
                  ),
                  if (c.family!.legacySheetId != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: _Notice(
                        'The original spreadsheet is unchanged. Only local entries are copied.',
                      ),
                    ),
                  const SizedBox(height: LogSpacing.field),
                ],
              ),
            ],
            if (const bool.fromEnvironment('MONTHLY_PERMISSION_PROBE'))
              MonthlyProbePanel(drive: c.drive),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if (success != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    success!,
                    style: TextStyle(color: logPalette(context).actionInk),
                  ),
                ),
              ),
            if (c.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _Notice(c.message!),
              ),
            if (c.auth.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _Notice(c.auth.error!),
              ),
            if (c.family != null) ...[
              const SizedBox(height: LogSpacing.field),
              _SyncStatus(controller: c),
            ],
          ],
        ),
      );
    },
  );
}
