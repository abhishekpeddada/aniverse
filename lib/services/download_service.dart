import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/download_model.dart';
import '../models/anime_model.dart';
import 'download_storage_service.dart';
import 'anime_api_service.dart';

class DownloadService {
  final Dio _dio;
  final DownloadStorageService _storage;
  final FlutterLocalNotificationsPlugin _notifications;
  final AnimeApiService _animeApi;
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, StreamController<double>> _progressControllers = {};
  final Set<String> _processingIds = {};
  bool _isForegroundServiceRunning = false;

  DownloadService({
    required Dio dio,
    required DownloadStorageService storage,
    required FlutterLocalNotificationsPlugin notifications,
    required AnimeApiService animeApi,
  })  : _dio = dio,
        _storage = storage,
        _notifications = notifications,
        _animeApi = animeApi {
    _initForegroundTask();
    _recoverActiveDownloads();
    importOrphanedDownloads();
  }

  Future<void> _recoverActiveDownloads() async {
    // Give storage time to initialize if needed
    await Future.delayed(const Duration(milliseconds: 500));
    final activeDownloads = _storage.getActiveDownloads();
    
    for (final download in activeDownloads) {
      if (download.status == DownloadStatus.downloading) {
        if (!_processingIds.contains(download.id)) {
          await _storage.updateDownload(download.copyWith(status: DownloadStatus.paused));
        }
      }
    }
  }

  Future<void> importOrphanedDownloads() async {
    try {
      // Check permissions first without requesting
      bool hasPermission = false;
      if (Platform.isAndroid) {
         if ((await Permission.manageExternalStorage.status).isGranted || 
             (await Permission.storage.status).isGranted) {
           hasPermission = true;
         }
      } else {
        hasPermission = true;
      }
      
      if (!hasPermission) return;

      final path = await _getDownloadPath();
      final dir = Directory(path);
      if (!await dir.exists()) return;

      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4'));
      final existingDownloads = _storage.getAllDownloads();
      final restoredDownloads = <Download>[];

      for (final file in files) {
        // Skip if path already exists in DB
        if (existingDownloads.any((d) => d.filePath == file.path)) continue;

        final filename = file.path.split(Platform.pathSeparator).last;
        
        // Match format: {animeId}_ep{number}_{quality}.mp4
        // Example: 2KFMXxqRZErcC3ej3_ep1_720p.mp4
        // We use non-greedy matching for the first part in case ID has similar pattern, 
        // but 'ep' sequence is distinctive enough with underscores.
        final regex = RegExp(r'^(.+)_ep(\d+)_(.+)\.mp4$');
        final match = regex.firstMatch(filename);
        
        if (match != null) {
           final animeId = match.group(1)!;
           final epNum = int.tryParse(match.group(2)!) ?? 1;
           final quality = match.group(3)!;
           
           // We can't recover the exact Episode ID from filename, so we generate a consistent one
           // But we DO have the real Anime ID and Episode Number, which allows us to match in UI.
           final id = 'restored_${filename.hashCode}';
           
           final download = Download(
             id: id,
             animeId: animeId, // Use REAL Anime ID
             animeTitle: 'Restored ($animeId)', // We don't have title, use ID
             episodeId: 'restored_ep_${filename.hashCode}', 
             episodeNumber: epNum,
             downloadUrl: 'file://${file.path}', 
             quality: quality,
             status: DownloadStatus.completed,
             filePath: file.path,
             totalBytes: await file.length(),
             downloadedBytes: await file.length(),
             createdAt: await file.lastModified(),
             completedAt: await file.lastModified(),
           );
           
           await _storage.saveDownload(download);
           restoredDownloads.add(download);
           debugPrint('Restored orphaned download: $filename (Anime: $animeId, Ep: $epNum)');
        }
      }
      
      // Also check if we have any existing restored downloads that need metadata
      final existingRestored = _storage.getAllDownloads().where((d) => 
          d.id.startsWith('restored_') && 
          d.animeTitle.startsWith('Restored (')
      );
      restoredDownloads.addAll(existingRestored);

      // Fetch metadata for restored downloads in background
      if (restoredDownloads.isNotEmpty) {
        _fetchMetadataForRestored(restoredDownloads);
      }
    } catch (e) {
      debugPrint('Failed to import orphaned downloads: $e');
    }
  }

