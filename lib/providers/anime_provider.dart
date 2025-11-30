import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anime_model.dart';
import '../services/anime_api_service.dart';

// API Service Provider
final animeApiServiceProvider = Provider((ref) => AnimeApiService());

// Search Results Provider
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<List<Anime>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];
  
  final apiService = ref.watch(animeApiServiceProvider);
  return await apiService.searchAnime(query);
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
final latestReleasesProvider = FutureProvider.family<List<Map<String, dynamic>>, int>((ref, page) async {
  final apiService = ref.watch(animeApiServiceProvider);
  return await apiService.getLatestReleases(page: page);
});
