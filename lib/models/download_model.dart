import 'package:hive/hive.dart';

part 'download_model.g.dart';

@HiveType(typeId: 3)
class Download {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String animeId;

  @HiveField(2)
  final String animeTitle;

  @HiveField(3)
  final String? animeImage;

  @HiveField(4)
  final String episodeId;

  @HiveField(5)
  final int episodeNumber;

  @HiveField(6)
  final String? episodeTitle;

  @HiveField(7)
  final String downloadUrl;

  @HiveField(8)
  final String quality;

  @HiveField(9)
  final String status;

  @HiveField(10)
  final String? filePath;

  @HiveField(11)
  final int totalBytes;

  @HiveField(12)
  final int downloadedBytes;

  @HiveField(13)
  final DateTime createdAt;

  @HiveField(14)
  final DateTime? completedAt;

  Download({
    required this.id,
    required this.animeId,
    required this.animeTitle,
    this.animeImage,
    required this.episodeId,
    required this.episodeNumber,
    this.episodeTitle,
    required this.downloadUrl,
    required this.quality,
    required this.status,
    this.filePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    required this.createdAt,
    this.completedAt,
  });

  double get progress {
    if (totalBytes == 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  String get progressPercentage {
    return '${(progress * 100).toStringAsFixed(0)}%';
  }

  String get formattedSize {
    if (totalBytes == 0) return 'Unknown';
    final mb = totalBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  Download copyWith({
    String? id,
    String? animeId,
    String? animeTitle,
    String? animeImage,
    String? episodeId,
    int? episodeNumber,
    String? episodeTitle,
    String? downloadUrl,
    String? quality,
    String? status,
    String? filePath,
    int? totalBytes,
    int? downloadedBytes,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return Download(
      id: id ?? this.id,
      animeId: animeId ?? this.animeId,
      animeTitle: animeTitle ?? this.animeTitle,
      animeImage: animeImage ?? this.animeImage,
      episodeId: episodeId ?? this.episodeId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      quality: quality ?? this.quality,
      status: status ?? this.status,
      filePath: filePath ?? this.filePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class DownloadStatus {
  static const String queued = 'queued';
  static const String downloading = 'downloading';
  static const String paused = 'paused';
  static const String completed = 'completed';
  static const String failed = 'failed';
  static const String cancelled = 'cancelled';
}

class DownloadQuality {
  static const String quality360p = '360p';
  static const String quality480p = '480p';
  static const String quality720p = '720p';
  static const String quality1080p = '1080p';

  static const List<String> allQualities = [
    quality360p,
    quality480p,
    quality720p,
    quality1080p,
  ];
}
