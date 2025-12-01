import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/watch_history_model.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import 'storage_provider.dart';
import 'auth_provider.dart';

// Watch History Provider
final historyProvider = StateNotifierProvider<HistoryNotifier, List<WatchHistory>>((ref) {
  return HistoryNotifier(
    ref.watch(storageServiceProvider),
    ref.watch(firestoreServiceProvider),
    ref.watch(currentUserProvider),
  );
});

class HistoryNotifier extends StateNotifier<List<WatchHistory>> {
  final StorageService _storageService;
  final FirestoreService _firestoreService;
  final User? _user;

  HistoryNotifier(this._storageService, this._firestoreService, this._user) : super([]) {
    _loadHistory();
  }

  void _loadHistory() {
    state = _storageService.getAllHistory();
  }

  Future<void> syncFromFirestore() async {
    if (_user == null) return;
    
    try {
      final snapshot = await _firestoreService.getWatchHistory(_user!.uid).first;
      for (var history in snapshot) {
        await _storageService.saveWatchHistory(history);
      }
      _loadHistory();
    } catch (e) {
      debugPrint('⚠️ Failed to sync history from Firestore: $e');
    }
  }


  Future<void> saveHistory(WatchHistory history, {bool syncToCloud = true}) async {
    // Always save locally
    await _storageService.saveWatchHistory(history);
    
    // Sync to Firestore if user is logged in and sync is requested
    if (syncToCloud && _user != null) {
      try {
        await _firestoreService.syncWatchHistory(_user!.uid, history);
      } catch (e) {
        debugPrint('⚠️ Failed to sync to Firestore: $e');
        // Continue even if Firestore sync fails
      }
    }
    
    _loadHistory();
  }

  WatchHistory? getHistory(String animeId) {
    return _storageService.getLatestAnimeHistory(animeId);
  }

  Future<void> removeAnimeHistory(String animeId) async {
    await _storageService.deleteAnimeHistory(animeId);
    
    // Also delete from Firestore if user is logged in
    if (_user != null) {
      try {
        // Note: Would need to implement deleteAnimeHistory in FirestoreService
        // For now, just log
        debugPrint('TODO: Delete anime $animeId from Firestore');
      } catch (e) {
        debugPrint('⚠️ Failed to delete from Firestore: $e');
      }
    }
    
    _loadHistory();
  }
}

// Continue Watching Provider
final continueWatchingProvider = Provider<List<WatchHistory>>((ref) {
  // Watch historyProvider to trigger updates when history changes
  ref.watch(historyProvider);
  // Use the logic in StorageService to get the correct list
  return ref.read(storageServiceProvider).getContinueWatching();
});
