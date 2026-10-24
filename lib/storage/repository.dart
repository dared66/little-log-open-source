import '../volume.dart';
import '../services/history_import.dart';
import 'dart:convert';
import 'package:sembast/sembast.dart';
import '../models.dart';
import '../activity_details.dart';
import '../quick_log.dart';

class Repository {
  Repository(this.db);
  final Database db;
  final _families = stringMapStoreFactory.store('families');
  final _feeds = stringMapStoreFactory.store('feedings');
  final _sessions = stringMapStoreFactory.store('nursingSessions');
  final _resumedNursing = stringMapStoreFactory.store('resumedNursing');
  final _timers = stringMapStoreFactory.store('activityTimers');
  final _settings = StoreRef<String, Object?>('settings');

  Future<String?> pendingSyncedSetup() async =>
      await _settings.record('pendingSyncedSetup').get(db) as String?;
  Future<void> setPendingSyncedSetup(String? familyId) async {
    if (familyId == null) {
      await _settings.record('pendingSyncedSetup').delete(db);
    } else {
      await _settings.record('pendingSyncedSetup').put(db, familyId);
    }
  }

  Future<void> savePendingSyncedFamily(Family family) async {
    await db.transaction((txn) async {
      final existing = await _families.record(family.id).get(txn);
      if (existing == null && await _families.count(txn) >= maxBabies) {
        throw StateError('You can have up to three babies.');
      }
      await _families.record(family.id).put(txn, family.toJson());
      await _settings.record('activeFamily').put(txn, family.id);
      await _settings.record('pendingSyncedSetup').put(txn, family.id);
    });
  }

  Future<Family> deferSyncedSetup(String pendingId, String returnId) =>
      db.transaction((txn) async {
        if (pendingId == returnId ||
            await _settings.record('pendingSyncedSetup').get(txn) !=
                pendingId) {
          throw StateError('The pending setup changed. Reopen the log.');
        }
        final target = await _families.record(returnId).get(txn);
        if (target == null) throw StateError('Choose an existing baby log.');
        // Keep the new log and any Drive reference intact. A later explicit
        // backup or sync resumes it without creating a duplicate.
        await _settings.record('activeFamily').put(txn, returnId);
        await _settings.record('pendingSyncedSetup').delete(txn);
        await _settings.record('onboardingStep').put(txn, 'tour');
        return Family.fromJson(target);
      });

  Future<String> onboardingStep() async =>
      await _settings.record('onboardingStep').get(db) as String? ?? 'tour';
  Future<void> saveOnboardingStep(String step) async =>
      _settings.record('onboardingStep').put(db, step);

  Future<bool> swipeDemoSeen() async =>
      await _settings.record('swipeDemoSeen').get(db) == true;
  Future<void> saveSwipeDemoSeen() async =>
      _settings.record('swipeDemoSeen').put(db, true);

  Future<bool> swipeActionsLearned() async =>
      await _settings.record('swipeActionsLearned').get(db) == true;
  Future<void> saveSwipeActionsLearned() async =>
      _settings.record('swipeActionsLearned').put(db, true);
  Future<DateTime?> swipeDemoLastShown() async {
    final value = await _settings.record('swipeDemoLastShown').get(db);
    return value is String ? DateTime.tryParse(value) : null;
  }

  Future<void> saveSwipeDemoLastShown(DateTime at) async => _settings
      .record('swipeDemoLastShown')
      .put(db, at.toUtc().toIso8601String());

  Future<String> themeMode() async {
    final saved = await _settings.record('themeMode').get(db);
    return ['system', 'light', 'dark'].contains(saved)
        ? saved as String
        : 'system';
  }

  Future<void> saveThemeMode(String mode) async =>
      _settings.record('themeMode').put(db, mode);

  Future<String> weightUnit() async =>
      await _settings.record('weightUnit').get(db) == 'lb' ? 'lb' : 'kg';
  Future<void> saveWeightUnit(String unit) async =>
      _settings.record('weightUnit').put(db, unit);

  Future<String> lengthUnit() async =>
      await _settings.record('lengthUnit').get(db) == 'in' ? 'in' : 'cm';
  Future<void> saveLengthUnit(String unit) async =>
      _settings.record('lengthUnit').put(db, unit);

  Future<String> temperatureUnit() async =>
      await _settings.record('temperatureUnit').get(db) == '°F' ? '°F' : '°C';
  Future<void> saveTemperatureUnit(String unit) async =>
      _settings.record('temperatureUnit').put(db, unit);

