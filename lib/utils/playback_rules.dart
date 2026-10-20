import '../models/episode_model.dart';
import '../models/watch_history_model.dart';

/// An intro ("op") or outro ("ed") segment that can be skipped.
class SkipSegment {
  const SkipSegment({required this.type, required this.start, required this.end});

  /// 'op' (intro) or 'ed' (outro), as AniSkip names them.
  final String type;
  final Duration start;
  final Duration end;

  String get label => type == 'op' ? 'Skip Intro' : 'Skip Outro';
}

/// Small, I/O-free rules behind playback features, kept separate for testing.
class PlaybackRules {
  /// Progress past which an episode counts as watched.
  static const watchedFraction = 0.9;

  static bool isFinished(WatchHistory history) =>
      history.durationMs > 0 &&
      history.positionMs >= history.durationMs * watchedFraction;

  /// The episode after [currentNumber] in [episodes], if any.
  static Episode? nextEpisode(List<Episode> episodes, int currentNumber) {
    Episode? next;
    for (final episode in episodes) {
      if (episode.number > currentNumber &&
          (next == null || episode.number < next.number)) {
        next = episode;
      }
    }
    return next;
  }

  /// The episode to highlight as "continue watching": the most recently
  /// watched one, or the one after it once it's finished. Falls back to
  /// [fallback] when there's no history for the anime.
  static String? continueEpisodeId({
    required List<WatchHistory> history,
    required String animeId,
    required List<Episode> episodes,
    String? fallback,
  }) {
    WatchHistory? latest;
    for (final entry in history) {
      if (entry.animeId != animeId) continue;
      if (latest == null || entry.lastWatched.isAfter(latest.lastWatched)) {
        latest = entry;
      }
    }
    if (latest == null) return fallback;
    if (!isFinished(latest)) return latest.episodeId;
    return nextEpisode(episodes, latest.episodeNumber)?.id ?? latest.episodeId;
  }

  /// Parses an AniSkip v1 response:
  /// `{"found":true,"results":[{"interval":{"start_time":..,"end_time":..},"skip_type":"op"}]}`.
  static List<SkipSegment> parseSkipTimes(Map<String, dynamic> json) {
    if (json['found'] != true) return const [];
    final results = json['results'];
    if (results is! List) return const [];

    final segments = <SkipSegment>[];
    for (final result in results) {
      if (result is! Map) continue;
      final type = result['skip_type'];
      final interval = result['interval'];
      if ((type != 'op' && type != 'ed') || interval is! Map) continue;
      final start = interval['start_time'];
      final end = interval['end_time'];
      if (start is! num || end is! num || end <= start) continue;
      segments.add(SkipSegment(
        type: type as String,
        start: Duration(milliseconds: (start * 1000).round()),
        end: Duration(milliseconds: (end * 1000).round()),
      ));
    }
    return segments;
  }

  static Map<String, dynamic> segmentToJson(SkipSegment segment) => {
        'type': segment.type,
        'startMs': segment.start.inMilliseconds,
        'endMs': segment.end.inMilliseconds,
      };

  static SkipSegment? segmentFromJson(Map json) {
    final type = json['type'];
    final start = json['startMs'];
    final end = json['endMs'];
    if (type is! String || start is! int || end is! int) return null;
    return SkipSegment(
      type: type,
      start: Duration(milliseconds: start),
      end: Duration(milliseconds: end),
    );
  }

  /// The segment covering [position], if any. The last second of a segment
  /// is excluded so the button doesn't flash just as it ends on its own.
  static SkipSegment? activeSkip(List<SkipSegment> segments, Duration position) {
    for (final segment in segments) {
      if (position >= segment.start &&
          position < segment.end - const Duration(seconds: 1)) {
        return segment;
      }
    }
    return null;
  }
}
