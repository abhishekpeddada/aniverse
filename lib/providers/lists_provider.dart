import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';
import 'auth_provider.dart';

// Watchlist Provider
final watchlistProvider = StateNotifierProvider<WatchlistNotifier, List<String>>((ref) {
  return WatchlistNotifier(
    ref.watch(storageServiceProvider),
    ref.watch(firestoreServiceProvider),
    ref.watch(currentUserProvider),
  );
});

class WatchlistNotifier extends StateNotifier<List<String>> {
  final StorageService _storageService;
  final FirestoreService _firestoreService;
  final User? _user;

  WatchlistNotifier(this._storageService, this._firestoreService, this._user) : super([]) {
    _loadWatchlist();
  }

  void _loadWatchlist() {
    state = _storageService.getWatchlist();
  }

  Future<void> syncFromFirestore() async {
    if (_user == null) return;
    
    try {
      final snapshot = await _firestoreService.getWatchlist(_user!.uid).first;
      for (var anime in snapshot) {
        await _storageService.addToWatchlist(anime.id);
        await _storageService.cacheAnime(anime);
      }
      _loadWatchlist();
    } catch (e) {
      print('⚠️ Failed to sync watchlist from Firestore: $e');
    }
  }

  Future<void> addToWatchlist(String animeId) async {
    await _storageService.addToWatchlist(animeId);
    
    if (_user != null) {
      // Get cached anime to sync full details
      final anime = _storageService.getCachedAnime(animeId);
      if (anime != null) {
        await _firestoreService.addToWatchlist(_user!.uid, anime);
      }
    }
    
    _loadWatchlist();
  }

  Future<void> removeFromWatchlist(String animeId) async {
    await _storageService.removeFromWatchlist(animeId);
    
    if (_user != null) {
      await _firestoreService.removeFromWatchlist(_user!.uid, animeId);
    }
    
    _loadWatchlist();
  }

  bool isInWatchlist(String animeId) {
    return state.contains(animeId);
  }
}

// Favorites Provider
final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<String>>((ref) {
  return FavoritesNotifier(
    ref.watch(storageServiceProvider),
    ref.watch(firestoreServiceProvider),
    ref.watch(currentUserProvider),
  );
});

class FavoritesNotifier extends StateNotifier<List<String>> {
  final StorageService _storageService;
  final FirestoreService _firestoreService;
  final User? _user;

  FavoritesNotifier(this._storageService, this._firestoreService, this._user) : super([]) {
    _loadFavorites();
  }

  void _loadFavorites() {
    state = _storageService.getFavorites();
  }

  Future<void> syncFromFirestore() async {
    if (_user == null) return;
    
    try {
      final snapshot = await _firestoreService.getFavorites(_user!.uid).first;
      for (var anime in snapshot) {
        await _storageService.addToFavorites(anime.id);
        await _storageService.cacheAnime(anime);
      }
      _loadFavorites();
    } catch (e) {
      print('⚠️ Failed to sync favorites from Firestore: $e');
    }
  }

  Future<void> addToFavorites(String animeId) async {
    await _storageService.addToFavorites(animeId);
    
    if (_user != null) {
      final anime = _storageService.getCachedAnime(animeId);
      if (anime != null) {
        await _firestoreService.addToFavorites(_user!.uid, anime);
      }
    }
    
    _loadFavorites();
  }

  Future<void> removeFromFavorites(String animeId) async {
    await _storageService.removeFromFavorites(animeId);
    
    if (_user != null) {
      await _firestoreService.removeFromFavorites(_user!.uid, animeId);
    }
    
    _loadFavorites();
  }

  bool isInFavorites(String animeId) {
    return state.contains(animeId);
  }
}
