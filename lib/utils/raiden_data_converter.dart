import '../models/anime_model.dart';

/// Helper class to convert Raiden API responses to Anime model
class RaidenDataConverter {
  /// Convert Raiden API result to Anime model
  static Anime fromRaidenResult(Map<String, dynamic> raidenData) {
    // Generate unique ID based on title and URL
    final title = raidenData['title'] as String? ?? 'Unknown';
    final pageUrl = raidenData['page_url'] as String? ?? '';
    
    // Extract a simple ID from the page URL or use title-based ID
    String id;
    if (pageUrl.isNotEmpty) {
      // Extract ID from URL like: https://hanimes.org/series/chainsaw-man-himeno-episode-1/
      final urlParts = pageUrl.split('/');
      id = 'raiden_${urlParts.length > 2 ? urlParts[urlParts.length - 2] : title.replaceAll(' ', '-').toLowerCase()}';
    } else {
      id = 'raiden_${title.replaceAll(' ', '-').toLowerCase()}';
    }
    
    return Anime(
      id: id,
      title: title,
      image: raidenData['thumbnail'] as String?,
      description: null, // Raiden API doesn't provide description
      genres: null, // Raiden API doesn't provide genres
      releaseDate: null,
      status: null,
      totalEpisodes: 1, // Each result is typically a single episode
      subOrDub: 'sub', // Assume sub by default
      source: 'raiden',
    );
  }

  /// Convert list of Raiden API results to list of Anime models
  static List<Anime> fromRaidenResultsList(List<Map<String, dynamic>> raidenDataList) {
    return raidenDataList.map((data) => fromRaidenResult(data)).toList();
  }

  /// Get video URL from Raiden anime
  /// The download_url field contains the direct video link (already domain-fixed by service)
  static String? getVideoUrl(Map<String, dynamic> raidenData) {
    return raidenData['download_url'] as String?;
  }
}
