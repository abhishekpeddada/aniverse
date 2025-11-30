import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../models/anime_model.dart';
import '../models/episode_model.dart';

class AnimeApiService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: kIsWeb ? {} : {
      'Referer': ApiConstants.referer,
      'User-Agent': ApiConstants.userAgent,
    },
  ));

  AnimeApiService() {
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ));
    }
  }

  Future<List<Anime>> searchAnime(String query) async {
    try {
      debugPrint('🔍 Searching anime: $query');
      
      const searchQuery = r'''
        query($search: SearchInput) {
          shows(search: $search, limit: 40, page: 1) {
            edges {
              _id
              name
              thumbnail
              description
              availableEpisodes
              status
            }
          }
        }
      ''';

      final variables = {
        'search': {
          'allowAdult': false,
          'allowUnknown': false,
          'query': query,
        },
      };

      final response = await _dio.get(
        ApiConstants.apiPath,
        queryParameters: {
          'variables': jsonEncode(variables),
          'query': searchQuery,
        },
      );

      debugPrint('✅ Response status: ${response.statusCode}');

      if (response.data != null && response.data['data'] != null) {
        final shows = response.data['data']['shows']['edges'] as List;
        debugPrint('✅ Found ${shows.length} results');
        
        return shows.map((show) {
          return Anime.fromJson({
            'id': show['_id'],
            'title': show['name'],
            'image': show['thumbnail'],
            'description': show['description'],
            'totalEpisodes': _parseEpisodeCount(show['availableEpisodes']),
            'status': show['status'],
          });
        }).toList();
      }

      debugPrint('⚠️ No results in response');
      return [];
    } catch (e, stackTrace) {
      debugPrint('❌ Error searching anime: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      return [];
    }
  }

  int? _parseEpisodeCount(dynamic availableEpisodes) {
    if (availableEpisodes == null) return null;
    if (availableEpisodes is Map) {
      final sub = availableEpisodes['sub'];
      if (sub is int) return sub;
      final dub = availableEpisodes['dub'];
      if (dub is int) return dub;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getAnimeInfo(String animeId) async {
    try {
      debugPrint('📖 Getting anime info: $animeId');

      const episodesQuery = r'''
        query($showId: String!) {
          show(_id: $showId) {
            _id
            name
            thumbnail
            description
            status
            availableEpisodesDetail
          }
        }
      ''';

      final variables = {'showId': animeId};

      final response = await _dio.get(
        ApiConstants.apiPath,
        queryParameters: {
          'variables': jsonEncode(variables),
          'query': episodesQuery,
        },
      );

      debugPrint('✅ Anime info response: ${response.statusCode}');

      if (response.data != null && response.data['data'] != null) {
        final show = response.data['data']['show'];
        
        final anime = Anime.fromJson({
          'id': show['_id'],
          'title': show['name'],
          'image': show['thumbnail'],
          'description': show['description'],
          'status': show['status'],
        });

        final episodesList = <Episode>[];
        final availableEpisodes = show['availableEpisodesDetail'];
        if (availableEpisodes != null && availableEpisodes is Map) {
          final subEpisodes = availableEpisodes['sub'] as List?;
          if (subEpisodes != null) {
            for (var epNum in subEpisodes) {
              final epString = epNum.toString();
              episodesList.add(Episode(
                id: '$animeId-$epString',
                number: int.tryParse(epString) ?? 0,
                title: 'Episode $epString',
                url: epString,
              ));
            }
          }
        }

        episodesList.sort((a, b) => a.number.compareTo(b.number));
        
        debugPrint('✅ Found ${episodesList.length} episodes');

        return {
          'anime': anime,
          'episodes': episodesList,
        };
      }
      return null;
    } catch (e, stackTrace) {
      debugPrint('❌ Error getting anime info: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getEpisodeSources(
    String episodeId, {
    String translationType = 'sub', // 'sub' or 'dub'
  }) async {
    try {
      debugPrint('🎬 Getting episode sources: $episodeId (type: $translationType)');

      final parts = episodeId.split('-');
      if (parts.length < 2) return null;
      
      final showId = parts[0];
      final episodeString = parts.sublist(1).join('-');

      const sourceQuery = r'''
        query($showId: String!, $translationType: VaildTranslationTypeEnumType!, $episodeString: String!) {
          episode(showId: $showId, translationType: $translationType, episodeString: $episodeString) {
            episodeString
            sourceUrls
          }
        }
      ''';

      final variables = {
        'showId': showId,
        'translationType': translationType,
        'episodeString': episodeString,
      };

      final response = await _dio.get(
        ApiConstants.apiPath,
        queryParameters: {
          'variables': jsonEncode(variables),
          'query': sourceQuery,
        },
      );

      debugPrint('✅ Episode sources response: ${response.statusCode}');

      if (response.data != null && response.data['data'] != null) {
        final episode = response.data['data']['episode'];
        final sourceUrls = episode['sourceUrls'] as List?;
        
        if (sourceUrls != null && sourceUrls.isNotEmpty) {
          final sources = <Map<String, dynamic>>[];
          
          for (var source in sourceUrls) {
            final sourceUrl = source['sourceUrl'] as String?;
            final sourceName = source['sourceName'] as String?;
            final sourceType = source['type'] as String?;
            final priority = source['priority'] as num?;
            
            if (sourceUrl != null && sourceType != 'iframe') {
              final decodedUrl = _decodeAllAnimeUrl(sourceUrl);
              if (decodedUrl != null && decodedUrl.isNotEmpty) {
                debugPrint('📺 Source: $sourceName ($priority) - ${decodedUrl.substring(0, decodedUrl.length > 50 ? 50 : decodedUrl.length)}...');
                sources.add({
                  'url': decodedUrl,
                  'quality': _extractQuality(sourceName, decodedUrl),
                  'isM3U8': decodedUrl.contains('.m3u8'),
                  'sourceName': sourceName ?? 'Unknown',
                  'priority': priority ?? 0,
                });
              }
            }
          }

          sources.sort((a, b) => (b['priority'] as num).compareTo(a['priority'] as num));

          if (sources.isNotEmpty) {
            debugPrint('✅ Found ${sources.length} video sources');
          }
          
          return {
            'sources': sources,
            'translationType': translationType,
          };
        }
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('❌ Error getting episode sources: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      return null;
    }
  }

  String _extractQuality(String? sourceName, String url) {
    // Try to extract quality from source name
    if (sourceName != null) {
      final qualityRegex = RegExp(r'(\d{3,4})[pP]');
      final match = qualityRegex.firstMatch(sourceName);
      if (match != null) {
        return '${match.group(1)}p';
      }
    }
    
    // Default quality labels based on source name
    if (sourceName?.contains('1080') == true) return '1080p';
    if (sourceName?.contains('720') == true) return '720p';
    if (sourceName?.contains('480') == true) return '480p';
    if (sourceName?.contains('360') == true) return '360p';
    
    // For M3U8, it's usually adaptive quality
    if (url.contains('.m3u8')) return 'Auto';
    
    return 'Default';
  }

  Future<List<Map<String, dynamic>>> getLatestReleases({int page = 1, int limit = 30}) async {
    try {
      debugPrint('📅 Fetching latest releases (page: $page, limit: $limit)');

      const latestQuery = r'''
        query($search: SearchInput, $limit: Int, $page: Int, $sortBy: SearchSortEnum) {
          shows(search: $search, limit: $limit, page: $page, sortBy: $sortBy) {
            edges {
              _id
              name
              thumbnail
              availableEpisodes
            }
          }
        }
      ''';

      final variables = {
        'search': {
          'allowAdult': false,
          'allowUnknown': false,
        },
        'limit': limit,
        'page': page,
        'sortBy': 'Latest_Update',  // Sort by most recent updates
      };

      final response = await _dio.get(
        ApiConstants.apiPath,
        queryParameters: {
          'variables': jsonEncode(variables),
          'query': latestQuery,
        },
      );

      debugPrint('✅ Latest releases response: ${response.statusCode}');

      if (response.data != null && response.data['data'] != null) {
        final shows = response.data['data']['shows']['edges'] as List;
        debugPrint('✅ Found ${shows.length} latest releases');

        return shows.map((show) {
          final availableEps = show['availableEpisodes'] as Map?;
          
          return {
            'id': show['_id'],
            'title': show['name'],
            'image': show['thumbnail'],
            'latestEpisode': _parseLatestEpisode(availableEps, null),
            'hasSubbed': availableEps?['sub'] != null,
            'hasDubbed': availableEps?['dub'] != null,
          };
        }).toList();
      }

      return [];
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching latest releases: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      return [];
    }
  }

  String _parseLatestEpisode(Map? availableEps, Map? lastEpInfo) {
    if (lastEpInfo != null) {
      final subEp = lastEpInfo['sub'];
      final dubEp = lastEpInfo['dub'];
      if (subEp != null) return 'Ep $subEp';
      if (dubEp != null) return 'Ep $dubEp';
    }
    
    if (availableEps != null) {
      final subCount = availableEps['sub'];
      final dubCount = availableEps['dub'];
      if (subCount != null) return 'Ep $subCount';
      if (dubCount != null) return 'Ep $dubCount';
    }
    
    return 'New';
  }

  String? _decodeAllAnimeUrl(String encodedUrl) {
    try {
      if (!encodedUrl.startsWith('--')) return encodedUrl;
      
      final encoded = encodedUrl.substring(2);
      final decoded = StringBuffer();
      
      for (int i = 0; i < encoded.length; i += 2) {
        if (i + 1 >= encoded.length) break;
        final hexChar = encoded.substring(i, i + 2);
        final charCode = int.parse(hexChar, radix: 16);
        
        final transformed = _transformChar(charCode);
        if (transformed != null) {
          decoded.write(transformed);
        }
      }
      
      String result = decoded.toString();
      if (result.contains('/clock')) {
        result = result.replaceAll('/clock', '/clock.json');
      }
      
      return result;
    } catch (e) {
      debugPrint('Error decoding URL: $e');
      return null;
    }
  }

  String? _transformChar(int code) {
    const charMap = {
      0x79: 'A', 0x7a: 'B', 0x7b: 'C', 0x7c: 'D', 0x7d: 'E', 0x7e: 'F', 0x7f: 'G',
      0x70: 'H', 0x71: 'I', 0x72: 'J', 0x73: 'K', 0x74: 'L', 0x75: 'M', 0x76: 'N', 0x77: 'O',
      0x68: 'P', 0x69: 'Q', 0x6a: 'R', 0x6b: 'S', 0x6c: 'T', 0x6d: 'U', 0x6e: 'V', 0x6f: 'W',
      0x60: 'X', 0x61: 'Y', 0x62: 'Z',
      0x59: 'a', 0x5a: 'b', 0x5b: 'c', 0x5c: 'd', 0x5d: 'e', 0x5e: 'f', 0x5f: 'g',
      0x50: 'h', 0x51: 'i', 0x52: 'j', 0x53: 'k', 0x54: 'l', 0x55: 'm', 0x56: 'n', 0x57: 'o',
      0x48: 'p', 0x49: 'q', 0x4a: 'r', 0x4b: 's', 0x4c: 't', 0x4d: 'u', 0x4e: 'v', 0x4f: 'w',
      0x40: 'x', 0x41: 'y', 0x42: 'z',
      0x08: '0', 0x09: '1', 0x0a: '2', 0x0b: '3', 0x0c: '4', 0x0d: '5', 0x0e: '6', 0x0f: '7',
      0x00: '8', 0x01: '9',
      0x15: '-', 0x16: '.', 0x67: '_', 0x46: '~', 0x02: ':', 0x17: '/', 0x07: '?', 0x1b: '#',
      0x63: '[', 0x65: ']', 0x78: '@', 0x19: '!', 0x1c: '\$', 0x1e: '&', 0x10: '(', 0x11: ')',
      0x12: '*', 0x13: '+', 0x14: ',', 0x03: ';', 0x05: '=', 0x1d: '%',
    };
    
    return charMap[code];
  }
}
