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

  Future<void> saveHistory(WatchHistory history) async {
    // Always save locally
    await _storageService.saveWatchHistory(history);
    
    // NOTE: Firestore sync disabled to reduce read/write operations as per user request.
    // If needed in future, uncomment the following:
    /*
    if (_user != null) {
      await _firestoreService.syncWatchHistory(_user!.uid, history);
    }
    */
    
    _loadHistory();
  }

  WatchHistory? getHistory(String animeId) {
    return _storageService.getLatestAnimeHistory(animeId);
  }
}

// Continue Watching Provider
final continueWatchingProvider = Provider<List<WatchHistory>>((ref) {
  // Watch historyProvider to trigger updates when history changes
  ref.watch(historyProvider);
  // Use the logic in StorageService to get the correct list
  return ref.read(storageServiceProvider).getContinueWatching();
});
