import 'services/live_activity.dart';
import 'services/assistant_history.dart';
import 'volume.dart';
import 'quick_log.dart';
import 'widgets/elapsed_activity_glyph.dart' show elapsedIconActivities;
import 'design.dart';
import 'dart:async';
import 'swipe_reminder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'models.dart';
import 'activity_details.dart';
import 'diaper_details.dart';
import 'record_validation.dart';
import 'storage/repository.dart';
import 'services/google_auth.dart';
import 'services/google_drive.dart';
import 'services/sync_service.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository, this.auth, this.drive)
    : syncService = SyncService(repository, drive) {
    auth.addListener(_authChanged);
  }
  final Repository repository;
  final GoogleAuth auth;
  final GoogleDrive drive;
  final SyncService syncService;
  ThemeMode themeMode = ThemeMode.system;
  String weightUnit = 'kg';
  String lengthUnit = 'cm';
  String temperatureUnit = '°C';
  VolumeUnit volumeUnit = VolumeUnit.ml;
  List<String> summaryMetrics = ['Nursing', 'Bottle', 'Diapers', 'Sleep'];
  List<String> quickLog = [...defaultQuickLog];
  bool showElapsedInIcons = false;
  final Map<String, String> babyBackgroundChoices = {};
  List<Family> families = [];
  Family? family;
  List<Feeding> feeds = [];
  Feeding? profileRecord;
  Map<String, Object?> get babyProfile => profileRecord?.details ?? const {};
  NursingSession? nursing;
  List<ActivityTimer> timers = [];
  bool recording = false;
  bool switchingBaby = false;
  bool get babyPickerBusy => working || syncing || recording || switchingBaby;
  bool loading = true;
  bool onboardingSyncedSetup = false;
  bool onboardingInvitePending = false;
  bool joiningFromOnboarding = false;
  String onboardingStep = 'tour';
  late final swipeReminder = SwipeReminder(repository);
  bool get swipeDemoSeen => swipeReminder.seen;
  bool get swipeDemoEligible => swipeReminder.eligible;
  void enterActivityVisit() => swipeReminder.enterVisit();
  bool beginSwipeDemo() => swipeReminder.begin();

  Future<void> endSwipeDemo(bool completed) async {
    await swipeReminder.end(completed);
    if (completed) notifyListeners();
  }

  Future<void> learnSwipeActions() async {
    await swipeReminder.learn();
    notifyListeners();
  }

  Future<void> setOnboardingStep(String step) async {
    onboardingStep = step;
    await repository.saveOnboardingStep(step);
    notifyListeners();
  }

  void setJoiningFromOnboarding(bool value) {
    joiningFromOnboarding = value;
    notifyListeners();
  }

  bool syncing = false;
  bool working = false;
  String? message;
  String? unavailableDriveFileId;
  DateTime? lastSync;
  Timer? _timer;
  final _syncFailures = <String, int>{};
  final _syncRetryAt = <String, DateTime>{};
  bool _foreground = true;

  bool get canSync =>
      family?.driveFileId != null &&
      auth.user != null &&
      family!.accountId == auth.user!.id;
  bool get driveFileUnavailable =>
      family?.driveFileId != null &&
      family!.driveFileId == unavailableDriveFileId;
  int _pendingDeletions = 0;
  int get pendingCount =>
      feeds.where((f) => !f.synced).length + _pendingDeletions;

  Future<void> initialize() async {
    try {
      final savedThemeMode = await repository.themeMode();
      themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == savedThemeMode,
        orElse: () => ThemeMode.system,
      );
      volumeUnit = await repository.volumeUnit();
      weightUnit = await repository.weightUnit();
      lengthUnit = await repository.lengthUnit();
      temperatureUnit = await repository.temperatureUnit();
      quickLog = await repository.quickLog();
      showElapsedInIcons = await repository.showElapsedInIcons();
      summaryMetrics = await repository.summaryMetrics();
      onboardingStep = await repository.onboardingStep();
      await swipeReminder.load();
      families = await repository.families();
      for (final baby in families) {
        await _ensureBabyBackground(baby.id);
      }
      final activeId = await repository.activeFamilyId();
      family =
          families.where((f) => f.id == activeId).firstOrNull ??
          families.firstOrNull;
      onboardingSyncedSetup =
          family != null && await repository.pendingSyncedSetup() == family!.id;
      await processLiveTimerStops();
      await refresh();
      LiveActivity.listenForStops(processLiveTimerStops);
      await auth.initialize();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_foreground) {
          notifyListeners();
          unawaited(processLiveTimerStops());
        }
        if (_foreground) {
          unawaited(sync());
        }
      });
    } catch (_) {
      message =
          'Could not load your local data. Please reopen the app; no records have been removed.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await repository.saveThemeMode(mode.name);
    themeMode = mode;
    notifyListeners();
  }

  Future<void> setVolumeUnit(VolumeUnit unit) async {
    await repository.saveVolumeUnit(unit);
    volumeUnit = unit;
    notifyListeners();
  }

  Future<void> setWeightUnit(String unit) async {
    if (!['kg', 'lb'].contains(unit)) {
      throw ArgumentError('Unknown weight unit');
    }
    await repository.saveWeightUnit(unit);
    weightUnit = unit;
    notifyListeners();
  }

  Future<void> setLengthUnit(String unit) async {
    if (!['cm', 'in'].contains(unit)) {
      throw ArgumentError('Unknown length unit');
    }
    await repository.saveLengthUnit(unit);
    lengthUnit = unit;
    notifyListeners();
  }

  Future<void> setTemperatureUnit(String unit) async {
    if (!['°C', '°F'].contains(unit)) {
      throw ArgumentError('Unknown temperature unit');
    }
    await repository.saveTemperatureUnit(unit);
    temperatureUnit = unit;
    notifyListeners();
  }

  Future<void> setSummaryMetrics(List<String> choices) async {
    const allowed = ['Nursing', 'Bottle', 'Diapers', 'Sleep', 'Pumped'];
    if (choices.isEmpty ||
        choices.toSet().length != choices.length ||
        choices.any((choice) => !allowed.contains(choice))) {
      throw ArgumentError('Choose at least one summary metric');
    }
    await repository.saveSummaryMetrics(choices);
    summaryMetrics = List.of(choices);
    notifyListeners();
  }

  Future<void> setQuickLog(List<String> choices) async {
    if (choices.isEmpty ||
        choices.length > maxQuickLogItems ||
        choices.toSet().length != choices.length ||
        choices.any((choice) => !quickLogActivities.containsKey(choice))) {
      throw ArgumentError('Choose one to six activities');
    }
    await repository.saveQuickLog(choices);
    quickLog = List<String>.of(choices);
    notifyListeners();
  }

  Future<void> setShowElapsedInIcons(bool value) async {
    await repository.saveShowElapsedInIcons(value);
    showElapsedInIcons = value;
    notifyListeners();
  }

  Duration? timeSinceLastActivity(String method, {DateTime? now}) {
    if (!elapsedIconActivities.contains(method) || family == null) return null;
    final current = now ?? DateTime.now();
    DateTime? latest;
    for (final record in feeds) {
      if (record.deleted ||
          record.familyId != family!.id ||
          record.method != method) {
        continue;
      }
      final at = record.endedAt ?? record.at;
      if (at.isAfter(current)) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest == null ? null : current.difference(latest);
  }

  String backgroundChoice(String babyId) =>
      babyBackgroundChoices[babyId] ?? babyBackgrounds.keys.first;

  Future<void> _ensureBabyBackground(String babyId) async {
    if (babyBackgroundChoices.containsKey(babyId)) return;
    final saved = await repository.babyBackground(babyId);
    final choice = babyBackgrounds.containsKey(saved)
        ? saved!
        : babyBackgrounds.keys.firstWhere(
            (key) => !babyBackgroundChoices.containsValue(key),
            orElse: () => babyBackgrounds.keys.first,
          );
    if (saved != choice) await repository.saveBabyBackground(babyId, choice);
    babyBackgroundChoices[babyId] = choice;
  }

  Future<void> setBabyBackground(String babyId, String choice) async {
    if (!babyBackgrounds.containsKey(choice) ||
        !families.any((baby) => baby.id == babyId)) {
      throw ArgumentError('Unknown baby background');
    }
    await repository.saveBabyBackground(babyId, choice);
    babyBackgroundChoices[babyId] = choice;
    notifyListeners();
  }

  Future<void> deleteRecord(Feeding record) async {
    if (family?.id != record.familyId) {
      throw StateError('The selected child has changed.');
    }
    await repository.add(record.asDeleted());
    await refresh();
    unawaited(sync());
  }

  void _authChanged() {
    notifyListeners();
    if (!loading && _foreground && auth.user != null && auth.driveConnected) {
      unawaited(sync());
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    if (value) {
      unawaited(processLiveTimerStops().then((_) => sync()));
    }
  }

  int _refreshRevision = 0;

  Future<void> refresh() async {
    final revision = ++_refreshRevision;
    final selected = family;
    final nextFamilies = await repository.families();
    final allRecords = selected == null
        ? <Feeding>[]
        : await repository.feeds(selected.id, includeDeleted: true);
    final nextNursing = selected == null
        ? null
        : await repository.nursingSession(selected.id);
    final nextTimers = selected == null
        ? <ActivityTimer>[]
        : await repository.activityTimers(selected.id);
    final nextSync = selected == null
        ? null
        : await repository.lastSync(selected.id);
    final live = <Map<String, Object?>>[];
    for (final baby in nextFamilies) {
      live.addAll(
        LiveActivity.snapshots(
          baby.babyName,
          baby.id == selected?.id
              ? nextNursing
              : await repository.nursingSession(baby.id),
          baby.id == selected?.id
              ? nextTimers
              : await repository.activityTimers(baby.id),
        ),
      );
    }
    // Publish a complete snapshot only if it still belongs to this selection
    // and no newer refresh has superseded it.
    if (revision != _refreshRevision || family?.id != selected?.id) return;
    final profiles =
        allRecords.where((f) => !f.deleted && f.method == 'profile').toList()
          ..sort((a, b) {
            final time = b.at.compareTo(a.at);
            return time != 0 ? time : b.id.compareTo(a.id);
          });
    families = nextFamilies;
    profileRecord = profiles.firstOrNull;
    feeds = allRecords
        .where((f) => !f.deleted && f.method != 'profile')
        .toList();
    _pendingDeletions = allRecords.where((f) => f.deleted && !f.synced).length;
    nursing = nextNursing;
    timers = nextTimers;
    lastSync = nextSync;
    notifyListeners();
    await LiveActivity.updateAll(live);
  }

  Future<void> createLocal(String name, String babyName) async {
    if (babyName.trim().isEmpty) throw StateError('Enter your baby’s name.');
    final created = Family(
      id: newId.v4(),
      name: name.trim(),
      babyName: babyName.trim(),
    );
    await repository.saveFamily(created);
    await setOnboardingStep('tour');
    await _ensureBabyBackground(created.id);
    family = created;
    await refresh();
  }

  Future<void> createSynced(String babyName) async {
    if (auth.user == null || !auth.driveConnected) {
      throw StateError('Connect Google Drive before creating a shared log.');
    }
    if (!onboardingSyncedSetup) {
      final name = babyName.trim();
      if (name.isEmpty) throw StateError('Enter your baby’s name.');
      final created = Family(
        id: newId.v4(),
        name: '$name’s family',
        babyName: name,
      );
      await repository.savePendingSyncedFamily(created);
      onboardingSyncedSetup = true;
      family = created;
      await _ensureBabyBackground(created.id);
      await refresh();
    }
    await publishFamily();
    if (message != null || family?.isLocal != false || lastSync == null) {
      throw StateError(
        message ??
            'The log has not finished saving to Google Drive. Try again.',
      );
    }
    await repository.setPendingSyncedSetup(null);
    await setOnboardingStep('tour');
    onboardingSyncedSetup = false;
    onboardingInvitePending = true;
    notifyListeners();
  }

  Future<void> usePendingSetupLocally() async {
    if (!onboardingSyncedSetup || family?.isLocal != true) {
      throw StateError(
        'This log is already connected to Google Drive. Retry saving it.',
      );
    }
    await repository.setPendingSyncedSetup(null);
    await setOnboardingStep('tour');
    onboardingSyncedSetup = false;
    notifyListeners();
  }

  Future<void> select(Family selected) async {
    if (babyPickerBusy || selected.id == family?.id) return;
    switchingBaby = true;
    notifyListeners();
    try {
      await repository.selectFamily(selected.id);
      family = selected;
      message = null;
      await refresh();
    } finally {
      switchingBaby = false;
      notifyListeners();
    }
    unawaited(sync());
  }

  Future<void> renameBaby(Family baby, String name) async {
    if (syncing || recording || switchingBaby) {
      throw StateError('Please wait for the current action to finish.');
    }
    switchingBaby = true;
    notifyListeners();
    try {
      final updated = await repository.renameBaby(baby.id, name);
      if (family?.id == baby.id) family = updated;
      await refresh();
    } finally {
      switchingBaby = false;
      notifyListeners();
    }
  }

  Future<void> deleteBaby(Family baby) async {
    if (syncing || recording || switchingBaby) {
      throw StateError('Please wait for the current action to finish.');
    }
    switchingBaby = true;
    notifyListeners();
    try {
      await repository.deleteBaby(baby.id);
      babyBackgroundChoices.remove(baby.id);
      families = await repository.families();
      final activeId = await repository.activeFamilyId();
      family = families.where((f) => f.id == activeId).firstOrNull;
      message = null;
      await refresh();
    } finally {
      switchingBaby = false;
      notifyListeners();
    }
  }

  Future<void> refreshSharingIdentity(List<Map<String, String>> people) async {
    final selected = family;
    if (selected == null || selected.isLocal) return;
    final owner = people.where((p) => p['role'] == 'owner').firstOrNull;
    if (owner == null) return;
    final identified = selected.withDriveIdentity(
      email: owner['email'],
      name: owner['name'],
      shared: people.any((p) => p['role'] != 'owner'),
    );
    await repository.updateFamilyIdentity(identified);
    if (family?.id == selected.id) family = identified;
    await refresh();
  }

  Future<void> publishFamily() =>
      _sync(manual: true, expectedFamilyId: family?.id, publishLocal: true);

  /// An explicit backup applies only to the log selected when it was requested.
  /// Ordinary sign-in (including invitation acceptance) never calls this path.
  Future<void> backUpFamily() async {
    final selectedId = family?.id;
    if (selectedId == null) throw StateError('Choose a log to back up.');
    if (auth.user == null) await auth.signIn();
    final session = auth.captureAccount();
    if (!auth.driveConnected) await auth.authorize();
    auth.checkAccount(session);
    await _sync(manual: true, expectedFamilyId: selectedId, publishLocal: true);
  }

  Future<void> join(String driveFileId, {String? expectedFamilyId}) async {
    final account = auth.user;
    if (account == null) {
      throw StateError('Sign in with the invited Google account first.');
    }
    if (switchingBaby || recording) {
      throw StateError('Finish the current action, then try again.');
    }
    final session = auth.captureAccount(expectedAccountId: account.id);
    switchingBaby = true;
    notifyListeners();
    try {
      await _syncTask;
      auth.checkAccount(session);
      final selected = await drive.openFamily(driveFileId, account.id);
      if (expectedFamilyId != null && selected.id != expectedFamilyId) {
        throw StateError(
          'This shared log changed. Refresh the list and choose it again.',
        );
      }
      auth.checkAccount(session);
      final history = await drive.readFeeds(selected);
      if (history.skipped > 0) {
        throw const FormatException(
          'Some shared entries could not be read. Ask the sender to check the log, then try again.',
        );
      }
      auth.checkAccount(session);
      await repository.joinFamily(selected, history.feeds);
      family = selected;
      onboardingSyncedSetup = false;
      onboardingStep = 'tour';
      message = null;
      await _ensureBabyBackground(selected.id);
      await refresh();
    } finally {
      switchingBaby = false;
      notifyListeners();
    }
  }

  Future<void> _saveEntry(Feeding record, Feeding? original) async {
    if (original == null) {
      await repository.add(record);
    } else {
      if (family?.id != original.familyId || original.method != record.method) {
        throw StateError('The selected child has changed. Reopen the entry.');
      }
      await repository.replace(original, record);
    }
  }

  Future<void> saveBabyProfile(
    Map<String, Object?> details,
    String expectedFamilyId,
  ) async {
    if (family?.id != expectedFamilyId) {
      throw StateError('The selected child has changed.');
    }
    validateProfile(details);
    final record = Feeding(
      id: newId.v4(),
      familyId: expectedFamilyId,
      at: DateTime.now(),
      method: 'profile',
      source: profileRecord?.source ?? const {},
      details: details,
      author: auth.user?.email ?? '',
    );
    await _saveEntry(record, profileRecord);
    await refresh();
    unawaited(sync());
  }

  Future<void> addFeed({
    required DateTime at,
    required String method,
    double? amountMl,
    int? minutes,
    int? leftSeconds,
    int? rightSeconds,
    Map<String, Object?> details = const {},
    required String note,
    Feeding? original,
    String? expectedFamilyId,
  }) async {
    final selected = family;
    if (selected == null) throw StateError('Add a baby first.');
    if (expectedFamilyId != null && selected.id != expectedFamilyId) {
      throw StateError('The selected child has changed. Reopen the form.');
    }
    if (at.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      throw const FormatException('Choose a time in the past or now.');
    }
    final preservingLegacyNursing =
        method == 'nursing' &&
        original?.method == 'nursing' &&
        original?.leftSeconds == null &&
        original?.rightSeconds == null &&
        original != null &&
        minutes == original.minutes;
    if (method == 'nursing' &&
        (leftSeconds == null || rightSeconds == null) &&
        !preservingLegacyNursing) {
      throw const FormatException(
        'Record the time for the left side, right side, or both.',
      );
    }
    final keepingNursingDuration =
        method == 'nursing' &&
        original?.method == 'nursing' &&
        original?.leftSeconds != null &&
        original!.leftSeconds == leftSeconds &&
        original.rightSeconds == rightSeconds;
    if (!['bottle', 'nursing'].contains(method) ||
        (method == 'bottle' &&
            (amountMl == null ||
                !amountMl.isFinite ||
                amountMl <= 0 ||
                amountMl > 2000)) ||
        (method == 'nursing' &&
            !keepingNursingDuration &&
            (minutes == null || minutes <= 0 || minutes > 240)) ||
        note.length > 2000) {
      throw const FormatException('Please check the feeding details.');
    }
    if (leftSeconds != null || rightSeconds != null) {
      if (method != 'nursing' ||
          leftSeconds == null ||
          rightSeconds == null ||
          leftSeconds < 0 ||
          rightSeconds < 0 ||
          (!keepingNursingDuration &&
              (leftSeconds + rightSeconds <= 0 ||
                  leftSeconds + rightSeconds > 14400))) {
        throw const FormatException('Please check the nursing side times.');
      }
    }
    DateTime? nursingEndedAt;
    if (method == 'nursing' && original?.endedAt != null) {
      final elapsed = original!.endedAt!.difference(original.at);
      if (leftSeconds == null ||
          rightSeconds == null ||
          Duration(seconds: leftSeconds + rightSeconds) <= elapsed) {
        nursingEndedAt = at.add(elapsed);
      }
      // Keep the recorded stop time when the correction fits its window.
      // Otherwise the end remains unknown; recorded side totals still resume.
    }
    final record = Feeding(
      id: newId.v4(),
      familyId: selected.id,
      at: at,
      method: method,
      amountMl: method == 'bottle' ? amountMl : null,
      minutes: method == 'nursing'
          ? (keepingNursingDuration ? original.minutes : minutes)
          : null,
      leftSeconds: leftSeconds,
      rightSeconds: rightSeconds,
      endedAt: nursingEndedAt,
      details: details,
      source: original?.source ?? const {},
      note: note.trim(),
      author: original?.author ?? auth.user?.email ?? '',
    );
    validateRecord(record, selected.id);
    await _saveEntry(record, original);
    await refresh();
    unawaited(sync());
  }

  Future<void> addDiaper({
    required String kind,
    required DateTime at,
    String note = '',
    String? poopColor,
    String? poopConsistency,
    List<String>? selectedColors,
    List<String>? selectedConsistencies,
    bool? blowout,
    bool? rash,
    Feeding? original,
    String? expectedFamilyId,
  }) async {
    final selected = family;
    if (selected == null) throw StateError('Add a baby first.');
    if (expectedFamilyId != null && selected.id != expectedFamilyId) {
      throw StateError('The selected child has changed. Reopen the form.');
    }
    if (at.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      throw const FormatException('Choose a time in the past or now.');
    }
    final record = Feeding(
      id: newId.v4(),
      familyId: selected.id,
      at: at,
      method: 'diaper',
      diaperKind: kind,
      details: {
        if (selectedColors != null && selectedColors.length > 1)
          'poopColors': selectedColors,
        if (selectedColors?.length == 1) 'poopColor': selectedColors!.single,
        if (selectedConsistencies != null && selectedConsistencies.length > 1)
          'poopConsistencies': selectedConsistencies,
        if (selectedConsistencies?.length == 1)
          'poopConsistency': selectedConsistencies!.single,
        if (selectedColors == null) 'poopColor': ?poopColor,
        if (selectedConsistencies == null) 'poopConsistency': ?poopConsistency,
        'blowout': ?blowout,
        'rash': ?rash,
      },
      source: original?.source ?? const {},
      note: note.trim(),
      author: original?.author ?? auth.user?.email ?? '',
    );
    validateDiaper(record, selected.id);
    await _saveEntry(record, original);
    await refresh();
    unawaited(sync());
  }

  /// Uses the selected baby and the same durable writes as the entry forms.
  /// The assistant receives success only after refresh completes; Drive sync is separate.
  Future<String> performAssistantAction(
    String action, {
    String? kind,
    double? amount,
    String? unit,
    required DateTime at,
  }) async {
    final selected = family;
    if (selected == null || onboardingSyncedSetup || joiningFromOnboarding) {
      throw StateError(
        'Finish setting up a baby in Little Log, then try again.',
      );
    }
    if (working || recording || switchingBaby) {
      throw StateError('Little Log is busy. Try again in a moment.');
    }
    if (!{
      'add_diaper',
      'nursing_left',
      'nursing_right',
      'sleep',
      'pumping',
      'finish_sleep',
      'finish_nursing',
      'finish_pumping',
      'open_diaper',
      'open_nursing',
      'review_pumping',
      ...assistantHistoryQuestions.keys,
    }.contains(action)) {
      throw const FormatException('That voice action is not available.');
    }
    working = true;
    notifyListeners();
    try {
      if (assistantHistoryQuestions.containsKey(action)) {
        final records = await repository.feeds(selected.id);
        final activeTimers = await repository.activityTimers(selected.id);
        final activeNursing = await repository.nursingSession(selected.id);
        if (family?.id != selected.id) {
          throw StateError('The selected baby changed. Ask again.');
        }
        return answerAssistantHistory(
          action: action,
          baby: selected,
          records: records,
          timers: activeTimers,
          nursing: activeNursing,
          now: at,
        );
      }
      if (action == 'open_diaper' || action == 'open_nursing') {
        return action == 'open_diaper'
            ? 'Choose the diaper details for ${selected.babyName}.'
            : 'Choose the nursing side for ${selected.babyName}.';
      }
      if (action == 'review_pumping') {
        final timer = timers
            .where((timer) => timer.method == 'pumping')
            .firstOrNull;
        if (timer == null) throw StateError('No pumping session is open.');
        await _applyLiveTimerAction(
          sessionId: timer.id,
          familyId: selected.id,
          method: 'pumping',
          action: 'finish',
          at: at,
        );
        await refresh();
        return 'Enter the pumped amount for ${selected.babyName}.';
      }
      if (action == 'add_diaper') {
        const kinds = {
          'wet': 'wet',
          'dirty': 'dirty',
          'both': 'wet and dirty',
          'dry': 'dry',
        };
        if (!kinds.containsKey(kind)) {
          throw const FormatException('Choose a diaper type.');
        }
        await addDiaper(kind: kind!, at: at, expectedFamilyId: selected.id);
        return 'Added a ${kinds[kind]} diaper for ${selected.babyName}.';
      }
      if (action == 'sleep' || action == 'pumping') {
        final label = action == 'sleep' ? 'Sleep' : 'Pumping';
        if (timers.any((timer) => timer.method == action)) {
          return '$label is already running for ${selected.babyName}.';
        }
        await startActivityTimer(action);
        return 'Started ${label.toLowerCase()} for ${selected.babyName}.';
      }
      if (action == 'finish_nursing') {
        final session = nursing;
        if (session == null) {
          throw StateError(
            'No nursing timer is running for ${selected.babyName}.',
          );
        }
        await saveReviewedNursing(
          session: session,
          endedAt: at,
          note: session.note,
        );
        return 'Saved nursing for ${selected.babyName}.';
      }
      if (action == 'finish_sleep' || action == 'finish_pumping') {
        final method = action == 'finish_sleep' ? 'sleep' : 'pumping';
        final timer = timers
            .where((timer) => timer.method == method)
            .firstOrNull;
        if (timer == null) {
          throw StateError(
            'No $method timer is running for ${selected.babyName}.',
          );
        }
        double? amountMl;
        ActivityTimer finishingTimer = timer;
        if (method == 'pumping') {
          if (timer.phase == 'running') {
            throw StateError('Pause pumping before finishing.');
          }
          if (amount == null ||
              !amount.isFinite ||
              amount <= 0 ||
              !['ml', 'oz'].contains(unit)) {
            throw const FormatException(
              'Enter a pumped amount greater than zero and choose ml or US fluid ounces.',
            );
          }
          amountMl = (unit == 'oz' ? VolumeUnit.oz : VolumeUnit.ml).toMl(
            amount,
          );
          if (amountMl > 2000) {
            throw const FormatException(
              'The pumped amount must be 2000 ml or less.',
            );
          }
        }
        if (method == 'pumping' && timer.paused) {
          finishingTimer = timer.finish();
          await repository.changePumpingTimer(timer, finishingTimer);
        }
        await addActivity(
          method: method,
          at: timer.startedAt,
          endedAt: finishingTimer.stoppedAt ?? at,
          amountMl: amountMl,
          timer: finishingTimer,
          expectedFamilyId: selected.id,
        );
        return 'Saved $method for ${selected.babyName}.';
      }
      final side = action == 'nursing_left' ? 'left' : 'right';
      if (nursing != null && !nursing!.paused) {
        return 'Nursing is already running on the ${nursing!.side} side for ${selected.babyName}.';
      }
      await nursingAction(side, rethrowErrors: true);
      return 'Started nursing on the $side side for ${selected.babyName}.';
    } finally {
      working = false;
      notifyListeners();
    }
  }

  Future<void>? _liveTimerDrain;
  ({String familyId, String sessionId})? pendingPumpingReview;

  Future<void> processLiveTimerStops() => _liveTimerDrain ??=
      _processLiveTimerStops().whenComplete(() => _liveTimerDrain = null);

  Future<void> _processLiveTimerStops() async {
    if (recording || working) return;
    try {
      for (final request in await LiveActivity.pendingStops()) {
        final id = request['id'], familyId = request['familyId'];
        final method = request['method'], milliseconds = request['stoppedAt'];
        if (id is! String ||
            familyId is! String ||
            method is! String ||
            milliseconds is! num) {
          throw const FormatException(
            'Could not read the stopped timer. Reopen Little Log.',
          );
        }
        final sessionId = request['sessionId'] as String? ?? id;
        final action = request['action'] as String? ?? 'finish';
        final at = DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt());
        // Complete already-issued stop requests from builds before pause/finish.
        if (!request.containsKey('action') && method != 'sleep') {
          await performLiveTimerAction(
            sessionId: sessionId,
            familyId: familyId,
            method: method,
            action: 'pause',
            at: at,
          );
        }
        final accepted = await performLiveTimerAction(
          sessionId: sessionId,
          familyId: familyId,
          method: method,
          action: action,
          at: at,
          expectedRevision: request['revision'] as int?,
        );
        if (accepted &&
            method == 'pumping' &&
            ['finish', 'review'].contains(action)) {
          pendingPumpingReview = (familyId: familyId, sessionId: sessionId);
          notifyListeners();
        }
        await LiveActivity.acknowledgeStop(id);
      }
    } catch (error) {
      message = friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> finishLiveTimer({
    required String sessionId,
    required String familyId,
    required String method,
    required DateTime at,
  }) async {
    await performLiveTimerAction(
      sessionId: sessionId,
      familyId: familyId,
      method: method,
      action: 'finish',
      at: at,
    );
  }

  /// Every surface uses the same transitions. Revision checks reject stale taps.
  Future<bool> performLiveTimerAction({
    required String sessionId,
    required String familyId,
    required String method,
    required String action,
    required DateTime at,
    int? expectedRevision,
  }) async {
    if (recording || working) {
      throw StateError('Please wait for the current change.');
    }
    recording = true;
    notifyListeners();
    try {
      final changed = await _applyLiveTimerAction(
        sessionId: sessionId,
        familyId: familyId,
        method: method,
        action: action,
        at: at,
        expectedRevision: expectedRevision,
      );
      if (changed) {
        await refresh();
        if (action == 'finish' && method != 'pumping') {
          _pendingTimerSync.add(familyId);
          unawaited(sync());
        }
      }
      return changed;
    } finally {
      recording = false;
      notifyListeners();
    }
  }

  Future<bool> _applyLiveTimerAction({
    required String sessionId,
    required String familyId,
    required String method,
    required String action,
    required DateTime at,
    int? expectedRevision,
  }) async {
    if (!['nursing', 'sleep', 'pumping'].contains(method) ||
        !['pause', 'resume', 'finish', 'review', 'switch'].contains(action) ||
        (action == 'switch' && method != 'nursing') ||
        at.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      throw const FormatException('Check the timer and device clock.');
    }
    if (!(await repository.families()).any((baby) => baby.id == familyId)) {
      return false;
    }
    if (method == 'nursing') {
      final session = await repository.nursingSession(familyId);
      if (session == null ||
          session.id != sessionId ||
          (expectedRevision != null && expectedRevision != session.revision)) {
        return false;
      }
      if (at.isBefore(session.segmentAt)) {
        throw const FormatException('Check the device clock.');
      }
      switch (action) {
        case 'switch':
          if (session.paused) return false;
          await repository.saveSession(
            session.switchTo(session.side == 'left' ? 'right' : 'left', at),
          );
        case 'pause':
          if (session.paused) return false;
          await repository.saveSession(session.pause(at));
        case 'resume':
          if (!session.paused) return false;
          await repository.saveSession(session.resume(at));
        case 'finish':
          if (!session.paused) {
            throw StateError('Pause nursing before finishing.');
          }
          await repository.finishSession(
            session,
            session.finish(session.segmentAt, auth.user?.email ?? ''),
          );
        default:
          return false;
      }
    } else {
      final timer = (await repository.activityTimers(familyId))
          .where((timer) => timer.id == sessionId && timer.method == method)
          .firstOrNull;
      if (timer == null ||
          (expectedRevision != null && timer.revision != expectedRevision)) {
        return false;
      }
      if (method == 'sleep') {
        if (action != 'finish') {
          throw StateError('Sleep does not pause. Finish the sleep session.');
        }
        if (!at.isAfter(timer.startedAt)) {
          throw const FormatException('Check the device clock.');
        }
        await repository.finishTimer(
          timer,
          Feeding(
            id: timer.id,
            familyId: familyId,
            method: 'sleep',
            at: timer.startedAt,
            endedAt: at,
            author: auth.user?.email ?? '',
          ),
        );
      } else {
        switch (action) {
          case 'pause':
            if (timer.phase != 'running') return false;
            await repository.changePumpingTimer(timer, timer.pause(at));
          case 'resume':
            if (!timer.paused) return false;
            await repository.changePumpingTimer(timer, timer.resume(at));
          case 'finish':
            if (timer.phase == 'review') return true;
            if (!timer.paused) {
              throw StateError('Pause pumping before finishing.');
            }
            await repository.changePumpingTimer(timer, timer.finish());
          case 'review':
            return timer.phase == 'review';
        }
      }
    }
    return true;
  }

  Future<void> discardNursingSession(NursingSession session) async {
    if (family?.id != session.familyId) {
      throw StateError('The selected baby has changed.');
    }
    if (recording || working) {
      throw StateError('Please wait for the current change.');
    }
    recording = true;
    notifyListeners();
    try {
      await repository.discardNursing(session);
      await refresh();
      unawaited(sync());
    } finally {
      recording = false;
      notifyListeners();
    }
  }

  Future<void> startActivityTimer(String method) async {
    if (recording || family == null) return;
    recording = true;
    notifyListeners();
    try {
      await repository.startTimer(
        ActivityTimer(
          id: newId.v4(),
          familyId: family!.id,
          method: method,
          startedAt: DateTime.now(),
        ),
      );
      await refresh();
    } finally {
      recording = false;
      notifyListeners();
    }
  }

  Future<void> discardActivityTimer(ActivityTimer timer) async {
    if (family?.id != timer.familyId) {
      throw StateError('The selected child has changed. Reopen the form.');
    }
    if (recording || working) {
      throw StateError('Finish the current action, then try again.');
    }
    recording = true;
    notifyListeners();
    try {
      await repository.discardTimer(timer);
      await refresh();
    } finally {
      recording = false;
      notifyListeners();
    }
  }

  Future<void> addActivity({
    required String method,
    required DateTime at,
    DateTime? endedAt,
    double? amountMl,
    Map<String, Object?> details = const {},
    String note = '',
    ActivityTimer? timer,
    Feeding? original,
    String? expectedFamilyId,
  }) async {
    final selected = family;
    if (selected == null ||
        (expectedFamilyId != null && selected.id != expectedFamilyId) ||
        (timer != null && timer.familyId != selected.id)) {
      throw StateError('The selected child has changed. Reopen the form.');
    }
    final now = DateTime.now().add(const Duration(minutes: 1));
    if (at.isAfter(now) || (endedAt?.isAfter(now) ?? false)) {
      throw const FormatException('Choose a time in the past or now.');
    }
    if (timer?.method == 'pumping' && timer!.phase != 'review') {
      throw StateError('Pause and finish pumping before saving.');
    }
    final record = Feeding(
      id: timer?.id ?? newId.v4(),
      familyId: selected.id,
      at: at,
      method: method,
      endedAt: endedAt,
      amountMl: amountMl,
      details: {
        ...details,
        if (method == 'pumping' && original?.details['activeSeconds'] != null)
          'activeSeconds': original!.details['activeSeconds'],
        if (timer?.method == 'pumping')
          'activeSeconds': timer!.elapsedAt(timer.stoppedAt!).inSeconds,
      },
      source: original?.source ?? const {},
      note: note.trim(),
      author: original?.author ?? auth.user?.email ?? '',
    );
    validateActivity(record, selected.id);
    if (timer == null) {
      await _saveEntry(record, original);
    } else {
      await repository.finishTimer(timer, record);
    }
    await refresh();
    unawaited(sync());
  }

  Future<void> saveReviewedNursing({
    required NursingSession session,
    required DateTime endedAt,
    required String note,
  }) async {
    if (recording) throw StateError('Please wait for the current change.');
    if (!session.paused) throw StateError('Pause nursing before finishing.');
    if (family?.id != session.familyId) {
      throw StateError('The selected child has changed. Reopen the activity.');
    }
    if (note.length > 2000 ||
        endedAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      throw const FormatException('Please check the session details.');
    }
    recording = true;
    notifyListeners();
    try {
      final current = await repository.nursingSession(session.familyId);
      if (current == null ||
          current.id != session.id ||
          !current.segmentAt.isAtSameMomentAs(session.segmentAt)) {
        throw StateError(
          'This timer has changed. Reopen it to review the current session.',
        );
      }
      final record = session.finish(session.segmentAt, auth.user?.email ?? '');
      await repository.finishSession(
        session,
        Feeding.fromJson({...record.toJson(), 'note': note.trim()}),
      );
      await refresh();
      unawaited(sync());
    } finally {
      recording = false;
      notifyListeners();
    }
  }

  Future<void> nursingAction(
    String action, {
    bool rethrowErrors = false,
  }) async {
    if (recording || family == null) return;
    recording = true;
    message = null;
    notifyListeners();
    try {
      final selected = family!;
      final current = await repository.nursingSession(selected.id);
      final now = DateTime.now();
      if (action == 'end') {
        if (current != null) {
          if (!current.paused) {
            throw StateError('Pause nursing before finishing.');
          }
          await repository.finishSession(
            current,
            current.finish(current.segmentAt, auth.user?.email ?? ''),
          );
        }
      } else if (action == 'pause' || action == 'resume') {
        if (current != null) {
          await repository.saveSession(
            action == 'pause' ? current.pause(now) : current.resume(now),
          );
        }
      } else {
        if (!['left', 'right'].contains(action)) {
          throw const FormatException('Choose left or right.');
        }
        await repository.saveSession(
          current == null
              ? NursingSession(
                  id: newId.v4(),
                  familyId: selected.id,
                  startedAt: now,
                  segmentAt: now,
                  side: action,
                )
              : current.switchTo(action, now),
        );
      }
      await refresh();
      if (action == 'end') unawaited(sync());
    } catch (e) {
      message = friendlyError(e);
      if (rethrowErrors) rethrow;
    } finally {
      recording = false;
      notifyListeners();
    }
  }

  Future<void> reopenNursing(Feeding original, String side) async {
    final selected = family;
    if (selected == null || selected.id != original.familyId) {
      throw StateError('The selected child has changed. Reopen the entry.');
    }
    if (original.method != 'nursing' ||
        original.leftSeconds == null ||
        original.rightSeconds == null ||
        !['left', 'right'].contains(side)) {
      throw const FormatException(
        'Only a nursing session with recorded side times can be resumed.',
      );
    }
    final now = DateTime.now();
    if (now.isBefore(original.endedAt ?? original.at)) {
      throw const FormatException('Check the device clock.');
    }
    await repository.reopenNursing(
      original,
      NursingSession(
        id: newId.v4(),
        familyId: selected.id,
        startedAt: original.at,
        segmentAt: now,
        side: side,
        leftSeconds: original.leftSeconds!,
        rightSeconds: original.rightSeconds!,
        note: original.note,
        source: original.source,
      ),
    );
    await refresh();
    unawaited(sync());
  }

  Future<void>? _syncTask;
  final _pendingTimerSync = <String>{};
  bool _syncNeedsRefresh = false;

  Future<void> sync({bool manual = false, String? expectedFamilyId}) =>
      _sync(manual: manual, expectedFamilyId: expectedFamilyId);

  Future<void> _sync({
    bool manual = false,
    String? expectedFamilyId,
    bool publishLocal = false,
  }) async {
    // A pull-to-refresh must wait for an in-flight upload, then flush anything
    // logged during that upload. Automatic ticks simply join the active pass.
    while (_syncTask != null) {
      await _syncTask;
      if (!manual && _pendingTimerSync.isEmpty) return;
    }
    if (expectedFamilyId != null && family?.id != expectedFamilyId) {
      throw StateError('The selected log changed. Choose it and try again.');
    }
    if (switchingBaby || (!_foreground && !manual)) return;
    if (auth.user == null && !manual) return;
    _syncNeedsRefresh = false;
    final task = Future<void>.microtask(() async {
      try {
        await _syncBatch(manual: manual, publishLocal: publishLocal);
      } finally {
        syncing = false;
        if (_syncNeedsRefresh) {
          await refresh();
        } else {
          notifyListeners();
        }
      }
    });
    _syncTask = task;
    syncing = true;
    notifyListeners();
    try {
      await task;
    } finally {
      if (identical(_syncTask, task)) _syncTask = null;
    }
  }

  Future<void> _syncBatch({
    required bool manual,
    required bool publishLocal,
  }) async {
    final selected = family;
    // Persisted unsynced records are the outbox, including after a restart.
    // Only already-connected logs belonging to this account are eligible.
    final accountId = auth.user?.id;
    for (final candidate in await repository.families()) {
      if (candidate.id == selected?.id ||
          candidate.isLocal ||
          candidate.accountId != accountId) {
        continue;
      }
      final rows = await repository.feeds(candidate.id, includeDeleted: true);
      if (rows.any((row) => !row.synced)) _pendingTimerSync.add(candidate.id);
    }
    if (selected != null) {
      _pendingTimerSync.remove(selected.id);
      await _syncOnce(selected, manual: manual, publishLocal: publishLocal);
    }
    while (_pendingTimerSync.isNotEmpty) {
      final requested = Set<String>.of(_pendingTimerSync);
      _pendingTimerSync.removeAll(requested);
      for (final candidate in await repository.families()) {
        if (!requested.contains(candidate.id) || candidate.isLocal) continue;
        await _syncOnce(candidate, manual: false);
      }
    }
  }

  Future<void> _syncOnce(
    Family target, {
    required bool manual,
    bool publishLocal = false,
  }) async {
    if (switchingBaby) return;
    if (!_foreground && !manual) return;
    final retryAt = _syncRetryAt[target.id];
    if (!manual && retryAt != null && DateTime.now().isBefore(retryAt)) {
      return;
    }
    var selected = target;
    // Refresh and sign-in never change the user's storage choice. Only an
    // explicit backup or Drive creation may publish this selected local log.
    if (selected.isLocal && !publishLocal) {
      if (manual && family?.id == selected.id) message = null;
      return;
    }
    final account = auth.user;
    if (account == null) {
      if (manual) {
        message = 'Connect Google Drive in Settings to save your log to Drive.';
        notifyListeners();
      }
      return;
    }
    if (!selected.isLocal && selected.accountId != account.id) {
      if (manual) {
        message =
            'Reconnect the Google account linked to this baby in Settings.';
        notifyListeners();
      }
      return;
    }
    _syncNeedsRefresh = true;
    if (family?.id == selected.id) message = null;
    notifyListeners();
    try {
      final session = auth.captureAccount(expectedAccountId: account.id);
      // Silent scope check: pull-to-refresh never opens a surprise sign-in UI.
      await auth.accessToken();
      auth.checkAccount(session);
      if (selected.isLocal) {
        selected = await drive.createFamily(selected, account.id);
        auth.checkAccount(session);
        await repository.prepareCsvFamily(selected);
        family = selected;
      }
      auth.checkAccount(session);
      await drive.prepareSync(selected, force: manual);
      auth.checkAccount(session);
      final identified = drive.cachedFamily(selected);
      if (identified != null) await repository.updateFamilyIdentity(identified);
      if (identified != null && family?.id == selected.id) {
        family = Family.fromJson({
          ...selected.toJson(),
          'ownerEmail': identified.ownerEmail,
          'ownerName': identified.ownerName,
          'driveShared': identified.driveShared,
        });
      }
      for (var pass = 0; pass < 10; pass++) {
        final skipped = await syncService.sync(
          selected,
          accountId: account.id,
          checkAccount: () => auth.checkAccount(session),
        );
        if (skipped > 0) {
          throw const FormatException(
            'Some Drive entries could not be read. Your local entries are retained.',
          );
        }
        final pending = (await repository.feeds(
          selected.id,
          includeDeleted: true,
        )).where((f) => !f.synced);
        if (pending.isEmpty) break;
        if (pass == 9) {
          throw StateError(
            'More entries are waiting to upload. Pull down again to finish syncing.',
          );
        }
      }
      _syncFailures.remove(selected.id);
      _syncRetryAt.remove(selected.id);
      if (family?.id == selected.id) unavailableDriveFileId = null;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Sync failed (${e.runtimeType}): $stack');
      if (family?.id == selected.id) {
        message = friendlyError(e);
        unavailableDriveFileId = e is CloudException && e.status == 404
            ? selected.driveFileId
            : null;
      }
      final failures = ((_syncFailures[selected.id] ?? 0) + 1).clamp(1, 5);
      _syncFailures[selected.id] = failures;
      _syncRetryAt[selected.id] = DateTime.now().add(
        Duration(seconds: 15 * (1 << failures)),
      );
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (working || syncing) return;
    working = true;
    message = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      message = friendlyError(e);
    } finally {
      working = false;
      notifyListeners();
    }
  }

  static String friendlyError(Object e) {
    if (e is CloudException) return e.message;
    if (e is StateError) return e.message.toString();
    if (e is FormatException) return e.message;
    return 'That did not finish. Please check your connection and try again. Saved entries remain on this device.';
  }

  @override
  void dispose() {
    _timer?.cancel();
    auth.removeListener(_authChanged);
    auth.dispose();
    drive.dispose();
    super.dispose();
  }
}
