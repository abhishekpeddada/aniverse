import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// One media segment of an HLS playlist.
@visibleForTesting
class HlsSegment {
  HlsSegment(this.uri, {this.keyUri, this.iv, required this.sequence});

  final Uri uri;

  /// AES-128 key location, when the segment is encrypted.
  final Uri? keyUri;

  /// Explicit IV from `#EXT-X-KEY`; otherwise the sequence number is used.
  final Uint8List? iv;
  final int sequence;
}

/// A parsed media playlist: an optional fMP4 init segment plus segments.
@visibleForTesting
class HlsMediaPlaylist {
  HlsMediaPlaylist(this.initSegment, this.segments);

  final Uri? initSegment;
  final List<HlsSegment> segments;
}

/// Downloads an HLS stream into a single file by concatenating its segments.
///
/// MPEG-TS segments (and fMP4 segments after their init segment) can be
/// joined byte for byte into a playable file, so no remuxing is needed.
class HlsDownloader {
  HlsDownloader(this._dio);

  final Dio _dio;

  /// Segments fetched at the same time. Each segment is its own request, so
  /// fetching several at once hides per-request latency; they are still
  /// written to the file in order.
  static const _parallelSegments = 6;

  Future<void> download({
    required String playlistUrl,
    required String outputPath,
    required Map<String, String> headers,
    CancelToken? cancelToken,
    void Function(int done, int total, int bytes)? onProgress,
  }) async {
    var mediaUri = Uri.parse(playlistUrl);
    var playlist = await _getText(mediaUri, headers, cancelToken);

    if (playlist.contains('#EXT-X-STREAM-INF')) {
      mediaUri = bestVariant(playlist, mediaUri);
      playlist = await _getText(mediaUri, headers, cancelToken);
    }

    final media = parseMediaPlaylist(playlist, mediaUri);
    if (media.segments.isEmpty) {
      throw const FormatException('HLS playlist has no segments');
    }

    final partFile = File('$outputPath.part');
    final sink = partFile.openWrite();
    // Futures, so segments sharing a key fetch it once even when in parallel.
    final keys = <Uri, Future<Uint8List>>{};
    var bytes = 0;

    Future<Uint8List> fetch(HlsSegment segment) async {
      final data = await _getBytes(segment.uri, headers, cancelToken);
      if (segment.keyUri == null) return data;
      final key = await (keys[segment.keyUri!] ??=
          _getBytes(segment.keyUri!, headers, cancelToken));
      return decryptSegment(data, key, segment.iv ?? sequenceIv(segment.sequence));
    }

    // Capture each result or error, so a failure doesn't surface as an
    // unhandled error from the other requests still in flight.
    Future<({Uint8List? data, Object? error, StackTrace? stack})> settle(
            HlsSegment segment) =>
        fetch(segment).then(
          (data) => (data: data, error: null, stack: null),
          onError: (Object e, StackTrace s) => (data: null, error: e, stack: s),
        );

    try {
      if (media.initSegment != null) {
        final init = await _getBytes(media.initSegment!, headers, cancelToken);
        sink.add(init);
        bytes += init.length;
      }

      final segments = media.segments;
      final inFlight =
          <Future<({Uint8List? data, Object? error, StackTrace? stack})>>[];
      var next = 0;
      for (var i = 0; i < segments.length; i++) {
        while (next < segments.length && inFlight.length < _parallelSegments) {
          inFlight.add(settle(segments[next++]));
        }

        final result = await inFlight.removeAt(0);
        if (result.error != null) {
          Error.throwWithStackTrace(result.error!, result.stack!);
        }

        sink.add(result.data!);
        bytes += result.data!.length;
        onProgress?.call(i + 1, segments.length, bytes);
      }

      await sink.flush();
      await sink.close();
      await partFile.rename(outputPath);
    } catch (_) {
      await sink.close();
      if (await partFile.exists()) await partFile.delete();
      rethrow;
    }
  }

