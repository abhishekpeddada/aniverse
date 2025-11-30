import 'package:hive_flutter/hive_flutter.dart';
import '../models/anime_model.dart';
import '../models/watch_history_model.dart';

class StorageService {
  static const String _watchlistBox = 'watchlist';
  static const String _favoritesBox = 'favorites';
  static const String _historyBox = 'history';
  static const String _animeBox = 'anime_cache';

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
    final key = '${history.animeId}_${history.episodeId}';
    await box.put(key, history);
  }

  WatchHistory? getWatchHistory(String animeId, String episodeId) {
    final box = Hive.box<WatchHistory>(_historyBox);
    final key = '${animeId}_$episodeId';
    return box.get(key);
  }

  List<WatchHistory> getAllHistory() {
    final box = Hive.box<WatchHistory>(_historyBox);
    final histories = box.values.toList();
    histories.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return histories;
  }

  // Get continue watching list (incomplete episodes)
  List<WatchHistory> getContinueWatching() {
    final box = Hive.box<WatchHistory>(_historyBox);
    final histories = box.values.where((h) => !h.isCompleted).toList();
    histories.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return histories;
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
}