  Future<VolumeUnit> volumeUnit() async =>
      await _settings.record('volumeUnit').get(db) == 'oz'
      ? VolumeUnit.oz
      : VolumeUnit.ml;
  Future<void> saveVolumeUnit(VolumeUnit unit) async =>
      _settings.record('volumeUnit').put(db, unit.name);

  Future<List<String>> summaryMetrics() async {
    final saved = await _settings.record('summaryMetrics').get(db);
    const defaults = ['Nursing', 'Bottle', 'Diapers', 'Sleep'];
    const allowed = [...defaults, 'Pumped'];
    if (saved is! List) return defaults;
    final valid = saved
        .whereType<String>()
        .where(allowed.contains)
        .toSet()
        .toList();
    return valid.isEmpty ? defaults : valid;
  }

  Future<void> saveSummaryMetrics(List<String> choices) async =>
      _settings.record('summaryMetrics').put(db, List<String>.of(choices));

  Future<List<String>> quickLog() async =>
      validQuickLog(await _settings.record('quickLog').get(db));
  Future<void> saveQuickLog(List<String> choices) async =>
      _settings.record('quickLog').put(db, List<String>.of(choices));

  Future<bool> showElapsedInIcons() async =>
      await _settings.record('showElapsedInIcons').get(db) == true;
  Future<void> saveShowElapsedInIcons(bool value) async =>
      _settings.record('showElapsedInIcons').put(db, value);

  Future<String?> babyBackground(String babyId) async =>
      await _settings.record('babyBackground/$babyId').get(db) as String?;
  Future<void> saveBabyBackground(String babyId, String color) async =>
      _settings.record('babyBackground/$babyId').put(db, color);

  Future<List<Family>> families() async =>
      (await _families.find(db)).map((r) => Family.fromJson(r.value)).toList();
  static const maxBabies = 3;

  Future<void> updateFamilyIdentity(Family family) async {
    final previous = await _families.record(family.id).get(db);
    if (previous == null || previous['driveFileId'] != family.driveFileId) {
      return;
    }
    await _families.record(family.id).put(db, {
      ...previous,
      'ownerEmail': family.ownerEmail,
      'ownerName': family.ownerName,
      'driveShared': family.driveShared,
    });
  }

  Future<void> saveFamily(Family family) async {
    await db.transaction((txn) async {
      final existing = await _families.record(family.id).get(txn);
      if (existing == null && await _families.count(txn) >= maxBabies) {
        throw StateError('You can have up to three babies.');
      }
      await _families.record(family.id).put(txn, family.toJson());
      await _settings.record('activeFamily').put(txn, family.id);
    });
  }

  // Commit a verified download and selection together. Failed joins change nothing.
  Future<void> joinFamily(Family family, List<Feeding> feeds) async {
    await db.transaction((txn) async {
      final previous = await _families.record(family.id).get(txn);
      if (previous == null && await _families.count(txn) >= maxBabies) {
        throw StateError('You can have up to three babies.');
      }
      if (previous != null && previous['driveFileId'] != family.driveFileId) {
        throw StateError(
          'This baby is already on this device with different storage.',
        );
      }
      for (final feed in feeds) {
        if (feed.familyId != family.id) {
          throw const FormatException(
            'The shared history belongs to a different baby.',
          );
        }
        final key = '${family.id}/${feed.id}';
        final current = await _feeds.record(key).get(txn);
        if (current != null &&
            jsonEncode(Feeding.fromJson(current).originalRow) !=
                jsonEncode(feed.originalRow)) {
          throw const FormatException(
            'An entry has conflicting local and cloud contents. Both copies were retained.',
          );
        }
        if (current?['deleted'] == true && !feed.deleted) continue;
        await _feeds.record(key).put(txn, feed.acknowledged().toJson());
      }
      await _families.record(family.id).put(txn, family.toJson());
      await _settings.record('activeFamily').put(txn, family.id);
      await _settings.record('onboardingStep').put(txn, 'tour');
      await _settings
          .record('sync/${family.id}')
          .put(txn, DateTime.now().toUtc().toIso8601String());
    });
  }

  Future<Family> renameBaby(String id, String babyName) async {
    final name = babyName.trim();
    if (name.isEmpty) throw StateError('Enter your baby’s name.');
    return db.transaction((txn) async {
      final json = await _families.record(id).get(txn);
      if (json == null) {
        throw StateError('This baby is no longer on this device.');
      }
      final updated = Family.fromJson({...json, 'babyName': name});
      await _families.record(id).put(txn, updated.toJson());
      return updated;
    });
  }

