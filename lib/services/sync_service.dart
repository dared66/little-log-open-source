import 'dart:convert';
import '../models.dart';
import '../storage/repository.dart';
import 'family_cloud.dart';

class SyncService {
  SyncService(this.repository, this.cloud);
  final Repository repository;
  final FamilyCloud cloud;
  bool _running = false;

  Future<int> sync(Family family, {required String accountId}) async {
    if (family.isLocal || family.accountId != accountId) {
      throw StateError(
        'Connect the Google account linked to this baby before syncing.',
      );
    }
    if (_running) return 0;
    _running = true;
    try {
      // Pull first: if an earlier append succeeded but its response was lost,
      // acknowledge those IDs locally instead of uploading them again.
      final remote = await cloud.readFeeds(family);
      final local = {
        for (final f in await repository.feeds(family.id, includeDeleted: true))
          f.id: f,
      };
      final updates = <Feeding>[];
      for (final feed in remote.feeds) {
        final existing = local[feed.id];
        if (existing != null &&
            jsonEncode(existing.originalRow) != jsonEncode(feed.originalRow)) {
          throw const FormatException(
            'An entry has conflicting local and cloud contents. Both copies were retained.',
          );
        }
        // The immutable payload was checked above. Unchanged polls need no
        // database writes; acknowledgments and tombstones still pass through
        // Repository.merge, which prevents resurrection of local deletions.
        if (existing == null ||
            existing.synced != feed.synced ||
            existing.deleted != feed.deleted) {
          updates.add(feed);
        }
      }
      if (updates.isNotEmpty) await repository.merge(updates);
      if (remote.needsCompatibilityRewrite) {
        // Repair already-shared build-56 rows even when this device has no
        // pending entries. The cloud uses its normal conditional merge/retry.
        await cloud.appendFeeds(family, []);
      }
      final pending = (await repository.feeds(
        family.id,
        includeDeleted: true,
      )).where((f) => !f.synced).toList();
      if (pending.isNotEmpty) {
        // Drive conditionally replaces one size-limited CSV, not individual
        // rows. Splitting the outbox repeats the entire file transfer for every
        // batch. Acknowledge only after the cloud verifies the complete upload.
        await cloud.appendFeeds(family, pending);
        await repository.merge(pending.map((f) => f.acknowledged()).toList());
      }
      await repository.setLastSync(family.id, DateTime.now());
      return remote.skipped;
    } finally {
      _running = false;
    }
  }
}
