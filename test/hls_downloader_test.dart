import 'dart:typed_data';

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