  /// Picks the highest-bandwidth variant of a master playlist.
  @visibleForTesting
  static Uri bestVariant(String master, Uri masterUri) {
    final lines = master.split('\n').map((l) => l.trim()).toList();
    Uri? best;
    var bestBandwidth = -1;
    for (var i = 0; i < lines.length - 1; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      final bandwidth = int.tryParse(
              RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i])?.group(1) ?? '') ??
          0;
      final uriLine = lines.skip(i + 1).firstWhere(
          (l) => l.isNotEmpty && !l.startsWith('#'),
          orElse: () => '');
      if (uriLine.isEmpty) continue;
      if (bandwidth > bestBandwidth) {
        bestBandwidth = bandwidth;
        best = masterUri.resolve(uriLine);
      }
    }
    if (best == null) {
      throw const FormatException('HLS master playlist has no variants');
    }
    return best;
  }

  @visibleForTesting
  static HlsMediaPlaylist parseMediaPlaylist(String playlist, Uri playlistUri) {
    if (playlist.contains('#EXT-X-BYTERANGE')) {
      throw const FormatException('Byte-range HLS playlists are not supported');
    }

    Uri? initSegment;
    Uri? keyUri;
    Uint8List? iv;
    var sequence = 0;
    final segments = <HlsSegment>[];

    for (final raw in playlist.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.tryParse(line.split(':').last) ?? 0;
      } else if (line.startsWith('#EXT-X-MAP:')) {
        final uri = _attribute(line, 'URI');
        if (uri != null) initSegment = playlistUri.resolve(uri);
      } else if (line.startsWith('#EXT-X-KEY:')) {
        final method = _attribute(line, 'METHOD');
        if (method == 'NONE') {
          keyUri = null;
          iv = null;
        } else if (method == 'AES-128') {
          final uri = _attribute(line, 'URI');
          keyUri = uri == null ? null : playlistUri.resolve(uri);
          final ivHex = _attribute(line, 'IV');
          iv = ivHex == null ? null : _hexToBytes(ivHex);
        } else {
          throw FormatException('Unsupported HLS encryption: $method');
        }
      } else if (!line.startsWith('#')) {
        segments.add(HlsSegment(playlistUri.resolve(line),
            keyUri: keyUri, iv: iv, sequence: sequence));
        sequence++;
      }
    }
    return HlsMediaPlaylist(initSegment, segments);
  }

  /// The default IV: the media sequence number as a 16-byte big-endian value.
  @visibleForTesting
  static Uint8List sequenceIv(int sequence) {
    final iv = Uint8List(16);
    var value = sequence;
    for (var i = 15; i >= 0 && value > 0; i--) {
      iv[i] = value & 0xff;
      value >>= 8;
    }
    return iv;
  }

  /// AES-128-CBC with PKCS7 padding, as HLS specifies.
  @visibleForTesting
  static Uint8List decryptSegment(Uint8List data, Uint8List key, Uint8List iv) {
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        false,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
          null,
        ),
      );
    return cipher.process(data);
  }

  static String? _attribute(String line, String name) {
    final match = RegExp('$name=("([^"]*)"|[^,]*)').firstMatch(line);
    if (match == null) return null;
    return match.group(2) ?? match.group(1);
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.toLowerCase().replaceFirst('0x', '').padLeft(32, '0');
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  Future<String> _getText(
      Uri uri, Map<String, String> headers, CancelToken? cancelToken) async {
    final response = await _withRetry(() => _dio.getUri<String>(
          uri,
          options: Options(responseType: ResponseType.plain, headers: headers),
          cancelToken: cancelToken,
        ));
    return response.data ?? '';
  }

  Future<Uint8List> _getBytes(
      Uri uri, Map<String, String> headers, CancelToken? cancelToken) async {
    final response = await _withRetry(() => _dio.getUri<List<int>>(
          uri,
          options: Options(responseType: ResponseType.bytes, headers: headers),
          cancelToken: cancelToken,
        ));
    return Uint8List.fromList(response.data ?? const []);
  }

  /// Retries transient failures; cancellation and 4xx responses fail fast.
  static Future<T> _withRetry<T>(Future<T> Function() request) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await request();
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        final permanent = CancelToken.isCancel(e) || (status >= 400 && status < 500);
        if (permanent || attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
  }
}
