import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class RaidenApiService {
  // Without timeouts one unresponsive page stalls the whole list.
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));
  static const String _baseUrl = 'https://api.raiden.ovh';

  /// Headers for playing and downloading Raiden videos. They are direct file
  /// links, so no Referer is sent for hotlink protection to reject.
  static const Map<String, String> streamHeaders = {
    'User-Agent':
        'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
  };

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
          
          // Scrape every page at once rather than one after another.
          final processed = await Future.wait(
            results.map((item) => _withVideoUrl(item as Map<String, dynamic>)),
          );
          return processed.whereType<Map<String, dynamic>>().toList();
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

  /// Fills in the scraped video URL, falling back to the API's own link with
  /// the domain fix. Returns null when there's no usable link.
  Future<Map<String, dynamic>?> _withVideoUrl(Map<String, dynamic> anime) async {
    final pageUrl = anime['page_url'] as String?;
    if (pageUrl == null) return null;

    final videoUrl = await _scrapeVideoUrl(pageUrl);
    if (videoUrl != null) {
      anime['download_url'] = videoUrl;
      return anime;
    }

    debugPrint('⚠️ Failed to scrape URL from $pageUrl');
    final apiUrl = anime['download_url'] as String?;
    if (apiUrl == null) return null;
    anime['download_url'] = getVideoSource(apiUrl);
    return anime;
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
