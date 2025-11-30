import 'package:hive/hive.dart';

part 'anime_model.g.dart';

@HiveType(typeId: 0)
class Anime {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? image;

  @HiveField(3)
  final String? description;

  @HiveField(4)
  final List<String>? genres;

  @HiveField(5)
  final String? releaseDate;

  @HiveField(6)
  final String? status;

  @HiveField(7)
  final int? totalEpisodes;

  @HiveField(8)
  final String? subOrDub;

  Anime({
    required this.id,
    required this.title,
    this.image,
    this.description,
    this.genres,
    this.releaseDate,
    this.status,
    this.totalEpisodes,
    this.subOrDub,
  });

  factory Anime.fromJson(Map<String, dynamic> json) {
    return Anime(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      image: json['image'],
      description: json['description'],
      genres: json['genres'] != null 
          ? List<String>.from(json['genres'])
          : null,
      releaseDate: json['releaseDate'],
      status: json['status'],
      totalEpisodes: json['totalEpisodes'],
      subOrDub: json['subOrDub'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'image': image,
      'description': description,
      'genres': genres,
      'releaseDate': releaseDate,
      'status': status,
      'totalEpisodes': totalEpisodes,
      'subOrDub': subOrDub,
    };
  }
}