  Future<void> _fetchMetadataForRestored(List<Download> orphans) async {
    debugPrint('Fetching metadata for ${orphans.length} orphans...');
    final animeIds = orphans.map((d) => d.animeId).toSet();
    
    for (final animeId in animeIds) {
      if (animeId.startsWith('imported_') || animeId.startsWith('restored_')) continue; 
      
      try {
        final info = await _animeApi.getAnimeInfo(animeId);
        if (info != null && info['anime'] is Anime) {
           final Anime anime = info['anime'];
           // Find all downloads for this anime that need updating
           final relevant = orphans.where((d) => d.animeId == animeId);
           
           for (final download in relevant) {
             final updated = download.copyWith(
               animeTitle: anime.title,
               animeImage: anime.image,
             );
             await _storage.updateDownload(updated);
           }
           debugPrint('Updated metadata for ${anime.title}');
        }
      } catch (e) {
        debugPrint('Failed to fetch metadata for $animeId: $e');
      }
    }
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

    try {
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
    } catch (e) {
      debugPrint('Foreground service not available (desktop): $e');
    }
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
    Directory? directory;
    
    if (Platform.isAndroid) {
      // Use standard Download directory
      directory = Directory('/storage/emulated/0/Download');
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    
    final downloadsDir = Directory('${directory.path}/Aniverse');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir.path;
  }

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Try manageExternalStorage first (Android 11+)
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    // Request manageExternalStorage
    if (status.isDenied) {
      status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;
    }

    // Fallback: try regular storage permission (Android 10 and below)
    var storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;
    
    if (storageStatus.isDenied) {
      storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;
    }

    // If permanently denied, open app settings
    if (status.isPermanentlyDenied || storageStatus.isPermanentlyDenied) {
      await openAppSettings();
    }

    return false;
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

    // Check storage permission first
    final hasPermission = await _requestStoragePermission();
    if (!hasPermission) {
      throw Exception('Storage permission denied. Please grant storage access to download episodes.');
    }

    // Attempt to restore any orphaned downloads now that we have permission
    importOrphanedDownloads();

    if (_processingIds.contains(downloadId)) return _storage.getDownload(downloadId) ?? 
        Download(
          id: downloadId,
          animeId: animeId,
          animeTitle: animeTitle,
          episodeId: episodeId,
          episodeNumber: episodeNumber,
          downloadUrl: downloadUrl,
          quality: quality,
          status: DownloadStatus.downloading,
          createdAt: DateTime.now(),
        ); // Return dummy or existing if locked
            
    _processingIds.add(downloadId);

    try {
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

      DateTime lastUpdate = DateTime.now();

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
              final progress = received / total;
              _progressControllers[downloadId]?.add(progress);

              final now = DateTime.now();
              if (now.difference(lastUpdate).inSeconds >= 1) {
                lastUpdate = now;
                final updatedDownload = download.copyWith(
                  totalBytes: total,
                  downloadedBytes: received,
                );
                _storage.updateDownload(updatedDownload);

                _updateNotification(
                  downloadId.hashCode,
                  animeTitle,
                  'Episode $episodeNumber',
                  progress,
                );
              }
            }
          },
          deleteOnError: false,
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
          debugPrint('Warning: Failed to show completion notification: $e');
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

          // Don't delete file on error to allow retry/resume
          // if (File(filePath).existsSync()) {
          //   await File(filePath).delete();
          // }

