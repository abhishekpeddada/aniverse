import 'package:hive/hive.dart';

part 'episode_model.g.dart';

@HiveType(typeId: 1)
class Episode {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final int number;

  @HiveField(2)
  final String? title;

  @HiveField(3)
  final String? url;

  Episode({
    required this.id,
    required this.number,
    this.title,
    this.url,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id'] ?? '',
      number: json['number'] ?? 0,
      title: json['title'],
      url: json['url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'title': title,
      'url': url,
    };
  }
}
