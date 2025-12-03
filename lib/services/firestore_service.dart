import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anime_model.dart';
import '../models/watch_history_model.dart';

final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference _getUserCollection(String userId, String collection) {
    return _firestore.collection('users').doc(userId).collection(collection);
  }

  // User Preferences
  Future<void> updateUserPreferences(String userId, Map<String, dynamic> prefs) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'preferences': prefs,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Failed to update user preferences: $e');
    }
  }

  Stream<Map<String, dynamic>> getUserPreferences(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data() as Map<String, dynamic>;
        return data['preferences'] as Map<String, dynamic>? ?? {};
      }
      return {};
    });
  }

  // Watch History
  Future<void> syncWatchHistory(String userId, WatchHistory history) async {
    try {
      await _getUserCollection(userId, 'watchHistory')
          .doc(history.animeId) // Use animeId as key to keep only latest episode
          .set({
        'animeId': history.animeId,
        'animeTitle': history.animeTitle,
        'animeImage': history.animeImage,
        'episodeNumber': history.episodeNumber,
        'episodeId': history.episodeId,
        // 'positionMs': history.positionMs
        'durationMs': history.durationMs,
        'lastWatched': history.lastWatched.toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Failed to sync watch history: $e');
    }
  }
  
  Future<void> deleteWatchHistory(String userId, String animeId) async {
    try {
      await _getUserCollection(userId, 'watchHistory').doc(animeId).delete();
    } catch (e) {
      debugPrint('❌ Failed to delete watch history: $e');
    }
  }

  Stream<List<WatchHistory>> getWatchHistory(String userId) {
    return _getUserCollection(userId, 'watchHistory')
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
    try {
      await _getUserCollection(userId, 'watchlist').doc(anime.id).set({
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
    try {
      await _getUserCollection(userId, 'watchlist').doc(animeId).delete();
    } catch (e) {
      debugPrint('❌ Failed to remove from watchlist: $e');
    }
  }

  Stream<List<Anime>> getWatchlist(String userId) {
    return _getUserCollection(userId, 'watchlist')
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
    try {
      await _getUserCollection(userId, 'favorites').doc(anime.id).set({
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
    try {
      await _getUserCollection(userId, 'favorites').doc(animeId).delete();
    } catch (e) {
      debugPrint('❌ Failed to remove from favorites: $e');
    }
  }

  Stream<List<Anime>> getFavorites(String userId) {
    return _getUserCollection(userId, 'favorites')
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
    try {
      final doc = await _getUserCollection(userId, 'favorites').doc(animeId).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isInWatchlist(String userId, String animeId) async {
    try {
      final doc = await _getUserCollection(userId, 'watchlist').doc(animeId).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }
}
