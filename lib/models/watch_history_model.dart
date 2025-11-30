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
  final Duration position;

  @HiveField(6)
  final Duration duration;

  @HiveField(7)
  final DateTime lastWatched;

  WatchHistory({
    required this.animeId,
    required this.animeTitle,
    this.animeImage,
    required this.episodeNumber,
    required this.episodeId,
    required this.position,
    required this.duration,
    required this.lastWatched,
  });

  double get progress => duration.inMilliseconds > 0 
      ? position.inMilliseconds / duration.inMilliseconds 
      : 0.0;

  bool get isCompleted => progress > 0.9; // Consider 90% as completed

  WatchHistory copyWith({
    Duration? position,
    Duration? duration,
    DateTime? lastWatched,
  }) {
    return WatchHistory(
      animeId: animeId,
      animeTitle: animeTitle,
      animeImage: animeImage,
      episodeNumber: episodeNumber,
      episodeId: episodeId,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      lastWatched: lastWatched ?? this.lastWatched,
    );
  }
}
