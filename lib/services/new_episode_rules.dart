/// Rules for new-episode notifications, kept free of I/O so they can be
/// tested: which anime to check, and whether a count change should notify.
class NewEpisodeRules {
  /// Watch history entries older than this aren't checked, so long-finished
  /// shows don't cost a request every run.
  static const historyWindow = Duration(days: 90);

  /// The anime to check: favorites, watchlist and recently watched history,
  /// each once. Raiden (adult) entries have no episode feed and are skipped.
  static List<String> animeToCheck({
    required Iterable<String> favorites,
    required Iterable<String> watchlist,
    required Iterable<({String animeId, DateTime lastWatched})> history,
    required DateTime now,
  }) {
    final ids = <String>{
      ...favorites,
      ...watchlist,
      for (final entry in history)
        if (now.difference(entry.lastWatched) <= historyWindow) entry.animeId,
    };
    return ids.where((id) => id.isNotEmpty && !id.startsWith('raiden_')).toList();
  }

  /// Decides what to do with a fresh episode count for one anime.
  ///
  /// - First sighting: record a baseline and stay quiet, so adding a show
  ///   doesn't announce every episode it already has.
  /// - More episodes than the baseline: notify for the new ones.
  /// - Fewer (an API hiccup): stay quiet and keep the higher baseline, so the
  ///   same episode can't be announced twice when the count recovers.
  static ({bool notify, int baseline, int newEpisodes}) evaluate({
    required int? knownCount,
    required int currentCount,
  }) {
    if (knownCount == null) {
      return (notify: false, baseline: currentCount, newEpisodes: 0);
    }
    if (currentCount > knownCount) {
      return (
        notify: true,
        baseline: currentCount,
        newEpisodes: currentCount - knownCount,
      );
    }
    return (notify: false, baseline: knownCount, newEpisodes: 0);
  }

  /// One notification id per anime and episode count: if a run is repeated
  /// (a periodic and an immediate check overlapping), Android replaces the
  /// notification instead of showing it twice.
  ///
  /// Uses FNV-1a rather than `hashCode`, which isn't guaranteed stable across
  /// runs, and background checks run in separate processes.
  static int notificationId(String animeId, int episodeCount) {
    var hash = 0x811c9dc5;
    for (final unit in '$animeId:$episodeCount'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  static ({String title, String body}) message({
    required String animeTitle,
    required int episodeCount,
    required int newEpisodes,
  }) {
    if (newEpisodes == 1) {
      return (
        title: 'New episode of $animeTitle!',
        body: 'Episode $episodeCount is now available',
      );
    }
    return (
      title: '$newEpisodes new episodes of $animeTitle!',
      body: 'Episodes ${episodeCount - newEpisodes + 1}-$episodeCount are now available',
    );
  }
}