  Future<void> deleteBaby(String id) async {
    await db.transaction((txn) async {
      await _feeds.delete(
        txn,
        finder: Finder(filter: Filter.equals('familyId', id)),
      );
      await _timers.delete(
        txn,
        finder: Finder(filter: Filter.equals('familyId', id)),
      );
      await _sessions.record(id).delete(txn);
      await _resumedNursing.record(id).delete(txn);
      await _imports.record(id).delete(txn);
      await _importReports.delete(
        txn,
        finder: Finder(filter: Filter.equals('familyId', id)),
      );
      if (await _settings.record('pendingSyncedSetup').get(txn) == id) {
        await _settings.record('pendingSyncedSetup').delete(txn);
      }
      await _settings.record('sync/$id').delete(txn);
      await _settings.record('babyBackground/$id').delete(txn);
      await _families.record(id).delete(txn);
      if (await _settings.record('activeFamily').get(txn) == id) {
        final remaining = await _families.find(txn);
        if (remaining.isEmpty) {
          await _settings.record('activeFamily').delete(txn);
        } else {
          await _settings.record('activeFamily').put(txn, remaining.first.key);
        }
      }
    });
  }

  Future<void> prepareCsvFamily(Family family) async {
    await db.transaction((txn) async {
      final records = await _feeds.find(
        txn,
        finder: Finder(filter: Filter.equals('familyId', family.id)),
      );
      for (final record in records) {
        await _feeds.record(record.key).put(txn, {
          ...record.value,
          'synced': false,
        });
      }
      await _families.record(family.id).put(txn, family.toJson());
      await _settings.record('activeFamily').put(txn, family.id);
      await _settings.record('sync/${family.id}').delete(txn);
    });
  }

  Future<void> selectFamily(String id) async =>
      _settings.record('activeFamily').put(db, id);
  Future<String?> activeFamilyId() async =>
      await _settings.record('activeFamily').get(db) as String?;
  Future<List<Feeding>> feeds(
    String familyId, {
    bool includeDeleted = false,
  }) async =>
      (await _feeds.find(
            db,
            finder: Finder(
              filter: Filter.equals('familyId', familyId),
              sortOrders: [SortOrder('at', false)],
            ),
          ))
          .map((r) => Feeding.fromJson(r.value))
          .where((f) => includeDeleted || !f.deleted)
          .toList();
  Future<void> add(Feeding feed) async =>
      _feeds.record('${feed.familyId}/${feed.id}').put(db, feed.toJson());
  Future<void> replace(Feeding original, Feeding replacement) async {
    await db.transaction((txn) async {
      final key = '${original.familyId}/${original.id}';
      final current = await _feeds.record(key).get(txn);
      if (current == null ||
          current['deleted'] == true ||
          jsonEncode(Feeding.fromJson(current).originalRow) !=
              jsonEncode(original.originalRow)) {
        throw StateError('This entry has changed. Reopen it before editing.');
      }
      if (replacement.familyId != original.familyId ||
          replacement.id == original.id) {
        throw StateError('Invalid replacement entry.');
      }
      await _feeds.record(key).put(txn, original.asDeleted().toJson());
      await _feeds
          .record('${replacement.familyId}/${replacement.id}')
          .put(txn, replacement.toJson());
    });
  }

  Future<void> merge(List<Feeding> feeds) async {
    await db.transaction((txn) async {
      for (final feed in feeds) {
        final current = await _feeds
            .record('${feed.familyId}/${feed.id}')
            .get(txn);
        if (current?['deleted'] == true && !feed.deleted) continue;
        await _feeds
            .record('${feed.familyId}/${feed.id}')
            .put(txn, feed.toJson());
      }
    });
  }

  Future<NursingSession?> nursingSession(String familyId) async {
    final json = await _sessions.record(familyId).get(db);
    return json == null ? null : NursingSession.fromJson(json);
  }

  Future<void> saveSession(NursingSession session) async =>
      _sessions.record(session.familyId).put(db, session.toJson());
  Future<void> reopenNursing(Feeding original, NursingSession session) async {
    await db.transaction((txn) async {
      final current = await _feeds
          .record('${original.familyId}/${original.id}')
          .get(txn);
      if (current == null ||
          current['deleted'] == true ||
          jsonEncode(Feeding.fromJson(current).originalRow) !=
              jsonEncode(original.originalRow)) {
        throw StateError('This entry has changed. Reopen it before editing.');
      }
      if (await _sessions.record(original.familyId).exists(txn)) {
        throw StateError('Finish the current nursing timer first.');
      }
      await _feeds
          .record('${original.familyId}/${original.id}')
          .put(txn, original.asDeleted().toJson());
      await _resumedNursing.record(original.familyId).put(txn, {
        'sessionId': session.id,
        'original': original.toJson(),
      });
      await _sessions.record(original.familyId).put(txn, session.toJson());
    });
  }

