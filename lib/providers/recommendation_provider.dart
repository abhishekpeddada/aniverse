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

  if (allAnime.isEmpty) return [];

  return await service.getRecommendations(
    watchHistory: watchHistory,
    allAnime: allAnime,
    limit: 20,
  );
});

final becauseYouWatchedProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(recommendationServiceProvider);
  final watchHistory = ref.watch(historyProvider);

  if (watchHistory.isEmpty) {
    return {'sourceAnime': null, 'recommendations': <Anime>[]};
  }

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

  if (allAnime.isEmpty) {
    return {'sourceAnime': null, 'recommendations': <Anime>[]};
  }

  final recommendations = <Anime>[];
  final seenIds = <String>{};

  final sorted = watchHistory.toList()
    ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));

  for (var i = 0; i < sorted.length && i < 3; i++) {
    final historyItem = sorted[i];
    final sourceAnime = allAnime.firstWhere(
      (anime) => anime.id == historyItem.animeId,
      orElse: () => Anime(
        id: historyItem.animeId,
        title: historyItem.animeTitle,
        image: historyItem.animeImage,
      ),
    );

    final similar = await service.getSimilarAnime(
      sourceAnime: sourceAnime,
      allAnime: allAnime,
      watchHistory: watchHistory,
      limit: 10,
    );

    for (var anime in similar) {
      if (!seenIds.contains(anime.id)) {
        recommendations.add(anime);
        seenIds.add(anime.id);
      }
    }
  }

  final recentAnime = sorted.first;
  final sourceAnime = allAnime.firstWhere(
    (anime) => anime.id == recentAnime.animeId,
    orElse: () => Anime(
      id: recentAnime.animeId,
      title: recentAnime.animeTitle,
      image: recentAnime.animeImage,
    ),
  );

  return {
    'sourceAnime': sourceAnime,
    'recommendations': recommendations.take(15).toList(),
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

  return allAnime.take(15).toList();
});
