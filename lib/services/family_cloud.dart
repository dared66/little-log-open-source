import '../models.dart';

class RemoteHistory {
  RemoteHistory(
    this.feeds, {
    this.skipped = 0,
    this.needsCompatibilityRewrite = false,
  });
  final List<Feeding> feeds;
  final int skipped;
  final bool needsCompatibilityRewrite;
}

abstract interface class FamilyCloud {
  Future<RemoteHistory> readFeeds(Family family);
  Future<void> appendFeeds(Family family, List<Feeding> feeds);
}
