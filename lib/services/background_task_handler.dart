import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:path_provider/path_provider.dart';
import '../models/anime_model.dart';
import '../models/episode_tracker_model.dart';
import '../models/notification_settings_model.dart';
import '../models/watch_history_model.dart';
import 'notification_service.dart';
import 'anime_api_service.dart';
import 'new_episode_rules.dart';

const String episodeCheckTask = 'episode_check_task';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('🔔 Background task started: $task');

      WidgetsFlutterBinding.ensureInitialized();
      final appDir = await getApplicationDocumentsDirectory();
      await Hive.initFlutter(appDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(WatchHistoryAdapter());
      }
      if (!Hive.isAdapterRegistered(5)) {
        Hive.registerAdapter(NotificationSettingsAdapter());
      }
      if (!Hive.isAdapterRegistered(6)) {
        Hive.registerAdapter(EpisodeTrackerAdapter());
      }

      final settingsBox = await Hive.openBox<NotificationSettings>('notification_settings');
      final settings = settingsBox.get('settings') ?? NotificationSettings();
      if (!settings.newEpisodeAlerts) {
        debugPrint('🔔 New episode alerts are off, skipping check');
        await Hive.close();
        return true;
      }

      final trackerBox = await Hive.openBox<EpisodeTracker>('episode_tracker');
      final favorites = await Hive.openBox<String>('favorites');
      final watchlist = await Hive.openBox<String>('watchlist');
      final history = await Hive.openBox<WatchHistory>('history');

      // Titles from history, so most notifications need no extra request.
      final historyTitles = <String, String>{
        for (final entry in history.values) entry.animeId: entry.animeTitle,
      };
      final animeIds = NewEpisodeRules.animeToCheck(
        favorites: favorites.values,
        watchlist: watchlist.values,
        history: history.values
            .map((h) => (animeId: h.animeId, lastWatched: h.lastWatched)),
        now: DateTime.now(),
      );
      debugPrint('🔔 Checking ${animeIds.length} anime for new episodes');

      final notificationService = NotificationService();
      await notificationService.initialize();
      final animeService = AnimeApiService();

      for (final animeId in animeIds) {
        try {
          await _checkAnime(
            animeId: animeId,
            knownTitle: historyTitles[animeId],
            trackerBox: trackerBox,
            animeService: animeService,
            notificationService: notificationService,
          );
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          debugPrint('🔔 Error checking $animeId: $e');
        }
      }

      await Hive.close();
      debugPrint('🔔 Background task completed');
      return true;
    } catch (e) {
      debugPrint('🔔 Background task error: $e');
      return false;
    }
  });
}

Future<void> _checkAnime({
  required String animeId,
  required String? knownTitle,
  required Box<EpisodeTracker> trackerBox,
  required AnimeApiService animeService,
  required NotificationService notificationService,
}) async {
  // A failed lookup is skipped rather than treated as zero episodes.
  final count = await animeService.getEpisodeCount(animeId);
  if (count == null || count <= 0) return;

  final tracker = trackerBox.get(animeId);
  final decision = NewEpisodeRules.evaluate(
    knownCount: tracker?.lastKnownEpisodeCount,
    currentCount: count,
  );

  var title = tracker?.animeTitle ?? knownTitle;
  if (decision.notify && (title == null || title == 'Unknown')) {
    final info = await animeService.getAnimeInfo(animeId);
    title = (info?['anime'] as Anime?)?.title;
  }

  // Save the new baseline before notifying: if anything fails after this,
  // the episode is never announced twice.
  await trackerBox.put(
    animeId,
    EpisodeTracker(
      animeId: animeId,
      animeTitle: title ?? 'Unknown',
      lastKnownEpisodeCount: decision.baseline,
      lastChecked: DateTime.now(),
      animeImage: tracker?.animeImage,
    ),
  );

  if (!decision.notify) return;

  final message = NewEpisodeRules.message(
    animeTitle: title ?? 'an anime you follow',
    episodeCount: count,
    newEpisodes: decision.newEpisodes,
  );
  await notificationService.showNotification(
    title: message.title,
    body: message.body,
    payload: 'anime:$animeId',
    id: NewEpisodeRules.notificationId(animeId, count),
  );
  debugPrint('🔔 Notified ${decision.newEpisodes} new episode(s) of $title');
}