  Future<void> finishSession(NursingSession session, Feeding feed) async {
    await db.transaction((txn) async {
      final current = await _sessions.record(session.familyId).get(txn);
      if (current == null || current['id'] != session.id) return;
      await _feeds
          .record('${feed.familyId}/${feed.id}')
          .put(txn, feed.toJson());
      await _sessions.record(session.familyId).delete(txn);
      await _resumedNursing.record(session.familyId).delete(txn);
    });
  }

  Future<List<ActivityTimer>> activityTimers(String familyId) async =>
      (await _timers.find(
        db,
        finder: Finder(filter: Filter.equals('familyId', familyId)),
      )).map((r) => ActivityTimer.fromJson(r.value)).toList();

  Future<void> startTimer(ActivityTimer timer) async {
    if (!['sleep', 'pumping'].contains(timer.method)) {
      throw const FormatException('Unknown timer.');
    }
    await db.transaction((txn) async {
      final key = '${timer.familyId}/${timer.method}';
      if (await _timers.record(key).exists(txn)) return;
      await _timers.record(key).put(txn, timer.toJson());
    });
  }

  Future<void> changePumpingTimer(
    ActivityTimer previous,
    ActivityTimer next,
  ) async {
    await db.transaction((txn) async {
      final key = '${previous.familyId}/pumping';
      final raw = await _timers.record(key).get(txn);
      if (raw == null ||
          raw['id'] != previous.id ||
          (raw['revision'] ?? 0) != previous.revision) {
        throw StateError('This timer has changed. Reopen its controls.');
      }
      await _timers.record(key).put(txn, next.toJson());
    });
  }

  Future<void> discardNursing(NursingSession session) async {
    await db.transaction((txn) async {
      final current = await _sessions.record(session.familyId).get(txn);
      if (current == null ||
          current['id'] != session.id ||
          (current['revision'] ?? 0) != session.revision) {
        throw StateError('This session has changed. Reopen its controls.');
      }
      final resumed = await _resumedNursing.record(session.familyId).get(txn);
      if (resumed?['sessionId'] == session.id) {
        // The old ID may already be tombstoned in Drive. Restore the saved
        // portion under the continuation ID rather than resurrecting that ID.
        final original = Map<String, Object?>.from(resumed!['original'] as Map);
        await _feeds.record('${session.familyId}/${session.id}').put(txn, {
          ...original,
          'id': session.id,
          'synced': false,
        });
      }
      await _sessions.record(session.familyId).delete(txn);
      await _resumedNursing.record(session.familyId).delete(txn);
    });
  }

  Future<void> finishTimer(ActivityTimer timer, Feeding activity) async {
    validateActivity(activity, timer.familyId);
    if (activity.id != timer.id ||
        activity.method != timer.method ||
        activity.at != timer.startedAt) {
      throw const FormatException('The activity does not match this timer.');
    }
    await db.transaction((txn) async {
      final key = '${timer.familyId}/${timer.method}';
      final current = await _timers.record(key).get(txn);
      if (current == null) return;
      if (current['id'] != timer.id) {
        throw StateError('This timer has changed. Reopen it to finish.');
      }
      await _feeds
          .record('${activity.familyId}/${activity.id}')
          .put(txn, activity.toJson());
      await _timers.record(key).delete(txn);
    });
  }

  Future<void> discardTimer(ActivityTimer timer) async {
    await db.transaction((txn) async {
      final key = '${timer.familyId}/${timer.method}';
      final current = await _timers.record(key).get(txn);
      if (current == null || current['id'] != timer.id) {
        throw StateError(
          'This timer has changed. Reopen it to review the current session.',
        );
      }
      await _timers.record(key).delete(txn);
    });
  }

  final _imports = stringMapStoreFactory.store('importReceipts');
  Future<bool> canUndoImport(String familyId) async =>
      await _imports.record(familyId).exists(db);

  final _importReports = stringMapStoreFactory.store('importReports');

