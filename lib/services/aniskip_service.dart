import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/playback_rules.dart';

/// Intro/outro skip times from AniSkip (the service ani-cli's ani-skip uses),
/// plus the sidecar file that keeps them with a downloaded episode.
class AniSkipService {
  /// Fetches skip times for [episodeNumber] of the show with MyAnimeList id
  /// [malId]. Returns null when the lookup fails (so it can be retried),
  /// and an empty list when AniSkip has no times for the episode.
  static Future<List<SkipSegment>?> fetch(String malId, int episodeNumber) async {
    try {
      final uri = Uri.parse('https://api.aniskip.com/v1/skip-times/'
          '$malId/$episodeNumber?types=op&types=ed');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) return const [];
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;
      return PlaybackRules.parseSkipTimes(json);
    } catch (e) {
      debugPrint('Skip times unavailable: $e');
      return null;
    }
  }

  /// Where a downloaded video's skip data is stored.
  static String sidecarPathFor(String videoPath) =>
      '${videoPath.replaceFirst(RegExp(r'\.[^./]+$'), '')}.skip.json';

  /// Saves the MAL id and, when known, the skip segments next to a video.
  static Future<void> writeSidecar(
    String videoPath, {
    required String malId,
    List<SkipSegment>? segments,
  }) async {
    try {
      await File(sidecarPathFor(videoPath)).writeAsString(jsonEncode({
        'malId': malId,
        if (segments != null)
          'segments': segments.map(PlaybackRules.segmentToJson).toList(),
      }));
    } catch (e) {
      debugPrint('Could not save skip times: $e');
    }
  }

  /// Reads a video's sidecar: its MAL id and the saved segments (null when
  /// they weren't fetched yet).
  static Future<({String? malId, List<SkipSegment>? segments})> readSidecar(
      String videoPath) async {
    try {
      final file = File(sidecarPathFor(videoPath));
      if (!await file.exists()) return (malId: null, segments: null);
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return (malId: null, segments: null);
      final saved = json['segments'];
      return (
        malId: json['malId'] as String?,
        segments: saved is List
            ? saved
                .whereType<Map>()
                .map(PlaybackRules.segmentFromJson)
                .whereType<SkipSegment>()
                .toList()
            : null,
      );
    } catch (e) {
      debugPrint('Could not read skip times: $e');
      return (malId: null, segments: null);
    }
  }

  /// Fetches skip times for a downloaded video and saves them with it.
  static Future<void> saveForDownload(
      String videoPath, String malId, int episodeNumber) async {
    final segments = await fetch(malId, episodeNumber);
    await writeSidecar(videoPath, malId: malId, segments: segments);
  }
}
