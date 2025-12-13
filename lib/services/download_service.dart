import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../models/download_model.dart';
import 'download_storage_service.dart';

class DownloadService {
  final Dio _dio;
  final DownloadStorageService _storage;
  final FlutterLocalNotificationsPlugin _notifications;
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, StreamController<double>> _progressControllers = {};
  bool _isForegroundServiceRunning = false;

  DownloadService({
    required Dio dio,
    required DownloadStorageService storage,
    required FlutterLocalNotificationsPlugin notifications,
  })  : _dio = dio,
        _storage = storage,
        _notifications = notifications {
    _initForegroundTask();
  }

  Future<void> initNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);

    const androidChannel = AndroidNotificationChannel(
      'downloads',
      'Downloads',
      description: 'Episode download progress',
      importance: Importance.low,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'download_foreground',
        channelName: 'Download Service',
        channelDescription: 'Keeps downloads running in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _startForegroundService() async {
    if (_isForegroundServiceRunning) return;

    final hasPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (hasPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Downloading episodes',
      notificationText: 'Downloads in progress',
      callback: null,
    );

    _isForegroundServiceRunning = true;
  }

  Future<void> _stopForegroundService() async {
    if (!_isForegroundServiceRunning) return;

    final activeDownloads = _storage.getActiveDownloads();
    if (activeDownloads.isEmpty) {
      await FlutterForegroundTask.stopService();
      _isForegroundServiceRunning = false;
    }
  }

  Future<String> _getDownloadPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory('${directory.path}/downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir.path;
  }

  Stream<double> getProgressStream(String downloadId) {
    if (!_progressControllers.containsKey(downloadId)) {
      _progressControllers[downloadId] = StreamController<double>.broadcast();
    }
    return _progressControllers[downloadId]!.stream;
  }

  Future<Download> startDownload({
    required String animeId,
    required String animeTitle,
    String? animeImage,
    required String episodeId,
    required int episodeNumber,
    String? episodeTitle,
    required String downloadUrl,
    required String quality,
  }) async {
    final downloadId = '${episodeId}_$quality';

    final existingDownload = _storage.getDownload(downloadId);
    if (existingDownload != null &&
        existingDownload.status == DownloadStatus.completed) {
      return existingDownload;
    }

    final download = Download(
      id: downloadId,
      animeId: animeId,
      animeTitle: animeTitle,
      animeImage: animeImage,
      episodeId: episodeId,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      downloadUrl: downloadUrl,
      quality: quality,
      status: DownloadStatus.downloading,
      createdAt: DateTime.now(),
    );

    await _storage.saveDownload(download);

    await _startForegroundService();

    final downloadPath = await _getDownloadPath();
    final fileName = '${animeId}_ep${episodeNumber}_$quality.mp4';
    final filePath = '$downloadPath/$fileName';

    final cancelToken = CancelToken();
    _cancelTokens[downloadId] = cancelToken;

    try {
      await _dio.download(
        downloadUrl,
        filePath,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'Referer': 'https://allanime.to',
            'User-Agent':
                'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
            'Origin': 'https://allanime.to',
          },
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final updatedDownload = download.copyWith(
              totalBytes: total,
              downloadedBytes: received,
            );
            _storage.updateDownload(updatedDownload);

            final progress = received / total;
            _progressControllers[downloadId]?.add(progress);

            _updateNotification(
              downloadId.hashCode,
              animeTitle,
              'Episode $episodeNumber',
              progress,
            );
          }
        },
        deleteOnError: true,
      );

      final completedDownload = download.copyWith(
        status: DownloadStatus.completed,
        filePath: filePath,
        totalBytes: File(filePath).lengthSync(),
        downloadedBytes: File(filePath).lengthSync(),
        completedAt: DateTime.now(),
      );

      await _storage.updateDownload(completedDownload);

      try {
        _progressControllers[downloadId]?.add(1.0);
        await _showCompletionNotification(
          downloadId.hashCode,
          animeTitle,
          'Episode $episodeNumber',
        );
      } catch (e) {
        print('Warning: Failed to show completion notification: $e');
      }

      _cleanup(downloadId);
      await _stopForegroundService();
      return completedDownload;
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        final pausedDownload = download.copyWith(
          status: DownloadStatus.paused,
        );
        await _storage.updateDownload(pausedDownload);
        _cleanup(downloadId);
        return pausedDownload;
      } else {
        final failedDownload = download.copyWith(
          status: DownloadStatus.failed,
        );
        await _storage.updateDownload(failedDownload);

        if (File(filePath).existsSync()) {
          await File(filePath).delete();
        }

        _cleanup(downloadId);
        rethrow;
      }
    }
  }

  Future<void> pauseDownload(String downloadId) async {
    _cancelTokens[downloadId]?.cancel();
    final download = _storage.getDownload(downloadId);
    if (download != null) {
      await _storage.updateDownload(
        download.copyWith(status: DownloadStatus.paused),
      );
    }
  }

  Future<void> cancelDownload(String downloadId) async {
    _cancelTokens[downloadId]?.cancel();
    final download = _storage.getDownload(downloadId);

    if (download != null) {
      if (download.filePath != null && File(download.filePath!).existsSync()) {
        await File(download.filePath!).delete();
      }
      await _storage.updateDownload(
        download.copyWith(status: DownloadStatus.cancelled),
      );
    }

    _cleanup(downloadId);
  }

  Future<void> deleteDownload(String downloadId) async {
    final download = _storage.getDownload(downloadId);

    if (download != null && download.filePath != null) {
      final file = File(download.filePath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    await _storage.deleteDownload(downloadId);
    _cleanup(downloadId);
  }

  void _cleanup(String downloadId) {
    _cancelTokens.remove(downloadId);
    _progressControllers[downloadId]?.close();
    _progressControllers.remove(downloadId);
    _notifications.cancel(downloadId.hashCode);
  }

  Future<void> _updateNotification(
    int id,
    String title,
    String subtitle,
    double progress,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      'downloads',
      'Downloads',
      channelDescription: 'Episode download progress',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: (progress * 100).toInt(),
    );

    await _notifications.show(
      id,
      title,
      '$subtitle - ${(progress * 100).toStringAsFixed(0)}%',
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _showCompletionNotification(
    int id,
    String title,
    String subtitle,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'downloads',
      'Downloads',
      channelDescription: 'Episode download progress',
      importance: Importance.defaultImportance,
    );

    await _notifications.show(
      id,
      'Download Complete',
      '$title - $subtitle',
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<int> getStorageUsed() async {
    final downloads = _storage.getCompletedDownloads();
    return downloads.fold<int>(0, (sum, d) => sum + d.totalBytes);
  }

  Future<void> clearAllDownloads() async {
    final downloads = _storage.getAllDownloads();
    for (final download in downloads) {
      await deleteDownload(download.id);
    }
  }
}
