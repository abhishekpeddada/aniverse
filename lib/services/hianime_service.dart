import 'dart:convert';
import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A failure while resolving a stream on hianime, with a message meant for
/// the player's error screen.
class HianimeException implements Exception {
  HianimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Episode stream lookup on hianime.at, ported from ani-cli's current
/// provider (`hianime_search`, `hianime_episodes`, `hianime_m3u8`).
///
/// hianime sits behind Cloudflare, which rejects clients without a browser
/// TLS fingerprint (ani-cli needs curl-impersonate). On Android the requests
/// go through Cronet, Chromium's network stack, for the same reason.
class HianimeService {
  static const baseUrl = 'https://hianime.at';
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// The embed page config is base64(json XOR this key).
  static const _embedKey = 'otaku-embed-v1';

  http.Client? _client;
  final Map<String, String> _showCache = {};
  final Map<String, Map<String, String>> _episodeCache = {};

  http.Client get _http => _client ??= _createClient();

  static http.Client _createClient() {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final engine = CronetEngine.build(
          cacheMode: CacheMode.memory,
          cacheMaxSize: 2 * 1024 * 1024,
          userAgent: userAgent,
        );
        return CronetClient.fromCronetEngine(engine, closeEngine: true);
      } catch (e) {
        debugPrint('⚠️ Cronet unavailable, using the default HTTP client: $e');
      }
    }
    return http.Client();
  }

  /// Finds the show matching [titles] and returns the HLS stream for
  /// [episodeNumber] in [translationType] ('sub' or 'dub').
  Future<List<Map<String, dynamic>>> getSources({
    required List<String> titles,
    required String episodeNumber,
    required String translationType,
  }) async {
    final slug = await _findShow(titles);
    final episodes = await _episodes(slug);

    final episodeId = _matchEpisode(episodes, episodeNumber);
    if (episodeId == null) {
      throw HianimeException(
          'Episode $episodeNumber not found on hianime ($slug has ${episodes.length} episodes)');
    }

    final stream = await _stream(episodeId, translationType);
    return [
      {
        'url': stream.url,
        'quality': 'Auto',
        'isM3U8': true,
        'sourceName': 'hianime',
        'priority': 0,
        'headers': {
          'Referer': stream.referer,
          'User-Agent': userAgent,
        },
        if (stream.subtitleUrl != null) 'subtitle': stream.subtitleUrl,
      },
    ];
  }

  Future<String> _findShow(List<String> titles) async {
    final cacheKey = titles.join('|');
    final cached = _showCache[cacheKey];
    if (cached != null) return cached;

    String? fallback;
    for (final title in titles) {
      final page = await _get(
          '$baseUrl/search?keyword=${Uri.encodeQueryComponent(title)}');
      final results = parseSearch(page);
      if (results.isEmpty) continue;

      fallback ??= results.first.slug;
      final best = _bestMatch(results, titles);
      if (best != null) {
        _showCache[cacheKey] = best;
        return best;
      }
    }

    if (fallback != null) {
      _showCache[cacheKey] = fallback;
      return fallback;
    }
    throw HianimeException('No hianime results for "${titles.first}"');
  }

  /// Parses search results as (slug, title, japanese title).
  @visibleForTesting
  static List<({String slug, String name, String? jname})> parseSearch(String page) {
    // The "top 10" sidebar repeats the result markup, so cut it off first.
    final sidebar = page.indexOf('id="main-sidebar"');
    final main = (sidebar == -1 ? page : page.substring(0, sidebar))
        .replaceAll('\n', ' ');

    final results = <({String slug, String name, String? jname})>[];
    for (final chunk in main.split('<div class="film-detail">').skip(1)) {
      final link = RegExp(
              r'<h3 class="film-name">\s*<a href="[^"]*/([^"/]*)"\s*title="([^"]*)"')
          .firstMatch(chunk);
      if (link == null) continue;

      final slug = link.group(1)!.split('?').first;
      final jname = RegExp(r'data-jname="([^"]*)"').firstMatch(chunk)?.group(1);
      results.add((
        slug: slug,
        name: _unescapeHtml(link.group(2)!),
        jname: jname == null ? null : _unescapeHtml(jname),
      ));
    }
    return results;
  }

  /// Picks the result whose English or Japanese title matches one of
  /// [titles]: an exact match first, then one title containing the other.
  String? _bestMatch(
    List<({String slug, String name, String? jname})> results,
    List<String> titles,
  ) {
    final wanted = titles.map(_normalize).where((t) => t.isNotEmpty).toList();
    String? partial;
    for (final result in results) {
      final names = [result.name, if (result.jname != null) result.jname!]
          .map(_normalize)
          .where((n) => n.isNotEmpty);
      for (final name in names) {
        if (wanted.contains(name)) return result.slug;
        if (partial == null &&
            wanted.any((t) => t.contains(name) || name.contains(t))) {
          partial = result.slug;
        }
      }
    }
    return partial;
  }

  /// Returns episode number -> episode id for the show [slug].
  Future<Map<String, String>> _episodes(String slug) async {
    final cached = _episodeCache[slug];
    if (cached != null) return cached;

    final showId = slug.split('-').last;
    final episodes = parseEpisodes(
        await _get('$baseUrl/api/theme/episode/list/$showId'), slug);

    if (episodes.isEmpty) {
      throw HianimeException('No episodes listed on hianime for $slug');
    }
    _episodeCache[slug] = episodes;
    return episodes;
  }

  /// Parses the episode list response as episode number -> episode id.
  @visibleForTesting
  static Map<String, String> parseEpisodes(String body, String slug) {
    final episodes = <String, String>{};
    for (final chunk in htmlPayload(body).split('ep-item').skip(1)) {
      // Ids from other providers share the same shape, so also check the
      // episode link points at this show.
      if (!chunk.contains('/watch/$slug?ep=')) continue;
      final number = RegExp(r'data-number="([^"]*)"').firstMatch(chunk)?.group(1);
      final id = RegExp(r'data-id="([0-9]+)"').firstMatch(chunk)?.group(1);
      if (number != null && id != null) episodes[number] = id;
    }
    return episodes;
  }

  String? _matchEpisode(Map<String, String> episodes, String number) {
    final exact = episodes[number.trim()];
    if (exact != null) return exact;

    final wanted = double.tryParse(number.trim());
    if (wanted == null) return null;
    for (final entry in episodes.entries) {
      if (double.tryParse(entry.key) == wanted) return entry.value;
    }
    return null;
  }

  Future<({String url, String referer, String? subtitleUrl})> _stream(
    String episodeId,
    String translationType,
  ) async {
    final servers = parseServers(await _get(
        '$baseUrl/api/theme/episode/servers?episodeId=$episodeId'));

    // Only the ZokoAnime embed uses the player ani-cli knows how to decode.
    final server = servers
        .where((s) => s.type == translationType && s.name == 'ZokoAnime')
        .firstOrNull;
    if (server == null) {
      final available = servers.where((s) => s.type == translationType);
      throw HianimeException(available.isEmpty
          ? 'No $translationType servers for this episode'
          : 'No ZokoAnime $translationType server (found: '
              '${available.map((s) => s.name).join(', ')})');
    }

    final embedUrl = utf8.decode(base64.decode(base64.normalize(server.hash)));
    final origin = RegExp(r'^(https?://[^/]*)').firstMatch(embedUrl)?.group(1);
    if (origin == null) {
      throw HianimeException('Unexpected embed URL from server hash');
    }

    final embedPage = await _get(embedUrl);
    final blob =
        RegExp(r'window\.__P="([^"]*)"').firstMatch(embedPage)?.group(1);
    if (blob == null) {
      throw HianimeException('Embed page has no player config (window.__P)');
    }

    final config = deobfuscate(blob).replaceAll(r'\/', '/');
    final masters =
        RegExp(r'"src":"([^"]*\.m3u8[^"]*)"').allMatches(config).toList();
    if (masters.isEmpty) {
      throw HianimeException('Player config has no m3u8 stream');
    }

    return (
      url: masters.last.group(1)!,
      // The stream host wants the embed site as referer.
      referer: '$origin/',
      subtitleUrl: defaultSubtitle(config),
    );
  }

  /// Parses the servers response into (type, server name, hash) entries.
  @visibleForTesting
  static List<({String type, String name, String hash})> parseServers(String body) {
    final servers = <({String type, String name, String hash})>[];
    for (final chunk in htmlPayload(body).split('server-item').skip(1)) {
      final type = RegExp(r'data-type="([^"]*)"').firstMatch(chunk)?.group(1);
      final name = RegExp(r'data-server-name="([^"]*)"').firstMatch(chunk)?.group(1);
      final hash = RegExp(r'data-hash="([^"]*)"').firstMatch(chunk)?.group(1);
      if (type != null && name != null && hash != null) {
        servers.add((type: type, name: name, hash: hash));
      }
    }
    return servers;
  }

  /// Decodes the embed config: base64, then XOR with the rotating key.
  @visibleForTesting
  static String deobfuscate(String blob) {
    final bytes = base64.decode(base64.normalize(blob));
    final key = ascii.encode(_embedKey);
    final out = List<int>.generate(
        bytes.length, (i) => bytes[i] ^ key[i % key.length]);
    return utf8.decode(out, allowMalformed: true);
  }

  /// Picks the subtitle track: the one marked default (as ani-cli does),
  /// else an English one, else the first.
  @visibleForTesting
  static String? defaultSubtitle(String config) {
    final start = config.indexOf('"subtitles":[');
    if (start == -1) return null;
    final rest = config.substring(start + '"subtitles":['.length);
    final end = rest.indexOf('}]');
    final entries = (end == -1 ? rest : rest.substring(0, end)).split('},{');

    String? srcOf(String entry) =>
        RegExp(r'"(?:src|file)":"([^"]*)"').firstMatch(entry)?.group(1);

    for (final entry in entries) {
      if (entry.contains('"default":true')) return srcOf(entry);
    }
    for (final entry in entries) {
      if (RegExp(r'english|"(?:lang|srclang|language)":"en', caseSensitive: false)
          .hasMatch(entry)) {
        final src = srcOf(entry);
        if (src != null) return src;
      }
    }
    return entries.map(srcOf).whereType<String>().firstOrNull;
  }

  /// The episode and server endpoints return `{"html": "..."}`.
  @visibleForTesting
  static String htmlPayload(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['html'] is String) {
        return decoded['html'] as String;
      }
    } on FormatException {
      // Not JSON: fall through and treat it as escaped HTML.
    }
    return body.replaceAll(r'\"', '"').replaceAll(r'\/', '/');
  }

  Future<String> _get(String url, {String? referer}) async {
    final uri = Uri.parse(url);
    final response = await _http.get(uri, headers: {
      'User-Agent': userAgent,
      if (referer != null) 'Referer': referer,
    }).timeout(const Duration(seconds: 15));

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (body.contains('<title>Just a moment')) {
      throw HianimeException('Blocked by Cloudflare at ${uri.host}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HianimeException('HTTP ${response.statusCode} from ${uri.host}');
    }
    return body;
  }

  static String _normalize(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _unescapeHtml(String text) => text
      .replaceAll('&#039;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&');
}
