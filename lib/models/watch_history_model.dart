import 'package:hive/hive.dart';

part 'watch_history_model.g.dart';

@HiveType(typeId: 2)
class WatchHistory {
  @HiveField(0)
  final String animeId;

  @HiveField(1)
  final String animeTitle;

  @HiveField(2)
  final String? animeImage;

  @HiveField(3)
  final int episodeNumber;

  @HiveField(4)
  final String episodeId;

  @HiveField(5)
  final int positionMs;

  @HiveField(6)
  final int durationMs;

  @HiveField(7)
  final DateTime lastWatched;

  WatchHistory({
    required this.animeId,
    required this.animeTitle,
    this.animeImage,
    required this.episodeNumber,
    required this.episodeId,
    required this.positionMs,
    required this.durationMs,
    required this.lastWatched,
  });

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  double get progress => durationMs > 0 
      ? positionMs / durationMs 
      : 0.0;

  bool get isCompleted => progress > 0.9;

  WatchHistory copyWith({
    int? positionMs,
    int? durationMs,
    DateTime? lastWatched,
  }) {
    return WatchHistory(
      animeId: animeId,
      animeTitle: animeTitle,
      animeImage: animeImage,
      episodeNumber: episodeNumber,
      episodeId: episodeId,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      lastWatched: lastWatched ?? this.lastWatched,
    );
  }
}
