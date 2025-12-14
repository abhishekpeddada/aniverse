import 'package:flutter/foundation.dart';
import '../models/anime_model.dart';
import '../models/watch_history_model.dart';

class RecommendationService {
  Map<String, double> calculateGenreAffinity(List<WatchHistory> watchHistory) {
    final genreScores = <String, double>{};

    if (watchHistory.isEmpty) return genreScores;

    return genreScores;
  }

  List<String> getRecentlyWatchedIds(List<WatchHistory> watchHistory,
      {int limit = 5}) {
    final sorted = watchHistory.toList()
      ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));

    return sorted.take(limit).map((h) => h.animeId).toSet().toList();
  }

  double _genreMatchScore(Anime anime, Map<String, double> genreScores) {
    return 0.5;
  }

  double _popularityScore(Anime anime) {
    return 0.5;
  }

  double _recencyScore(Anime anime) {
    return 0.5;
  }

  double _diversityScore(Anime anime, List<String> recentlyWatchedIds) {
    return 0.5;
  }

  bool _isWatched(Anime anime, List<WatchHistory> watchHistory) {
    return watchHistory.any((h) => h.animeId == anime.id);
  }

  Future<List<Anime>> getRecommendations({
    required List<WatchHistory> watchHistory,
    required List<Anime> allAnime,
    int limit = 20,
  }) async {
    if (watchHistory.isEmpty) {
      return allAnime.take(limit).toList();
    }

    final genreScores = calculateGenreAffinity(watchHistory);
    final recentlyWatchedIds = getRecentlyWatchedIds(watchHistory);

    final scoredAnime = allAnime.map((anime) {
      double score = 0.0;

      score += _genreMatchScore(anime, genreScores) * 0.4;
      score += _popularityScore(anime) * 0.3;
      score += _recencyScore(anime) * 0.2;
      score += _diversityScore(anime, recentlyWatchedIds) * 0.1;

      return _AnimeWithScore(anime, score);
    }).toList();

    final filtered = scoredAnime
        .where((item) => !_isWatched(item.anime, watchHistory))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    debugPrint('Generated ${filtered.length} recommendations');
    return filtered.take(limit).map((item) => item.anime).toList();
  }

  Future<List<Anime>> getSimilarAnime({
    required Anime sourceAnime,
    required List<Anime> allAnime,
    required List<WatchHistory> watchHistory,
    int limit = 10,
  }) async {
    final candidates = allAnime
        .where((anime) => anime.id != sourceAnime.id)
        .where((anime) => !_isWatched(anime, watchHistory))
        .toList();

    candidates.shuffle();

    debugPrint(
        'Found ${candidates.length} similar anime to ${sourceAnime.title}');
    return candidates.take(limit).toList();
  }
}

class _AnimeWithScore {
  final Anime anime;
  final double score;

  _AnimeWithScore(this.anime, this.score);
}