  Future<List<Map<String, Object?>>> importReports(String familyId) async =>
      (await _importReports.find(
        db,
        finder: Finder(
          filter: Filter.equals('familyId', familyId),
          sortOrders: [SortOrder('createdAt', false)],
        ),
      )).map((r) => r.value).toList();

  Future<void> applyImport(ImportPlan plan) async {
    if (plan.needsConsent) {
      throw StateError('Review the excluded entries before importing.');
    }
    await db.transaction((txn) async {
      final current = (await _feeds.find(
        txn,
        finder: Finder(filter: Filter.equals('familyId', plan.familyId)),
      )).map((r) => Feeding.fromJson(r.value)).toList();
      if (snapshotFingerprint(current) != snapshotFingerprint(plan.before)) {
        throw StateError(
          'History changed after preview. Preview the import again.',
        );
      }
      if (plan.additions.isEmpty && plan.removals.isEmpty) return;
      final changes = [
        ...plan.additions,
        ...plan.removals.map((f) => f.asDeleted()),
      ];
      final reportId = newId.v4();
      await _importReports.record(reportId).put(txn, {
        'familyId': plan.familyId,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'label': plan.label,
        'added': plan.activityCount,
        'duplicates': plan.duplicates,
        'removed': plan.removals.length,
        'issues': plan.issues.map((i) => i.toJson()).toList(),
        'recordIds': plan.additions.map((r) => r.id).toList(),
      });
      // Save the full prior state and expected mutations in the same transaction.
      await _imports.record(plan.familyId).put(txn, {
        'before': current.map((f) => f.toJson()).toList(),
        'changes': changes.map((f) => f.toJson()).toList(),
        'label': plan.label,
        'reportId': reportId,
      });
      for (final f in changes) {
        await _feeds.record('${f.familyId}/${f.id}').put(txn, f.toJson());
      }
    });
  }

  Future<void> undoImport(String familyId) async {
    await db.transaction((txn) async {
      final receipt = await _imports.record(familyId).get(txn);
      if (receipt == null) throw StateError('No import to undo.');
      final before = (receipt['before'] as List)
          .map((j) => Feeding.fromJson(Map<String, Object?>.from(j as Map)))
          .toList();
      final changes = (receipt['changes'] as List)
          .map((j) => Feeding.fromJson(Map<String, Object?>.from(j as Map)))
          .toList();
      for (final change in changes) {
        final json = await _feeds.record('$familyId/${change.id}').get(txn);
        if (json == null ||
            recordFingerprint(Feeding.fromJson(json)) !=
                recordFingerprint(change)) {
          throw StateError(
            'An imported entry has since changed. Undo would overwrite that change.',
          );
        }
      }
      for (final change in changes) {
        if (!change.deleted) {
          await _feeds
              .record('$familyId/${change.id}')
              .put(txn, change.asDeleted().toJson());
        }
        final prior = before
            .where((f) => f.id == change.id && !f.deleted)
            .firstOrNull;
        if (prior != null && change.deleted) {
          // Restore as a new entry; never resurrect an ID already deleted on another device.
          final restored = Feeding.fromJson({
            ...prior.toJson(),
            'id': newId.v4(),
            'synced': false,
          });
          await _feeds
              .record('$familyId/${restored.id}')
              .put(txn, restored.toJson());
        }
      }
      final reportId = receipt['reportId'] as String?;
      if (reportId != null) {
        await _importReports.record(reportId).update(txn, {'undone': true});
      }
      await _imports.record(familyId).delete(txn);
    });
  }

  Future<DateTime?> lastSync(String familyId) async {
    final value = await _settings.record('sync/$familyId').get(db) as String?;
    return value == null ? null : DateTime.parse(value);
  }

  Future<void> setLastSync(String familyId, DateTime time) async => _settings
      .record('sync/$familyId')
      .put(db, time.toUtc().toIso8601String());
  Future<String> export(Family family) async =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'little-log',
        'schemaVersion': 4,
        'family': family.toJson(),
        'feedings': (await feeds(
          family.id,
        )).where((f) => f.isFeeding).map((f) => f.toJson()).toList(),
        'diapers': (await feeds(
          family.id,
        )).where((f) => f.isDiaper).map((f) => f.toJson()).toList(),
        'activities': (await feeds(family.id))
            .where((f) => !f.isFeeding && !f.isDiaper)
            .map((f) => f.toJson())
            .toList(),
        'activeTimers': (await activityTimers(
          family.id,
        )).map((t) => t.toJson()).toList(),
        'activeNursing': (await nursingSession(family.id))?.toJson(),
      });
}
