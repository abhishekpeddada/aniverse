import 'package:hive/hive.dart';

part 'notification_settings_model.g.dart';

@HiveType(typeId: 5)
class NotificationSettings extends HiveObject {
  @HiveField(0)
  bool newEpisodeAlerts;

  @HiveField(1)
  bool watchReminders;

  @HiveField(2)
  bool appUpdates;

  @HiveField(3)
  int reminderHours;

  @HiveField(4)
  bool sound;

  @HiveField(5)
  bool vibration;

  NotificationSettings({
    this.newEpisodeAlerts = false,
    this.watchReminders = false,
    this.appUpdates = false,
    this.reminderHours = 2,
    this.sound = true,
    this.vibration = true,
  });

  NotificationSettings copyWith({
    bool? newEpisodeAlerts,
    bool? watchReminders,
    bool? appUpdates,
    int? reminderHours,
    bool? sound,
    bool? vibration,
  }) {
    return NotificationSettings(
      newEpisodeAlerts: newEpisodeAlerts ?? this.newEpisodeAlerts,
      watchReminders: watchReminders ?? this.watchReminders,
      appUpdates: appUpdates ?? this.appUpdates,
      reminderHours: reminderHours ?? this.reminderHours,
      sound: sound ?? this.sound,
      vibration: vibration ?? this.vibration,
    );
  }
}
