import 'package:hive/hive.dart';

part 'episode_tracker_model.g.dart';

@HiveType(typeId: 6)
class EpisodeTracker extends HiveObject {
  @HiveField(0)
  String animeId;

  @HiveField(1)
  String animeTitle;

  @HiveField(2)
  int lastKnownEpisodeCount;

  @HiveField(3)
  DateTime lastChecked;

  @HiveField(4)
  String? animeImage;

  EpisodeTracker({
    required this.animeId,
    required this.animeTitle,
    required this.lastKnownEpisodeCount,
    required this.lastChecked,
    this.animeImage,
  });
}
