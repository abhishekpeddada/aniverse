import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../models/anime_model.dart';
import '../models/episode_model.dart';
import 'hianime_service.dart';

class AnimeApiService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: kIsWeb
        ? {'Content-Type': 'application/json'}
        : {
            'Content-Type': 'application/json',
            'Referer': ApiConstants.referer,
            'User-Agent': ApiConstants.userAgent,
          },
  ));

  final HianimeService _hianime = HianimeService();
  final Map<String, List<String>> _titleCache = {};

  /// Why the last [getEpisodeSources] call found nothing, for the UI to show.
  String? lastSourceError;

  AnimeApiService() {
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ));
    }
  }

  Future<List<Anime>> searchAnime(String query, {bool allowAdult = false}) async {
    try {
      debugPrint('🔍 Searching anime: $query (adult: $allowAdult)');

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
          'allowAdult': allowAdult,
          'allowUnknown': false,
          'query': query,
        },
      };

      final response = await _dio.post(
        ApiConstants.apiPath,
        data: {
          'variables': variables,
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

      final response = await _dio.post(
        ApiConstants.apiPath,
        data: {
          'variables': variables,
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

  /// The number of subbed episodes out (dubbed when there's no sub), or null
  /// when the lookup fails, so a failed request isn't mistaken for zero.
  Future<int?> getEpisodeCount(String showId) async {
    try {
      final response = await _dio.post(
        ApiConstants.apiPath,
        data: {
          'variables': {'showId': showId},
          'query': r'query($showId: String!) { show(_id: $showId) { availableEpisodes } }',
        },
      );
      final episodes = response.data?['data']?['show']?['availableEpisodes'];
      if (episodes is! Map) return null;
      final sub = episodes['sub'];
      final dub = episodes['dub'];
      if (sub is int && sub > 0) return sub;
      return dub is int ? dub : null;
    } catch (e) {
      debugPrint('❌ Error getting episode count for $showId: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getEpisodeSources(
    String episodeId, {
    String translationType = 'sub', // 'sub' or 'dub'
  }) async {
    lastSourceError = null;
    var stage = 'parsing episode id';
    try {
      debugPrint('🎬 Getting episode sources: $episodeId (type: $translationType)');

      final parts = episodeId.split('-');
      if (parts.length < 2) {
        lastSourceError = 'Unexpected episode id "$episodeId"';
        return null;
      }

      final showId = parts[0];
      final episodeString = parts.sublist(1).join('-');

      // The catalog comes from AllAnime, but its stream endpoint is gone, so
      // streams are resolved on hianime (ani-cli's provider) by show title.
      stage = 'looking up the show title';
      final titles = await _showTitles(showId);

      stage = 'fetching the stream from hianime';
      final sources = await _hianime.getSources(
        titles: titles,
        episodeNumber: episodeString,
        translationType: translationType,
      );

      debugPrint('✅ Found ${sources.length} video sources');
      return {
        'sources': sources,
        'translationType': translationType,
      };
    } catch (e, stackTrace) {
      lastSourceError = 'Failed while $stage: ${_describeError(e)}';
      debugPrint('❌ Error getting episode sources: $lastSourceError');
      debugPrint('📍 Stack trace: $stackTrace');
      return null;
    }
  }

  /// Titles to search hianime with: AllAnime's name first, then the English
  /// and alternative names when the API provides them.
  Future<List<String>> _showTitles(String showId) async {
    final cached = _titleCache[showId];
    if (cached != null) return cached;

    Future<Map?> fetch(String fields) async {
      final response = await _dio.post(
        ApiConstants.apiPath,
        data: {
          'variables': {'showId': showId},
          'query': 'query(\$showId: String!) { show(_id: \$showId) { $fields } }',
        },
      );
      final data = response.data;
      if (data is! Map || data['errors'] != null) return null;
      return data['data']?['show'] as Map?;
    }

    final show = await fetch('name englishName altNames') ?? await fetch('name');
    if (show == null) {
      throw StateError('AllAnime has no show $showId');
    }

    final titles = <String>{
      for (final title in [
        show['name'],
        show['englishName'],
        ...?(show['altNames'] as List?)?.take(3),
      ])
        if (title is String && title.trim().isNotEmpty) title.trim(),
    }.toList();
    if (titles.isEmpty) throw StateError('Show $showId has no title');

    _titleCache[showId] = titles;
    return titles;
  }

  String _describeError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final host = e.requestOptions.uri.host;
      if (status != null) return 'HTTP $status from $host';
      return '${e.type.name} contacting $host${e.message == null ? '' : ': ${e.message}'}';
    }
    if (e is HianimeException) return e.message;
    final text = e.toString();
    return text.length <= 200 ? text : '${text.substring(0, 200)}…';
  }

  Future<List<Map<String, dynamic>>> getLatestReleases({
    int page = 1,
    int limit = 30,
    bool allowAdult = false,
    List<String>? genres,
  }) async {
    try {
      debugPrint('📅 Fetching latest releases (page: $page, limit: $limit, adult: $allowAdult, genres: $genres)');

      const latestQuery = r'''
        query($search: SearchInput, $limit: Int, $page: Int) {
          shows(search: $search, limit: $limit, page: $page) {
            edges {
              _id
              name
              thumbnail
              availableEpisodes
            }
          }
        }
      ''';

      final searchInput = {
        'allowAdult': allowAdult,
        'allowUnknown': false,
        'sortBy': 'Latest_Update',
      };

      if (genres != null && genres.isNotEmpty) {
        searchInput['genres'] = genres;
      }

      final variables = {
        'search': searchInput,
        'limit': limit,
        'page': page,
      };

      final response = await _dio.post(
        ApiConstants.apiPath,
        data: {
          'variables': variables,
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
}
