import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await _initializeLocal();
    await _initializeFirebase();

    _initialized = true;
  }

  Future<void> _initializeLocal() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      linux:
          LinuxInitializationSettings(defaultActionName: 'Open notification'),
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    if (Platform.isAndroid) {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.createNotificationChannel(_episodeChannel);
      await androidPlugin?.createNotificationChannel(_reminderChannel);
    }
  }

  Future<void> _initializeFirebase() async {
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      _handleNotificationPayload(payload);
    }
  }

  void _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await showNotification(
      title: notification.title ?? 'AniVerse',
      body: notification.body ?? '',
      payload: message.data.toString(),
    );
  }

  void _handleMessageTap(RemoteMessage message) {
    _handleNotificationPayload(message.data.toString());
  }

  void _handleNotificationPayload(String payload) {}

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.notification.isDenied) {
        final status = await Permission.notification.request();
        return status.isGranted;
      }
      return true;
    } else if (Platform.isIOS) {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    }
    return true;
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'episode_alerts',
      'Episode Alerts',
      channelDescription: 'Notifications for new episode releases',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(id, title, body, details, payload: payload);
  }

  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  Future<int> getPendingNotificationCount() async {
    final pending = await _localNotifications.pendingNotificationRequests();
    return pending.length;
  }

  static const AndroidNotificationChannel _episodeChannel =
      AndroidNotificationChannel(
    'episode_alerts',
    'Episode Alerts',
    description: 'Notifications for new episode releases',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _reminderChannel =
      AndroidNotificationChannel(
    'watch_reminders',
    'Watch Reminders',
    description: 'Reminders to continue watching',
    importance: Importance.defaultImportance,
  );
}
