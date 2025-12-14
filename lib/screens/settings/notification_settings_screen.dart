import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/notification_provider.dart';
import '../../services/notification_service.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Choose what notifications you want to receive',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          SwitchListTile(
            title: const Text('New Episode Alerts'),
            subtitle:
                const Text('Notify when watchlist anime get new episodes'),
            value: settings.newEpisodeAlerts,
            onChanged: (value) {
              ref
                  .read(notificationSettingsProvider.notifier)
                  .toggleNewEpisodeAlerts(value);
            },
          ),
          SwitchListTile(
            title: const Text('Watch Reminders'),
            subtitle: const Text('Remind you to continue watching'),
            value: settings.watchReminders,
            onChanged: (value) {
              ref
                  .read(notificationSettingsProvider.notifier)
                  .toggleWatchReminders(value);
            },
          ),
          SwitchListTile(
            title: const Text('App Updates'),
            subtitle: const Text('Notify about new features and updates'),
            value: settings.appUpdates,
            onChanged: (value) {
              ref
                  .read(notificationSettingsProvider.notifier)
                  .toggleAppUpdates(value);
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Notification Preferences',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ListTile(
            title: const Text('Reminder Timing'),
            subtitle:
                Text('${settings.reminderHours} hours before episode airs'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: settings.reminderHours.toDouble(),
                min: 1,
                max: 24,
                divisions: 23,
                label: '${settings.reminderHours}h',
                onChanged: (value) {
                  ref
                      .read(notificationSettingsProvider.notifier)
                      .setReminderHours(value.toInt());
                },
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Sound'),
            subtitle: const Text('Play sound with notifications'),
            value: settings.sound,
            onChanged: (value) {
              ref
                  .read(notificationSettingsProvider.notifier)
                  .toggleSound(value);
            },
          ),
          SwitchListTile(
            title: const Text('Vibration'),
            subtitle: const Text('Vibrate on notification'),
            value: settings.vibration,
            onChanged: (value) {
              ref
                  .read(notificationSettingsProvider.notifier)
                  .toggleVibration(value);
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Test Notification'),
            subtitle: const Text('Send a test notification'),
            trailing: ElevatedButton(
              onPressed: () async {
                await NotificationService().showNotification(
                  title: 'Test Notification',
                  body: 'Notifications are working correctly!',
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Test notification sent')),
                  );
                }
              },
              child: const Text('Test'),
            ),
          ),
          ListTile(
            title: const Text('Clear All Notifications'),
            subtitle: const Text('Remove all pending notifications'),
            trailing: ElevatedButton(
              onPressed: () async {
                await NotificationService().cancelAllNotifications();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All notifications cleared')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Clear'),
            ),
          ),
        ],
      ),
    );
  }
}
