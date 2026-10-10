import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/api_constants.dart';

/// AllAnime's AES-256-GCM request/response scheme, ported from ani-cli 4.15
/// (`fetch_keys`, `get_aa_req`, `process_tobeparsed`).
///
/// The key is not hard-coded: it is rebuilt from the site's page (epoch and
/// `partB`) and a 64-hex-char mask found in its JavaScript chunks.
class AllAnimeCrypto {
  AllAnimeCrypto(this._dio);

  final Dio _dio;

  static const _keyTtl = Duration(hours: 1);
  static const _userAgent = ApiConstants.userAgent;

  static final _aesGcm = AesGcm.with256bits();

  Uint8List? _key;
  String? _epoch;
  DateTime? _keyFetchedAt;

  bool get _hasFreshKey =>
      _key != null &&
      _keyFetchedAt != null &&
      DateTime.now().difference(_keyFetchedAt!) < _keyTtl;

  /// Injects a key and epoch so the framing can be tested without the network.
  @visibleForTesting
  void setKeysForTest(Uint8List key, String epoch) {
    _key = key;
    _epoch = epoch;
    _keyFetchedAt = DateTime.now();
  }

  /// Fetches the epoch, `partB` and mask from the site, and derives the key.
  Future<void> ensureKeys() async {
    if (_hasFreshKey) return;

    final page = await _getText(ApiConstants.referer);

    final epoch = RegExp(r'"epoch":(\d+)').firstMatch(page)?.group(1);
    final partB = RegExp(r'"partB":"([^"]*)"').firstMatch(page)?.group(1);
    final appUrl = RegExp(
      '${RegExp.escape(ApiConstants.cdn)}/entry/app\\.[A-Za-z0-9_.-]+\\.js',
    ).firstMatch(page)?.group(0);

    if (epoch == null || partB == null || appUrl == null) {
      throw StateError('AllAnime key page is missing epoch, partB or app bundle');
    }

    final appJs = await _getText(appUrl);
    final chunkPaths = RegExp(r'"\.\./chunks/[A-Za-z0-9_.-]+\.js"')
        .allMatches(appJs)
        .map((m) => m.group(0)!.replaceAll('"', '').replaceFirst('../', ''))
        .take(5);

    String? mask;
    for (final path in chunkPaths) {
      final js = await _getText('${ApiConstants.cdn}/$path');
      mask = RegExp(r'[0-9a-f]{64}').firstMatch(js)?.group(0);
      if (mask != null) break;
    }
    if (mask == null) {
      throw StateError('AllAnime key mask not found in JavaScript chunks');
    }

    final maskBytes = _hexToBytes(mask);
    final partBBytes = base64Decode(partB);
    if (partBBytes.length < maskBytes.length) {
      throw StateError('AllAnime partB is shorter than the key mask');
    }

    final key = Uint8List(maskBytes.length);
    for (var i = 0; i < maskBytes.length; i++) {
      key[i] = maskBytes[i] ^ partBBytes[i];
    }

    _key = key;
    _epoch = epoch;
    _keyFetchedAt = DateTime.now();
    debugPrint('🔑 AllAnime key derived (epoch $epoch)');
  }

  /// Builds the `aaReq` value sent in the persisted-query `extensions`.
  Future<String> buildAaReq(String queryHash) async {
    await ensureKeys();
    final epoch = _epoch!;

    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 300000) * 300000;
    final payload = '{"v":1,"ts":$ts,"epoch":$epoch,"qh":"$queryHash"}';

    // The IV is the first 12 bytes of SHA-256("epoch:qh:ts").
    final iv = sha256.convert(utf8.encode('$epoch:$queryHash:$ts')).bytes.sublist(0, 12);

    final box = await _aesGcm.encrypt(
      utf8.encode(payload),
      secretKey: SecretKey(_key!),
      nonce: iv,
    );

    // Output layout: 0x01 | iv | ciphertext | tag.
    final out = BytesBuilder()
      ..addByte(1)
      ..add(iv)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return base64Encode(out.toBytes());
  }

  /// Decrypts a `tobeparsed` payload: 0x01 | iv(12) | ciphertext | tag(16).
  Future<String> decryptTobeParsed(String tobeParsed) async {
    await ensureKeys();
    final bytes = base64Decode(tobeParsed);
    if (bytes.length < 13 + 16) {
      throw FormatException('tobeparsed payload too short');
    }

    final nonce = bytes.sublist(1, 13);
    final cipherText = bytes.sublist(13, bytes.length - 16);
    final tag = bytes.sublist(bytes.length - 16);

    final clear = await _aesGcm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
      secretKey: SecretKey(_key!),
    );
    return utf8.decode(clear);
  }

  Future<String> _getText(String url) async {
    final response = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': _userAgent,
          'Referer': ApiConstants.referer,
        },
      ),
    );
    return response.data ?? '';
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
