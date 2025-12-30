import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/download_service.dart';
import '../services/download_storage_service.dart';
import '../services/download_storage_service.dart';
import '../models/download_model.dart';
import 'anime_provider.dart';

final downloadStorageServiceProvider = Provider<DownloadStorageService>((ref) {
  return DownloadStorageService();
});

final downloadServiceProvider = Provider<DownloadService>((ref) {
  final dio = Dio();
  final storage = ref.watch(downloadStorageServiceProvider);
  final notifications = FlutterLocalNotificationsPlugin();
  final animeApi = ref.watch(animeApiServiceProvider);

  return DownloadService(
    dio: dio,
    storage: storage,
    notifications: notifications,
    animeApi: animeApi,
  );
});

final downloadsProvider = StreamProvider<List<Download>>((ref) {
  final storage = ref.watch(downloadStorageServiceProvider);
  return Stream.periodic(const Duration(milliseconds: 500), (_) {
    return storage.getAllDownloads();
  });
});

final activeDownloadsProvider = Provider<List<Download>>((ref) {
  final downloads = ref.watch(downloadsProvider).value ?? [];
  return downloads
      .where((d) =>
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.queued)
      .toList();
});

final completedDownloadsProvider = Provider<List<Download>>((ref) {
  final downloads = ref.watch(downloadsProvider).value ?? [];
  return downloads.where((d) => d.status == DownloadStatus.completed).toList();
});

final failedDownloadsProvider = Provider<List<Download>>((ref) {
  final downloads = ref.watch(downloadsProvider).value ?? [];
  return downloads.where((d) => d.status == DownloadStatus.failed).toList();
});

final downloadProgressProvider =
    StreamProvider.family<double, String>((ref, downloadId) {
  final service = ref.watch(downloadServiceProvider);
  return service.getProgressStream(downloadId);
});

final storageUsageProvider = FutureProvider<int>((ref) {
  final service = ref.watch(downloadServiceProvider);
  return service.getStorageUsed();
});

// Stream provider for real-time storage updates
final storageUsageStreamProvider = StreamProvider<int>((ref) {
  final service = ref.watch(downloadServiceProvider);
  return Stream.periodic(const Duration(seconds: 1), (_) async {
    return await service.getStorageUsed();
  }).asyncMap((future) => future);
});

final isEpisodeDownloadedProvider =
    Provider.family<bool, String>((ref, episodeId) {
  final downloads = ref.watch(downloadsProvider).value ?? [];
  return downloads.any(
    (d) => d.episodeId == episodeId && d.status == DownloadStatus.completed,
  );
});

final downloadByEpisodeProvider =
    Provider.family<Download?, String>((ref, episodeId) {
  final downloads = ref.watch(downloadsProvider).value ?? [];
  try {
    return downloads.firstWhere(
      (d) => d.episodeId == episodeId && d.status == DownloadStatus.completed,
    );
  } catch (e) {
    return null;
  }
});

final downloadByAnimeAndEpisodeProvider =
    Provider.family<Download?, ({String animeId, int episodeNumber})>((ref, args) {
  final downloads = ref.watch(downloadsProvider).value ?? [];
  try {
    return downloads.firstWhere(
      (d) => d.animeId == args.animeId && 
             d.episodeNumber == args.episodeNumber && 
             d.status == DownloadStatus.completed,
    );
  } catch (e) {
    return null;
  }
});
