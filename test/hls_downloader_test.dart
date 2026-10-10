import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:AniVerse/services/hls_downloader.dart';

void main() {
  final base = Uri.parse('https://cdn.example/hls/master.m3u8');

  test('bestVariant picks the highest bandwidth and resolves it', () {
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
1080/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720
https://other.example/720.m3u8
''';
    expect(HlsDownloader.bestVariant(master, base).toString(),
        'https://cdn.example/hls/1080/index.m3u8');
  });

  test('parseMediaPlaylist tracks keys, IVs, sequence and init segment', () {
    const playlist = '''
#EXTM3U
#EXT-X-MEDIA-SEQUENCE:7
#EXT-X-MAP:URI="init.mp4"
#EXTINF:4.0,
seg0.m4s
#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x000102030405060708090a0b0c0d0e0f
#EXTINF:4.0,
seg1.m4s
#EXT-X-KEY:METHOD=NONE
#EXTINF:4.0,
seg2.m4s
#EXT-X-ENDLIST
''';
    final media = HlsDownloader.parseMediaPlaylist(playlist, base);

    expect(media.initSegment.toString(), 'https://cdn.example/hls/init.mp4');
    expect(media.segments.map((s) => s.sequence), [7, 8, 9]);
    expect(media.segments[0].keyUri, isNull);
    expect(media.segments[1].keyUri.toString(), 'https://cdn.example/hls/key.bin');
    expect(media.segments[1].iv, Uint8List.fromList(List.generate(16, (i) => i)));
    expect(media.segments[2].keyUri, isNull);
  });

  test('unsupported encryption and byte ranges are rejected', () {
    expect(
        () => HlsDownloader.parseMediaPlaylist(
            '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="k"\nseg.ts', base),
        throwsFormatException);
    expect(
        () => HlsDownloader.parseMediaPlaylist(
            '#EXT-X-BYTERANGE:100@0\nseg.ts', base),
        throwsFormatException);
  });

  test('sequenceIv is the big-endian sequence number', () {
    final iv = HlsDownloader.sequenceIv(0x0102);
    expect(iv.length, 16);
    expect(iv.sublist(14), [0x01, 0x02]);
    expect(iv.sublist(0, 14).every((b) => b == 0), isTrue);
  });

  test('download writes parallel-fetched segments in playlist order', () async {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter({
        'https://cdn.example/hls/master.m3u8': '#EXTM3U\n'
            '${List.generate(20, (i) => '#EXTINF:1,\nseg$i.ts').join('\n')}',
        for (var i = 0; i < 20; i++) 'https://cdn.example/hls/seg$i.ts': 'S$i;',
      });
    final dir = await Directory.systemTemp.createTemp('hls_test');
    final out = '${dir.path}/out.ts';
    final progress = <int>[];

    await HlsDownloader(dio).download(
      playlistUrl: 'https://cdn.example/hls/master.m3u8',
      outputPath: out,
      headers: const {},
      onProgress: (done, total, bytes) => progress.add(done),
    );

    expect(await File(out).readAsString(),
        List.generate(20, (i) => 'S$i;').join());
    expect(progress, List.generate(20, (i) => i + 1));
    await dir.delete(recursive: true);
  });

  test('download fails cleanly and leaves no partial file', () async {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter({
        'https://cdn.example/hls/master.m3u8':
            '#EXTM3U\n#EXTINF:1,\nseg0.ts\n#EXTINF:1,\nmissing.ts\n#EXTINF:1,\nseg2.ts',
        'https://cdn.example/hls/seg0.ts': 'a',
        'https://cdn.example/hls/seg2.ts': 'c',
      });
    final dir = await Directory.systemTemp.createTemp('hls_test');
    final out = '${dir.path}/out.ts';

    await expectLater(
      HlsDownloader(dio).download(
        playlistUrl: 'https://cdn.example/hls/master.m3u8',
        outputPath: out,
        headers: const {},
      ),
      throwsA(isA<DioException>()),
    );
    expect(File(out).existsSync(), isFalse);
    expect(File('$out.part').existsSync(), isFalse);
    await dir.delete(recursive: true);
  });

  test('decryptSegment reverses AES-128-CBC with PKCS7', () {
    final key = Uint8List.fromList(List.generate(16, (i) => i * 3));
    final iv = HlsDownloader.sequenceIv(42);
    final plain = Uint8List.fromList(List.generate(1000, (i) => i % 251));

    final encrypter = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        true,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
          null,
        ),
      );
    final encrypted = encrypter.process(plain);

    expect(HlsDownloader.decryptSegment(encrypted, key, iv), plain);
  });
}

/// Serves fixed bodies by URL after a random delay, so parallel requests
/// finish out of order. Unknown URLs return 404.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.bodies);

  final Map<String, String> bodies;
  final _random = Random(1);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    await Future<void>.delayed(Duration(milliseconds: _random.nextInt(20)));
    final body = bodies[options.uri.toString()];
    if (body == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromBytes(utf8.encode(body), 200);
  }

  @override
  void close({bool force = false}) {}
}
