import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/watch_history_model.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

// Watch History Provider
final historyProvider = StateNotifierProvider<HistoryNotifier, List<WatchHistory>>((ref) {
  return HistoryNotifier(ref.watch(storageServiceProvider));
});

class HistoryNotifier extends StateNotifier<List<WatchHistory>> {
  final StorageService _storageService;

  HistoryNotifier(this._storageService) : super([]) {
    _loadHistory();
  }

  void _loadHistory() {
    state = _storageService.getAllHistory();
  }

  Future<void> saveHistory(WatchHistory history) async {
    await _storageService.saveWatchHistory(history);
    _loadHistory();
  }

  WatchHistory? getHistory(String animeId, String episodeId) {
    return _storageService.getWatchHistory(animeId, episodeId);
  }
}

// Continue Watching Provider
final continueWatchingProvider = Provider<List<WatchHistory>>((ref) {
  final history = ref.watch(historyProvider);
  return history.where((h) => !h.isCompleted).toList();
});
