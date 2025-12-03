import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class RaidenApiService {
  final Dio _dio = Dio();
  static const String _baseUrl = 'https://api.raiden.ovh';

  /// Fetch adult anime list from Raiden API
  /// Returns list of anime with title, thumbnail, and download URL
  Future<List<Map<String, dynamic>>> getAdultAnime({int page = 1}) async {
    try {
      debugPrint('🔞 Fetching adult anime from Raiden API (page: $page)');
      
      final response = await _dio.get(
        '$_baseUrl/hanime',
        queryParameters: {'page': page},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>?;
        
        if (results != null && results.isNotEmpty) {
          debugPrint('✅ Fetched ${results.length} adult anime from Raiden');
          
          // Apply domain fix to all download URLs
          return results.map((item) {
            final anime = item as Map<String, dynamic>;
            // Fix domain from .city to .fit
            if (anime['download_url'] != null) {
              anime['download_url'] = (anime['download_url'] as String)
                  .replaceAll('hanime.city', 'hanime.fit');
            }
            return anime;
          }).toList();
        }
      }
      
      debugPrint('⚠️ No results from Raiden API');
      return [];
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching from Raiden API: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Search adult anime by filtering results locally
  /// Since Raiden API doesn't have a search endpoint, we fetch all and filter
  Future<List<Map<String, dynamic>>> searchAdultAnime(String query) async {
    try {
      if (query.trim().isEmpty) return [];
      
      debugPrint('🔍 Searching adult anime for: "$query"');
      
      // Fetch first page and filter by title
      final allAnime = await getAdultAnime(page: 1);
      
      final filtered = allAnime.where((anime) {
        final title = (anime['title'] as String? ?? '').toLowerCase();
        return title.contains(query.toLowerCase());
      }).toList();
      
      debugPrint('✅ Found ${filtered.length} matches for "$query"');
      return filtered;
    } catch (e) {
      debugPrint('❌ Error searching adult anime: $e');
      return [];
    }
  }

  /// Get video source URL with domain fix applied
  /// This ensures the URL uses the correct domain (.fit instead of .city)
  String getVideoSource(String downloadUrl) {
    return downloadUrl.replaceAll('hanime.city', 'hanime.fit');
  }

  /// Check if a URL is from Raiden API
  bool isRaidenSource(String url) {
    return url.contains('hanime.fit') || url.contains('hanimes.org');
  }
}
