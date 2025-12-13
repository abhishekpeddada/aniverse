import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anime_model.dart';
import '../models/watch_history_model.dart';

final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());

class FirestoreService {
  FirebaseFirestore? _firestore;
  bool _isFirebaseAvailable = false;

  FirestoreService() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        _firestore = FirebaseFirestore.instance;
        _isFirebaseAvailable = true;
      } catch (e) {
        debugPrint('Firebase not available: $e');
        _isFirebaseAvailable = false;
      }
    } else {
      debugPrint('Firebase disabled on desktop platform');
      _isFirebaseAvailable = false;
    }
  }

  CollectionReference? _getUserCollection(String userId, String collection) {
    if (!_isFirebaseAvailable || _firestore == null) return null;
    return _firestore!.collection('users').doc(userId).collection(collection);
  }

  // User Preferences
  Future<void> updateUserPreferences(
      String userId, Map<String, dynamic> prefs) async {
    if (!_isFirebaseAvailable || _firestore == null) {
      debugPrint('ℹ️ Skipping Firebase sync (desktop mode)');
      return;
    }

    try {
      await _firestore!.collection('users').doc(userId).set({
        'preferences': prefs,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Failed to update user preferences: $e');
    }
  }

  Stream<Map<String, dynamic>> getUserPreferences(String userId) {
    if (!_isFirebaseAvailable || _firestore == null) {
      return Stream.value({});
    }

    return _firestore!
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data() as Map<String, dynamic>;
        return data['preferences'] as Map<String, dynamic>? ?? {};
      }
      return {};
    });
  }

  // Watch History
  Future<void> syncWatchHistory(String userId, WatchHistory history) async {
    if (!_isFirebaseAvailable || _firestore == null) return;

    try {
      final collection = _getUserCollection(userId, 'watchHistory');
      if (collection == null) return;

      await collection
          .doc(
              history.animeId) // Use animeId as key to keep only latest episode
          .set({
        'animeId': history.animeId,
        'animeTitle': history.animeTitle,
        'animeImage': history.animeImage,
        'episodeNumber': history.episodeNumber,
        'episodeId': history.episodeId,
        // 'positionMs': history.positionMs
        'durationMs': history.durationMs,
        'lastWatched': history.lastWatched.toIso8601String(),
      });
    } catch (e) {
      debugPrint('❌ Failed to sync watch history: $e');
    }
  }

  Future<void> deleteWatchHistory(String userId, String animeId) async {
    if (!_isFirebaseAvailable || _firestore == null) return;
    try {
      final collection = _getUserCollection(userId, 'watchHistory');
      if (collection == null) return;
      await collection.doc(animeId).delete();
    } catch (e) {
      debugPrint('❌ Failed to delete watch history: $e');
    }
  }

  Stream<List<WatchHistory>> getWatchHistory(String userId) {
    if (!_isFirebaseAvailable || _firestore == null) {
      return Stream.value([]);
    }

    final collection = _getUserCollection(userId, 'watchHistory');
    if (collection == null) return Stream.value([]);

    return collection
        .orderBy('lastWatched', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return WatchHistory(
          animeId: data['animeId'] ?? '',
          animeTitle: data['animeTitle'] ?? '',
          animeImage: data['animeImage'],
          episodeNumber: data['episodeNumber'] ?? 0,
          episodeId: data['episodeId'] ?? '',
          positionMs: data['positionMs'] ?? 0,
          durationMs: data['durationMs'] ?? 0,
          lastWatched: DateTime.parse(data['lastWatched']),
        );
      }).toList();
    });
  }

  // Watchlist
  Future<void> addToWatchlist(String userId, Anime anime) async {
    if (!_isFirebaseAvailable || _firestore == null) return;
    try {
      final collection = _getUserCollection(userId, 'watchlist');
      if (collection == null) return;
      await collection.doc(anime.id).set({
        'id': anime.id,
        'title': anime.title,
        'image': anime.image,
        'description': anime.description,
        'totalEpisodes': anime.totalEpisodes,
        'status': anime.status,
        'addedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('❌ Failed to add to watchlist: $e');
    }
  }

  Future<void> removeFromWatchlist(String userId, String animeId) async {
    if (!_isFirebaseAvailable || _firestore == null) return;
    try {
      final collection = _getUserCollection(userId, 'watchlist');
      if (collection == null) return;
      await collection.doc(animeId).delete();
    } catch (e) {
      debugPrint('❌ Failed to remove from watchlist: $e');
    }
  }

  Stream<List<Anime>> getWatchlist(String userId) {
    if (!_isFirebaseAvailable || _firestore == null) {
      return Stream.value([]);
    }
    final collection = _getUserCollection(userId, 'watchlist');
    if (collection == null) return Stream.value([]);
    return collection
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map<Anime>((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Anime(
          id: data['id'] ?? '',
          title: data['title'] ?? '',
          image: data['image'],
          description: data['description'],
          totalEpisodes: data['totalEpisodes'],
          status: data['status'],
        );
      }).toList();
    });
  }

  // Favorites
  Future<void> addToFavorites(String userId, Anime anime) async {
    if (!_isFirebaseAvailable || _firestore == null) return;
    try {
      final collection = _getUserCollection(userId, 'favorites');
      if (collection == null) return;
      await collection.doc(anime.id).set({
        'id': anime.id,
        'title': anime.title,
        'image': anime.image,
        'description': anime.description,
        'totalEpisodes': anime.totalEpisodes,
        'status': anime.status,
        'addedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('❌ Failed to add to favorites: $e');
    }
  }

  Future<void> removeFromFavorites(String userId, String animeId) async {
    if (!_isFirebaseAvailable || _firestore == null) return;
    try {
      final collection = _getUserCollection(userId, 'favorites');
      if (collection == null) return;
      await collection.doc(animeId).delete();
    } catch (e) {
      debugPrint('❌ Failed to remove from favorites: $e');
    }
  }

  Stream<List<Anime>> getFavorites(String userId) {
    if (!_isFirebaseAvailable || _firestore == null) {
      return Stream.value([]);
    }
    final collection = _getUserCollection(userId, 'favorites');
    if (collection == null) return Stream.value([]);
    return collection
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map<Anime>((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Anime(
          id: data['id'] ?? '',
          title: data['title'] ?? '',
          image: data['image'],
          description: data['description'],
          totalEpisodes: data['totalEpisodes'],
          status: data['status'],
        );
      }).toList();
    });
  }

  Future<bool> isFavorite(String userId, String animeId) async {
    if (!_isFirebaseAvailable || _firestore == null) return false;
    try {
      final collection = _getUserCollection(userId, 'favorites');
      if (collection == null) return false;
      final doc = await collection.doc(animeId).get();
      return doc.exists;
    } catch (e) {
      debugPrint('Failed to check favorite status: $e');
      return false;
    }
  }

  Future<bool> isInWatchlist(String userId, String animeId) async {
    if (!_isFirebaseAvailable || _firestore == null) return false;
    try {
      final collection = _getUserCollection(userId, 'watchlist');
      if (collection == null) return false;
      final doc = await collection.doc(animeId).get();
      return doc.exists;
    } catch (e) {
      debugPrint('Failed to check watchlist status: $e');
      return false;
    }
  }
}
