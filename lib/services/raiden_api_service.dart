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
          
          final List<Map<String, dynamic>> processedResults = [];
          
          for (var item in results) {
            final anime = item as Map<String, dynamic>;
            final pageUrl = anime['page_url'] as String?;
            
            if (pageUrl != null) {
              try {
                final videoUrl = await _scrapeVideoUrl(pageUrl);
                if (videoUrl != null) {
                  anime['download_url'] = videoUrl;
                  processedResults.add(anime);
                  debugPrint('✅ Scraped URL from $pageUrl');
                } else {
                  debugPrint('⚠️ Failed to scrape URL from $pageUrl');
                  if (anime['download_url'] != null) {
                    anime['download_url'] = (anime['download_url'] as String)
                        .replaceAll('hanime.city', 'rule34.city');
                    processedResults.add(anime);
                  }
                }
              } catch (e) {
                debugPrint('⚠️ Error scraping $pageUrl: $e');
                if (anime['download_url'] != null) {
                  anime['download_url'] = (anime['download_url'] as String)
                      .replaceAll('hanime.city', 'rule34.city');
                  processedResults.add(anime);
                }
              }
            }
          }
          
          return processedResults;
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
    return downloadUrl.replaceAll('hanime.city', 'rule34.city');
  }

  /// Check if a URL is from Raiden API
  bool isRaidenSource(String url) {
    return url.contains('hanime.fit') || 
           url.contains('hanimes.org') || 
           url.contains('rule34.city') || 
           url.contains('rule34video.city');
  }

  Future<String?> _scrapeVideoUrl(String pageUrl) async {
    try {
      debugPrint('🕷️ Scraping video URL from: $pageUrl');
      
      final response = await _dio.get(pageUrl);
      
      if (response.statusCode == 200 && response.data != null) {
        final html = response.data as String;
        
        final sourceRegex = RegExp(r'<source\s+src="([^"]+)"', caseSensitive: false);
        final match = sourceRegex.firstMatch(html);
        
        if (match != null && match.groupCount >= 1) {
          final videoUrl = match.group(1);
          debugPrint('✅ Found video URL: $videoUrl');
          return videoUrl;
        }
        
        final downloadRegex = RegExp(r"window\.open\('([^']+)'", caseSensitive: false);
        final downloadMatch = downloadRegex.firstMatch(html);
        
        if (downloadMatch != null && downloadMatch.groupCount >= 1) {
          final videoUrl = downloadMatch.group(1);
          debugPrint('✅ Found video URL from download button: $videoUrl');
          return videoUrl;
        }
        
        debugPrint('⚠️ No video URL pattern found in page HTML');
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Error scraping video URL: $e');
      return null;
    }
  }
}
