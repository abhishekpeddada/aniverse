import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anime_model.dart';
import '../services/recommendation_service.dart';
import './history_provider.dart';
import './anime_provider.dart';

final recommendationServiceProvider =
    Provider((ref) => RecommendationService());

final recommendationsProvider = FutureProvider<List<Anime>>((ref) async {
  final service = ref.watch(recommendationServiceProvider);
  final watchHistory = ref.watch(historyProvider);

  // Fetch all available pages until we get empty results
  final List<Map<String, dynamic>> allReleases = [];
  int page = 1;
  while (true) {
    try {
      final releases = await ref.watch(
        latestReleasesProvider((page: page, genres: null)).future,
      );
      if (releases.isEmpty) break;
      allReleases.addAll(releases);
      page++;
      // Safety limit to prevent infinite loop
      if (page > 50) break;
    } catch (_) {
      break;
    }
  }

  final allAnime = allReleases
      .map((item) {
        final thumbnail = item['thumbnail'] ?? item['image'];
        if (thumbnail == null ||
            thumbnail.toString().isEmpty ||
            thumbnail.toString().startsWith('mcovers/')) {
          return null;
        }
        return Anime(
          id: item['id'] ?? '',
          title: item['name'] ?? '',
          image: thumbnail,
          description: item['description'],
          genres:
              item['genres'] != null ? List<String>.from(item['genres']) : null,
          source: 'allanime',
        );
      })
      .where((anime) => anime != null)
      .cast<Anime>()
      .toList();

  // Remove duplicates by ID
  final seenIds = <String>{};
  final uniqueAnime = allAnime.where((a) {
    if (seenIds.contains(a.id)) return false;
    seenIds.add(a.id);
    return true;
  }).toList();

  if (uniqueAnime.isEmpty) return [];

  return await service.getRecommendations(
    watchHistory: watchHistory,
    allAnime: uniqueAnime,
    limit: 12,
  );
});

final becauseYouWatchedProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(recommendationServiceProvider);
  final watchHistory = ref.watch(historyProvider);

  if (watchHistory.isEmpty) {
    return {'sourceAnime': null, 'recommendations': <Anime>[]};
  }

  // Fetch all available pages
  final List<Map<String, dynamic>> allReleases = [];
  int page = 1;
  while (true) {
    try {
      final releases = await ref.watch(
        latestReleasesProvider((page: page, genres: null)).future,
      );
      if (releases.isEmpty) break;
      allReleases.addAll(releases);
      page++;
      if (page > 50) break;
    } catch (_) {
      break;
    }
  }

  final allAnime = allReleases
      .map((item) {
        final thumbnail = item['thumbnail'] ?? item['image'];
        if (thumbnail == null ||
            thumbnail.toString().isEmpty ||
            thumbnail.toString().startsWith('mcovers/')) {
          return null;
        }
        return Anime(
          id: item['id'] ?? '',
          title: item['name'] ?? '',
          image: thumbnail,
          description: item['description'],
          genres:
              item['genres'] != null ? List<String>.from(item['genres']) : null,
          source: 'allanime',
        );
      })
      .where((anime) => anime != null)
      .cast<Anime>()
      .toList();

  // Remove duplicates
  final seenIds = <String>{};
  final uniqueAnime = allAnime.where((a) {
    if (seenIds.contains(a.id)) return false;
    seenIds.add(a.id);
    return true;
  }).toList();

  if (uniqueAnime.isEmpty) {
    return {'sourceAnime': null, 'recommendations': <Anime>[]};
  }

  final recommendations = <Anime>[];
  final recommendationIds = <String>{};

  final sorted = watchHistory.toList()
    ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));

  for (var i = 0; i < sorted.length && i < 3; i++) {
    final historyItem = sorted[i];
    final sourceAnime = uniqueAnime.firstWhere(
      (anime) => anime.id == historyItem.animeId,
      orElse: () => Anime(
        id: historyItem.animeId,
        title: historyItem.animeTitle,
        image: historyItem.animeImage,
      ),
    );

    final similar = await service.getSimilarAnime(
      sourceAnime: sourceAnime,
      allAnime: uniqueAnime,
      watchHistory: watchHistory,
      limit: 10,
    );

    for (var anime in similar) {
      if (!recommendationIds.contains(anime.id)) {
        recommendations.add(anime);
        recommendationIds.add(anime.id);
      }
    }
  }

  final recentAnime = sorted.first;
  final sourceAnime = uniqueAnime.firstWhere(
    (anime) => anime.id == recentAnime.animeId,
    orElse: () => Anime(
      id: recentAnime.animeId,
      title: recentAnime.animeTitle,
      image: recentAnime.animeImage,
    ),
  );

  return {
    'sourceAnime': sourceAnime,
    'recommendations': recommendations.take(12).toList(),
  };
});

final genrePreferencesProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final service = ref.watch(recommendationServiceProvider);
  final watchHistory = ref.watch(historyProvider);

  return service.calculateGenreAffinity(watchHistory);
});

final trendingAnimeProvider = FutureProvider<List<Anime>>((ref) async {
  final latestReleases =
      await ref.watch(latestReleasesProvider((page: 1, genres: null)).future);
  final allAnime = latestReleases
      .map((item) {
        final thumbnail = item['thumbnail'] ?? item['image'];
        if (thumbnail == null ||
            thumbnail.toString().isEmpty ||
            thumbnail.toString().startsWith('mcovers/')) {
          return null;
        }
        return Anime(
          id: item['id'] ?? '',
          title: item['name'] ?? '',
          image: thumbnail,
          description: item['description'],
          genres:
              item['genres'] != null ? List<String>.from(item['genres']) : null,
          source: 'allanime',
        );
      })
      .where((anime) => anime != null)
      .cast<Anime>()
      .toList();

  return allAnime.take(12).toList();
});
