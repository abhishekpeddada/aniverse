import 'package:hive/hive.dart';
import '../models/notification_settings_model.dart';
import '../models/episode_tracker_model.dart';

class NotificationStorage {
  static const String _settingsBox = 'notification_settings';
  static const String _episodeTrackerBox = 'episode_tracker';
  static const String _settingsKey = 'settings';

  static Future<void> initialize() async {
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(NotificationSettingsAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(EpisodeTrackerAdapter());
    }

    await Hive.openBox<NotificationSettings>(_settingsBox);
    await Hive.openBox<EpisodeTracker>(_episodeTrackerBox);
  }

  static Box<NotificationSettings> get _settings =>
      Hive.box<NotificationSettings>(_settingsBox);

  static Box<EpisodeTracker> get _tracker =>
      Hive.box<EpisodeTracker>(_episodeTrackerBox);

  static Future<NotificationSettings> getSettings() async {
    var settings = _settings.get(_settingsKey);
    if (settings == null) {
      settings = NotificationSettings();
      await _settings.put(_settingsKey, settings);
    }
    return settings;
  }

  static Future<void> saveSettings(NotificationSettings settings) async {
    await _settings.put(_settingsKey, settings);
  }

  static Future<void> saveEpisodeTracker(EpisodeTracker tracker) async {
    await _tracker.put(tracker.animeId, tracker);
  }

  static EpisodeTracker? getEpisodeTracker(String animeId) {
    return _tracker.get(animeId);
  }

  static Future<void> deleteEpisodeTracker(String animeId) async {
    await _tracker.delete(animeId);
  }

  static List<EpisodeTracker> getAllTrackers() {
    return _tracker.values.toList();
  }

  static Future<void> clearAllTrackers() async {
    await _tracker.clear();
  }
}
