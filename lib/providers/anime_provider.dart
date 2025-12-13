import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/anime_model.dart';
import '../services/anime_api_service.dart';
import '../services/raiden_api_service.dart';
import '../utils/raiden_data_converter.dart';
import './raiden_provider.dart';
import 'auth_provider.dart';
import 'local_settings_provider.dart';

// API Service Providers
final animeApiServiceProvider = Provider((ref) => AnimeApiService());
final raidenApiServiceProvider = Provider((ref) => RaidenApiService());

// Search Results Provider
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<List<Anime>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];

  final apiService = ref.watch(animeApiServiceProvider);
  final raidenService = ref.watch(raidenApiServiceProvider);

  final localSettings = ref.watch(localSettingsProvider);
  final firebasePrefs = ref.watch(userPreferencesProvider).valueOrNull;

  final allowAdult = (localSettings['allowAdult'] as bool?) ??
      (firebasePrefs?['allowAdult'] as bool?) ??
      false;

  debugPrint('Search query: $query');
  debugPrint('Local settings allowAdult: ${localSettings['allowAdult']}');
  debugPrint('Firebase prefs allowAdult: ${firebasePrefs?['allowAdult']}');
  debugPrint('Final allowAdult: $allowAdult');

  // Always search AllAnime first
  final allAnimeResults =
      await apiService.searchAnime(query, allowAdult: allowAdult);

  // If adult mode is ON, also search Raiden API and combine results
  if (allowAdult) {
    debugPrint('🔍 Adult mode ON - searching Raiden API too');
    try {
      final raidenResults = await raidenService.searchAdultAnime(query);

      // Cache Raiden data for video playback
      final raidenDataCache = ref.read(raidenAnimeDataProvider.notifier);
      final currentCache = ref.read(raidenAnimeDataProvider);
      final updatedCache = Map<String, Map<String, dynamic>>.from(currentCache);

      for (var raidenData in raidenResults) {
        final anime = RaidenDataConverter.fromRaidenResult(raidenData);
        updatedCache[anime.id] =
            raidenData; // Store original data with download_url
      }

      raidenDataCache.state = updatedCache;

      final raidenAnime =
          RaidenDataConverter.fromRaidenResultsList(raidenResults);

      // Combine results: AllAnime first, then Raiden
      debugPrint(
          'Combined ${allAnimeResults.length} AllAnime + ${raidenAnime.length} Raiden results');
      return [...allAnimeResults, ...raidenAnime];
    } catch (e) {
      debugPrint('Raiden API failed: $e');
      // Raiden API failed, just return AllAnime results
      return allAnimeResults;
    }
  } else {
    debugPrint('Adult mode OFF - only AllAnime results');
  }

  return allAnimeResults;
});

// Anime Details Provider
final animeDetailsProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, animeId) async {
  final apiService = ref.watch(animeApiServiceProvider);
  return await apiService.getAnimeInfo(animeId);
});

// Episode Sources Provider (legacy - uses 'sub' by default)
final episodeSourcesProvider =
    FutureProvider.family<Map<String, dynamic>?, String>(
        (ref, episodeId) async {
  final apiService = ref.watch(animeApiServiceProvider);
  return await apiService.getEpisodeSources(episodeId);
});

// Episode Sources Provider with Translation Type
final episodeSourcesWithTypeProvider = FutureProvider.family<
    Map<String, dynamic>?,
    ({String episodeId, String translationType})>((ref, params) async {
  final apiService = ref.watch(animeApiServiceProvider);
  return await apiService.getEpisodeSources(params.episodeId,
      translationType: params.translationType);
});

// Latest Releases Provider
final latestReleasesProvider = FutureProvider.family<List<Map<String, dynamic>>,
    ({int page, List<String>? genres})>((ref, params) async {
  final apiService = ref.watch(animeApiServiceProvider);
  final raidenService = ref.watch(raidenApiServiceProvider);

  final localSettings = ref.watch(localSettingsProvider);
  final firebasePrefs = ref.watch(userPreferencesProvider).valueOrNull;

  final allowAdult = (localSettings['allowAdult'] as bool?) ??
      (firebasePrefs?['allowAdult'] as bool?) ??
      false;

  debugPrint(
      'Latest releases - allowAdult: $allowAdult, genres: ${params.genres}');

  // Check if "Hentai" genre is selected
  final hasHentaiFilter = params.genres?.contains('Hentai') ?? false;

  if (hasHentaiFilter && allowAdult) {
    // Fetch from Raiden API instead of AllAnime
    try {
      final raidenResults =
          await raidenService.getAdultAnime(page: params.page);

      // Cache Raiden data for video playback
      if (raidenResults.isNotEmpty) {
        final raidenDataCache = ref.read(raidenAnimeDataProvider.notifier);
        final currentCache = ref.read(raidenAnimeDataProvider);
        final updatedCache =
            Map<String, Map<String, dynamic>>.from(currentCache);

        for (var raidenData in raidenResults) {
          final anime = RaidenDataConverter.fromRaidenResult(raidenData);
          updatedCache[anime.id] = raidenData;
        }

        raidenDataCache.state = updatedCache;
      }

      // Convert to format expected by UI (List<Map<String, dynamic>>)
      return raidenResults.map((data) {
        final anime = RaidenDataConverter.fromRaidenResult(data);
        return {
          'id': anime.id,
          'title': anime.title,
          'image': anime.image,
          'source': 'raiden',
          'latestEpisode': 'Movie',
          'hasSubbed': true,
          'hasDubbed': false,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching from Raiden: $e');
      return [];
    }
  }

  // Original AllAnime logic for other genres
  return await apiService.getLatestReleases(
    page: params.page,
    allowAdult: allowAdult,
    genres: params.genres,
  );
});
