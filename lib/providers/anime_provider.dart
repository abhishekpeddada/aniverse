import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anime_model.dart';
import '../services/anime_api_service.dart';
import '../services/raiden_api_service.dart';
import '../utils/raiden_data_converter.dart';
import './raiden_provider.dart';
import 'auth_provider.dart';

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
  final prefs = ref.watch(userPreferencesProvider).valueOrNull;
  final allowAdult = prefs?['allowAdult'] as bool? ?? false;
  
  // Always search AllAnime first
  final allAnimeResults = await apiService.searchAnime(query, allowAdult: allowAdult);
  
  // If adult mode is ON, also search Raiden API and combine results
  if (allowAdult) {
    try {
      final raidenResults = await raidenService.searchAdultAnime(query);
      
      // Cache Raiden data for video playback
      final raidenDataCache = ref.read(raidenAnimeDataProvider.notifier);
      final currentCache = ref.read(raidenAnimeDataProvider);
      final updatedCache = Map<String, Map<String, dynamic>>.from(currentCache);
      
      for (var raidenData in raidenResults) {
        final anime = RaidenDataConverter.fromRaidenResult(raidenData);
        updatedCache[anime.id] = raidenData; // Store original data with download_url
      }
      
      raidenDataCache.state = updatedCache;
      
      final raidenAnime = RaidenDataConverter.fromRaidenResultsList(raidenResults);
      
      // Combine results: AllAnime first, then Raiden
      return [...allAnimeResults, ...raidenAnime];
    } catch (e) {
      // Raiden API failed, just return AllAnime results
      return allAnimeResults;
    }
  }
  
  return allAnimeResults;
});

// Anime Details Provider
final animeDetailsProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, animeId) async {
  final apiService = ref.watch(animeApiServiceProvider);
  return await apiService.getAnimeInfo(animeId);
});

// Episode Sources Provider (legacy - uses 'sub' by default)
final episodeSourcesProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, episodeId) async {
  final apiService = ref.watch(animeApiServiceProvider);
  return await apiService.getEpisodeSources(episodeId);
});

// Episode Sources Provider with Translation Type
final episodeSourcesWithTypeProvider = FutureProvider.family<Map<String, dynamic>?, ({String episodeId, String translationType})>((ref, params) async {
  final apiService = ref.watch(animeApiServiceProvider);
  return await apiService.getEpisodeSources(params.episodeId, translationType: params.translationType);
});

// Latest Releases Provider
final latestReleasesProvider = FutureProvider.family<List<Map<String, dynamic>>, ({int page, List<String>? genres})>((ref, params) async {
  final apiService = ref.watch(animeApiServiceProvider);
  final prefs = ref.watch(userPreferencesProvider).valueOrNull;
  final allowAdult = prefs?['allowAdult'] as bool? ?? false;
  
  return await apiService.getLatestReleases(
    page: params.page, 
    allowAdult: allowAdult,
    genres: params.genres,
  );
});
