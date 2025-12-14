import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anime_model.dart';
import '../models/episode_tracker_model.dart';
import '../providers/anime_provider.dart';
import '../providers/lists_provider.dart';
import 'notification_storage.dart';
import 'notification_service.dart';

class EpisodeTrackerService {
  final Ref ref;

  EpisodeTrackerService(this.ref);

  Future<void> checkForNewEpisodes() async {
    final watchlist = ref.read(watchlistProvider);
    final settings = await NotificationStorage.getSettings();

    if (!settings.newEpisodeAlerts || watchlist.isEmpty) {
      return;
    }

    for (final animeId in watchlist) {
      await _checkSingleAnime(animeId);
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _checkSingleAnime(String animeId) async {
    try {
      final animeDetails = await ref.read(animeDetailsProvider(animeId).future);

      if (animeDetails == null) return;

      final currentEpisodeCount = _getEpisodeCount(animeDetails);
      final tracker = NotificationStorage.getEpisodeTracker(animeId);

      if (tracker == null) {
        await NotificationStorage.saveEpisodeTracker(
          EpisodeTracker(
            animeId: animeId,
            animeTitle: animeDetails['name'] ?? 'Unknown',
            lastKnownEpisodeCount: currentEpisodeCount,
            lastChecked: DateTime.now(),
            animeImage: animeDetails['thumbnail'] ?? animeDetails['image'],
          ),
        );
        return;
      }

      if (currentEpisodeCount > tracker.lastKnownEpisodeCount) {
        final newEpisodes = currentEpisodeCount - tracker.lastKnownEpisodeCount;
        await _showNewEpisodeNotification(
          animeTitle: tracker.animeTitle,
          episodeNumber: currentEpisodeCount,
          newEpisodesCount: newEpisodes,
          animeId: animeId,
        );

        tracker.lastKnownEpisodeCount = currentEpisodeCount;
        tracker.lastChecked = DateTime.now();
        await NotificationStorage.saveEpisodeTracker(tracker);
      } else {
        tracker.lastChecked = DateTime.now();
        await NotificationStorage.saveEpisodeTracker(tracker);
      }
    } catch (e) {}
  }

  int _getEpisodeCount(Map<String, dynamic> animeDetails) {
    final availableEpisodes = animeDetails['availableEpisodes'];
    if (availableEpisodes is Map) {
      final sub = availableEpisodes['sub'] ?? 0;
      final dub = availableEpisodes['dub'] ?? 0;
      return sub > dub ? sub : dub;
    }
    return 0;
  }

  Future<void> _showNewEpisodeNotification({
    required String animeTitle,
    required int episodeNumber,
    required int newEpisodesCount,
    required String animeId,
  }) async {
    final notificationService = NotificationService();
    final title = newEpisodesCount == 1
        ? 'New episode of $animeTitle!'
        : '$newEpisodesCount new episodes of $animeTitle!';

    final body = newEpisodesCount == 1
        ? 'Episode $episodeNumber is now available'
        : 'Episodes ${episodeNumber - newEpisodesCount + 1}-$episodeNumber are now available';

    await notificationService.showNotification(
      title: title,
      body: body,
      payload: 'anime:$animeId',
      id: animeId.hashCode,
    );
  }

  Future<void> addToTracking(String animeId, String animeTitle,
      {String? animeImage}) async {
    try {
      final animeDetails = await ref.read(animeDetailsProvider(animeId).future);
      if (animeDetails == null) return;

      final episodeCount = _getEpisodeCount(animeDetails);

      await NotificationStorage.saveEpisodeTracker(
        EpisodeTracker(
          animeId: animeId,
          animeTitle: animeTitle,
          lastKnownEpisodeCount: episodeCount,
          lastChecked: DateTime.now(),
          animeImage:
              animeImage ?? animeDetails['thumbnail'] ?? animeDetails['image'],
        ),
      );
    } catch (e) {}
  }

  Future<void> removeFromTracking(String animeId) async {
    await NotificationStorage.deleteEpisodeTracker(animeId);
  }
}

final episodeTrackerServiceProvider =
    Provider((ref) => EpisodeTrackerService(ref));
