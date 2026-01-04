import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:path_provider/path_provider.dart';
import '../models/episode_tracker_model.dart';
import '../models/notification_settings_model.dart';
import 'notification_service.dart';
import 'anime_api_service.dart';

const String episodeCheckTask = 'episode_check_task';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('🔔 Background task started: $task');

      WidgetsFlutterBinding.ensureInitialized();
      final appDir = await getApplicationDocumentsDirectory();
      await Hive.initFlutter(appDir.path);
      if (!Hive.isAdapterRegistered(5)) {
        Hive.registerAdapter(NotificationSettingsAdapter());
      }
      if (!Hive.isAdapterRegistered(6)) {
        Hive.registerAdapter(EpisodeTrackerAdapter());
      }

      final settingsBox = await Hive.openBox<NotificationSettings>('notification_settings');
      final trackerBox = await Hive.openBox<EpisodeTracker>('episode_tracker');

      final settings = settingsBox.get('settings');
      if (settings == null || !settings.newEpisodeAlerts) {
        debugPrint('🔔 Notifications disabled, skipping check');
        await Hive.close();
        return true;
      }

      final trackers = trackerBox.values.toList();
      if (trackers.isEmpty) {
        debugPrint('🔔 No anime being tracked');
        await Hive.close();
        return true;
      }

      final notificationService = NotificationService();
      await notificationService.initialize();

      final animeService = AnimeApiService();

      for (final tracker in trackers) {
        try {
          debugPrint('🔔 Checking: ${tracker.animeTitle}');
          
          final animeDetails = await animeService.getAnimeInfo(tracker.animeId);
          if (animeDetails == null) continue;

          final currentEpisodeCount = _getEpisodeCount(animeDetails);

          if (currentEpisodeCount > tracker.lastKnownEpisodeCount) {
            final newEpisodes = currentEpisodeCount - tracker.lastKnownEpisodeCount;
            
            final title = newEpisodes == 1
                ? 'New episode of ${tracker.animeTitle}!'
                : '$newEpisodes new episodes of ${tracker.animeTitle}!';

            final body = newEpisodes == 1
                ? 'Episode $currentEpisodeCount is now available'
                : 'Episodes ${currentEpisodeCount - newEpisodes + 1}-$currentEpisodeCount are now available';

            await notificationService.showNotification(
              title: title,
              body: body,
              payload: 'anime:${tracker.animeId}',
              id: tracker.animeId.hashCode,
            );

            tracker.lastKnownEpisodeCount = currentEpisodeCount;
            tracker.lastChecked = DateTime.now();
            await tracker.save();

            debugPrint('🔔 Found new episodes for ${tracker.animeTitle}!');
          }

          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          debugPrint('🔔 Error checking ${tracker.animeTitle}: $e');
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

int _getEpisodeCount(Map<String, dynamic> animeDetails) {
  final availableEpisodes = animeDetails['availableEpisodes'];
  if (availableEpisodes is Map) {
    final sub = availableEpisodes['sub'] ?? 0;
    final dub = availableEpisodes['dub'] ?? 0;
    return sub > dub ? sub : dub;
  }
  return 0;
}
