import 'package:hive_flutter/hive_flutter.dart';
import '../models/anime_model.dart';
import '../models/watch_history_model.dart';

class StorageService {
  static const String _watchlistBox = 'watchlist';
  static const String _favoritesBox = 'favorites';
  static const String _historyBox = 'history';
  static const String _animeBox = 'anime_cache';
  static const String _raidenDataBox = 'raiden_data'; // NEW: Persistent Raiden cache

  // Initialize Hive
  static Future<void> init() async {
    await Hive.initFlutter();
    
    // Register adapters
    Hive.registerAdapter(AnimeAdapter());
    Hive.registerAdapter(WatchHistoryAdapter());
    
    // Open boxes
    await Hive.openBox<String>(_watchlistBox);
    await Hive.openBox<String>(_favoritesBox);
    await Hive.openBox<WatchHistory>(_historyBox);
    await Hive.openBox<Anime>(_animeBox);
    await Hive.openBox<Map>(_raidenDataBox); // NEW
  }

  // Watchlist operations
  Future<void> addToWatchlist(String animeId) async {
    final box = Hive.box<String>(_watchlistBox);
    if (!box.values.contains(animeId)) {
      await box.add(animeId);
    }
  }

  Future<void> removeFromWatchlist(String animeId) async {
    final box = Hive.box<String>(_watchlistBox);
    final key = box.keys.firstWhere(
      (k) => box.get(k) == animeId,
      orElse: () => null,
    );
    if (key != null) {
      await box.delete(key);
    }
  }

  bool isInWatchlist(String animeId) {
    final box = Hive.box<String>(_watchlistBox);
    return box.values.contains(animeId);
  }

  List<String> getWatchlist() {
    final box = Hive.box<String>(_watchlistBox);
    return box.values.toList();
  }

  // Favorites operations
  Future<void> addToFavorites(String animeId) async {
    final box = Hive.box<String>(_favoritesBox);
    if (!box.values.contains(animeId)) {
      await box.add(animeId);
    }
  }

  Future<void> removeFromFavorites(String animeId) async {
    final box = Hive.box<String>(_favoritesBox);
    final key = box.keys.firstWhere(
      (k) => box.get(k) == animeId,
      orElse: () => null,
    );
    if (key != null) {
      await box.delete(key);
    }
  }

  bool isInFavorites(String animeId) {
    final box = Hive.box<String>(_favoritesBox);
    return box.values.contains(animeId);
  }

  List<String> getFavorites() {
    final box = Hive.box<String>(_favoritesBox);
    return box.values.toList();
  }

  // Watch history operations
  Future<void> saveWatchHistory(WatchHistory history) async {
    final box = Hive.box<WatchHistory>(_historyBox);
    // Use composite key to store history for each episode individually
    final key = '${history.animeId}_${history.episodeId}';
    await box.put(key, history);
  }

  // Get specific episode history
  WatchHistory? getEpisodeHistory(String animeId, String episodeId) {
    final box = Hive.box<WatchHistory>(_historyBox);
    final key = '${animeId}_$episodeId';
    return box.get(key);
  }

  // Get latest history for an anime (for continue watching logic)
  WatchHistory? getLatestAnimeHistory(String animeId) {
    final box = Hive.box<WatchHistory>(_historyBox);
    final animeHistory = box.values.where((h) => h.animeId == animeId).toList();
    if (animeHistory.isEmpty) return null;
    
    animeHistory.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return animeHistory.first;
  }

  List<WatchHistory> getAllHistory() {
    final box = Hive.box<WatchHistory>(_historyBox);
    final histories = box.values.toList();
    histories.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return histories;
  }

  // Get continue watching list (latest incomplete episode per anime)
  List<WatchHistory> getContinueWatching() {
    final box = Hive.box<WatchHistory>(_historyBox);
    final allHistory = box.values.toList();
    
    // Group by animeId
    final Map<String, WatchHistory> latestPerAnime = {};
    
    for (var history in allHistory) {
      if (latestPerAnime.containsKey(history.animeId)) {
        if (history.lastWatched.isAfter(latestPerAnime[history.animeId]!.lastWatched)) {
          latestPerAnime[history.animeId] = history;
        }
      } else {
        latestPerAnime[history.animeId] = history;
      }
    }
    
    // Filter for incomplete and sort
    final result = latestPerAnime.values.toList();
    result.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return result;
  }

  // Delete all history for a specific anime
  Future<void> deleteAnimeHistory(String animeId) async {
    final box = Hive.box<WatchHistory>(_historyBox);
    final keysToDelete = <String>[];
    
    // Find all keys for this anime
    for (var key in box.keys) {
      final history = box.get(key);
      if (history != null && history.animeId == animeId) {
        keysToDelete.add(key as String);
      }
    }
    
    // Delete all found entries
    for (var key in keysToDelete) {
      await box.delete(key);
    }
  }

  // Clear all watch history
  Future<void> clearAllHistory() async {
    final box = Hive.box<WatchHistory>(_historyBox);
    await box.clear();
  }

  // Anime cache operations
  Future<void> cacheAnime(Anime anime) async {
    final box = Hive.box<Anime>(_animeBox);
    await box.put(anime.id, anime);
  }

  Anime? getCachedAnime(String animeId) {
    final box = Hive.box<Anime>(_animeBox);
    return box.get(animeId);
  }

  // Clear anime cache (useful for schema migrations)
  static Future<void> clearAnimeCache() async {
    final box = Hive.box<Anime>(_animeBox);
    await box.clear();
  }

  // NEW: Raiden data cache operations
  Future<void> cacheRaidenData(String animeId, Map<String, dynamic> data) async {
    final box = Hive.box<Map>(_raidenDataBox);
    await box.put(animeId, data);
  }

  Map<String, dynamic>? getRaidenData(String animeId) {
    final box = Hive.box<Map>(_raidenDataBox);
    final data = box.get(animeId);
    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  Future<void> clearRaidenCache() async {
    final box = Hive.box<Map>(_raidenDataBox);
    await box.clear();
  }
}
