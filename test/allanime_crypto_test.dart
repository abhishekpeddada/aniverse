import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:AniVerse/services/allanime_crypto.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i * 7 + 3));
  const epoch = '1234';

  test('aaReq has version byte, 12-byte IV and GCM tag', () async {
    final crypto = AllAnimeCrypto(Dio())..setKeysForTest(key, epoch);
    final bytes = base64Decode(await crypto.buildAaReq('abc'));

    expect(bytes.first, 1);
    // 1 version + 12 iv + ciphertext (payload length) + 16 tag
    final payloadLength = utf8.encode('{"v":1,"ts":0000000000000,"epoch":1234,"qh":"abc"}').length;
    expect(bytes.length, 1 + 12 + payloadLength + 16);
  });

  test('tobeparsed payload round-trips through the decryptor', () async {
    final crypto = AllAnimeCrypto(Dio())..setKeysForTest(key, epoch);

    // Encrypt a plaintext the way the server does: 0x01 | iv | ct | tag.
    final iv = List<int>.generate(12, (i) => 200 - i);
    const plain = '{"data":{"episode":{"sourceUrls":[]}}}';
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plain),
      secretKey: SecretKey(key),
      nonce: iv,
    );
    final payload = base64Encode([1, ...iv, ...box.cipherText, ...box.mac.bytes]);

    expect(await crypto.decryptTobeParsed(payload), plain);
  });

  test('tampered tobeparsed payload is rejected', () async {
    final crypto = AllAnimeCrypto(Dio())..setKeysForTest(key, epoch);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode('hello'),
      secretKey: SecretKey(key),
      nonce: List<int>.filled(12, 9),
    );
    final bytes = [1, ...List<int>.filled(12, 9), ...box.cipherText, ...box.mac.bytes];
    bytes[bytes.length - 1] ^= 0xff;

    expect(() => crypto.decryptTobeParsed(base64Encode(bytes)), throwsA(anything));
  });
}
