import 'package:hive/hive.dart';
import '../models/download_model.dart';

class DownloadStorageService {
  static const String _downloadsBox = 'downloads';

  static Future<void> init() async {
    Hive.registerAdapter(DownloadAdapter());
    await Hive.openBox<Download>(_downloadsBox);
  }

  Box<Download> get _box => Hive.box<Download>(_downloadsBox);

  Future<void> saveDownload(Download download) async {
    await _box.put(download.id, download);
  }

  Download? getDownload(String id) {
    return _box.get(id);
  }

  Future<void> updateDownload(Download download) async {
    await _box.put(download.id, download);
  }

  Future<void> deleteDownload(String id) async {
    await _box.delete(id);
  }

  List<Download> getAllDownloads() {
    return _box.values.toList();
  }

  List<Download> getDownloadsByStatus(String status) {
    return _box.values.where((d) => d.status == status).toList();
  }

  List<Download> getActiveDownloads() {
    return _box.values
        .where((d) =>
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.queued)
        .toList();
  }

  List<Download> getCompletedDownloads() {
    return _box.values
        .where((d) => d.status == DownloadStatus.completed)
        .toList();
  }

  Download? getDownloadByEpisode(String episodeId) {
    try {
      return _box.values.firstWhere((d) => d.episodeId == episodeId);
    } catch (e) {
      return null;
    }
  }

  bool isEpisodeDownloaded(String episodeId) {
    return _box.values.any(
      (d) => d.episodeId == episodeId && d.status == DownloadStatus.completed,
    );
  }

  int getTotalDownloadedSize() {
    return _box.values
        .where((d) => d.status == DownloadStatus.completed)
        .fold(0, (sum, d) => sum + d.totalBytes);
  }

  int getDownloadCount() {
    return _box.length;
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}
