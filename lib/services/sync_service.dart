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
      for (final feed in remote.feeds) {
        final existing = local[feed.id];
        if (existing != null &&
            jsonEncode(existing.originalRow) != jsonEncode(feed.originalRow)) {
          throw const FormatException(
            'An entry has conflicting local and cloud contents. Both copies were retained.',
          );
        }
      }
      await repository.merge(remote.feeds);
      if (remote.needsCompatibilityRewrite) {
        // Repair already-shared build-56 rows even when this device has no
        // pending entries. The cloud uses its normal conditional merge/retry.
        await cloud.appendFeeds(family, []);
      }
      final pending = (await repository.feeds(
        family.id,
        includeDeleted: true,
      )).where((f) => !f.synced).toList();
      for (var start = 0; start < pending.length; start += 100) {
        final end = (start + 100).clamp(0, pending.length);
        final batch = pending.sublist(start, end);
        await cloud.appendFeeds(family, batch);
        await repository.merge(batch.map((f) => f.acknowledged()).toList());
      }
      await repository.setLastSync(family.id, DateTime.now());
      return remote.skipped;
    } finally {
      _running = false;
    }
  }
}
