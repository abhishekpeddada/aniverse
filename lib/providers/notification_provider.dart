import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_settings_model.dart';
import '../services/notification_storage.dart';
import '../services/notification_service.dart';

class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  NotificationSettingsNotifier() : super(NotificationSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await NotificationStorage.getSettings();
    state = settings;
  }

  Future<void> updateSettings(NotificationSettings settings) async {
    await NotificationStorage.saveSettings(settings);
    state = settings;
  }

  Future<void> toggleNewEpisodeAlerts(bool value) async {
    final newSettings = state.copyWith(newEpisodeAlerts: value);
    await updateSettings(newSettings);
  }

  Future<void> toggleWatchReminders(bool value) async {
    final newSettings = state.copyWith(watchReminders: value);
    await updateSettings(newSettings);
  }

  Future<void> toggleAppUpdates(bool value) async {
    final newSettings = state.copyWith(appUpdates: value);
    await updateSettings(newSettings);
  }

  Future<void> setReminderHours(int hours) async {
    final newSettings = state.copyWith(reminderHours: hours);
    await updateSettings(newSettings);
  }

  Future<void> toggleSound(bool value) async {
    final newSettings = state.copyWith(sound: value);
    await updateSettings(newSettings);
  }

  Future<void> toggleVibration(bool value) async {
    final newSettings = state.copyWith(vibration: value);
    await updateSettings(newSettings);
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
  (ref) => NotificationSettingsNotifier(),
);

final pendingNotificationsProvider = FutureProvider<int>((ref) async {
  final notificationService = NotificationService();
  return await notificationService.getPendingNotificationCount();
});

final lastEpisodeCheckProvider = StateProvider<DateTime?>((ref) => null);