          _cleanup(downloadId);
          rethrow;
        }
      }
    } finally {
      _processingIds.remove(downloadId);
    }
  }

  Future<void> resumeDownload(String downloadId) async {
    if (_processingIds.contains(downloadId)) return;
    _processingIds.add(downloadId);

    try {
      final download = _storage.getDownload(downloadId);
      if (download == null) return;
      
      // If not paused or failed, do nothing
      if (download.status != DownloadStatus.paused && 
          download.status != DownloadStatus.failed) {
        return;
      }

      final downloadPath = await _getDownloadPath();
      final fileName = '${download.animeId}_ep${download.episodeNumber}_${download.quality}.mp4';
      final filePath = '$downloadPath/$fileName';
      final file = File(filePath);
      
      int existingBytes = 0;
      if (await file.exists()) {
        existingBytes = await file.length();
      }

      final cancelToken = CancelToken();
      _cancelTokens[downloadId] = cancelToken;
      
      await _storage.updateDownload(download.copyWith(status: DownloadStatus.downloading));
      
      // Initialize progress stream if not exists
      if (!_progressControllers.containsKey(downloadId) || _progressControllers[downloadId]!.isClosed) {
        _progressControllers[downloadId] = StreamController<double>.broadcast();
      }

      try {
        await _startForegroundService();
        
        final response = await _dio.get(
          download.downloadUrl,
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'Range': 'bytes=$existingBytes-',
              'Referer': 'https://allanime.to',
              'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
            },
          ),
          cancelToken: cancelToken,
        );

        final raf = await file.open(mode: FileMode.append);
        
        int receivedBytes = 0;
        int totalBytes = existingBytes + (int.parse(response.headers.value('content-length') ?? '0'));
        
        // Fallback to existing totalBytes if header missing and we have previous data
        if (totalBytes <= existingBytes && download.totalBytes > existingBytes) {
            totalBytes = download.totalBytes;
        }
        
        final contentRange = response.headers.value('content-range');
        if (contentRange != null) {
          final parts = contentRange.split('/');
          if (parts.length == 2 && parts[1] != '*') {
            totalBytes = int.parse(parts[1]);
          }
        }

        final stream = response.data.stream;
        DateTime lastUpdate = DateTime.now();

        await for (final chunk in stream) {
          await raf.writeFrom(chunk);
          receivedBytes += chunk.length as int;
          
          final currentTotal = existingBytes + receivedBytes;
          final rawProgress = totalBytes > 0 ? currentTotal / totalBytes : 0.0;
          final progress = rawProgress.clamp(0.0, 1.0);
          
          _progressControllers[downloadId]?.add(progress);

          // Update throttled (every 1 second)
          final now = DateTime.now();
          if (now.difference(lastUpdate).inSeconds >= 1) {
             lastUpdate = now;
             _storage.updateDownload(download.copyWith( // Stale download has Paused status!
              status: DownloadStatus.downloading, // Force correct status
              downloadedBytes: currentTotal,
              totalBytes: totalBytes,
            ));
             _updateNotification(
                downloadId.hashCode,
                download.animeTitle,
                'Episode ${download.episodeNumber}',
                progress,
              );
          }
        }
        
        await raf.close();

        final completedDownload = download.copyWith(
          status: DownloadStatus.completed,
          filePath: filePath,
          downloadedBytes: await file.length(),
          totalBytes: await file.length(), // Ensure total matches actual
          completedAt: DateTime.now(),
        );

        await _storage.updateDownload(completedDownload);
        _progressBarCompletion(downloadId, download.animeTitle, download.episodeNumber);
        
      } catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) {
           await _storage.updateDownload(download.copyWith(status: DownloadStatus.paused));
        } else {
           await _storage.updateDownload(download.copyWith(status: DownloadStatus.failed));
        }
      } finally {
        _cleanup(downloadId);
        await _stopForegroundService();
      }
    } finally {
      _processingIds.remove(downloadId);
    }
  }

  void _progressBarCompletion(String downloadId, String title, int ep) {
      try {
        _progressControllers[downloadId]?.add(1.0);
        _showCompletionNotification(
          downloadId.hashCode,
          title,
          'Episode $ep',
        );
      } catch (e) {
        debugPrint('Warning: Failed to show completion notification: $e');
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
