import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

// Watchlist Provider
final watchlistProvider = StateNotifierProvider<WatchlistNotifier, List<String>>((ref) {
  return WatchlistNotifier(ref.watch(storageServiceProvider));
});

class WatchlistNotifier extends StateNotifier<List<String>> {
  final StorageService _storageService;

  WatchlistNotifier(this._storageService) : super([]) {
    _loadWatchlist();
  }

  void _loadWatchlist() {
    state = _storageService.getWatchlist();
  }

  Future<void> addToWatchlist(String animeId) async {
    await _storageService.addToWatchlist(animeId);
    _loadWatchlist();
  }

  Future<void> removeFromWatchlist(String animeId) async {
    await _storageService.removeFromWatchlist(animeId);
    _loadWatchlist();
  }

  bool isInWatchlist(String animeId) {
    return state.contains(animeId);
  }
}

// Favorites Provider
final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<String>>((ref) {
  return FavoritesNotifier(ref.watch(storageServiceProvider));
});

class FavoritesNotifier extends StateNotifier<List<String>> {
  final StorageService _storageService;

  FavoritesNotifier(this._storageService) : super([]) {
    _loadFavorites();
  }

  void _loadFavorites() {
    state = _storageService.getFavorites();
  }

  Future<void> addToFavorites(String animeId) async {
    await _storageService.addToFavorites(animeId);
    _loadFavorites();
  }

  Future<void> removeFromFavorites(String animeId) async {
    await _storageService.removeFromFavorites(animeId);
    _loadFavorites();
  }

  bool isInFavorites(String animeId) {
    return state.contains(animeId);
  }
}
