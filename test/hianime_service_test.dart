import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:AniVerse/services/hianime_service.dart';

void main() {
  test('parseSearch reads results and ignores the sidebar', () {
    const page = '''
<div class="film_list-wrap">
<div class="flw-item"><div class="film-detail">
  <h3 class="film-name">
    <a href="/vigilante-my-hero-academia-illegals-19544" title="Vigilante: My Hero Academia Illegals" class="dynamic-name" data-jname="Vigilante: Boku no Hero Academia Illegals">Vigilante</a>
  </h3>
</div></div>
<div class="flw-item"><div class="film-detail"><h3 class="film-name"><a href="/my-hero-academia-100" title="My Hero Academia &amp; Friends" data-jname="Boku no Hero Academia">x</a></h3></div></div>
</div>
<div id="main-sidebar"><div class="film-detail"><h3 class="film-name"><a href="/sidebar-show-1" title="Sidebar">s</a></h3></div></div>
''';

    final results = HianimeService.parseSearch(page);

    expect(results.map((r) => r.slug),
        ['vigilante-my-hero-academia-illegals-19544', 'my-hero-academia-100']);
    expect(results.first.jname, 'Vigilante: Boku no Hero Academia Illegals');
    expect(results.last.name, 'My Hero Academia & Friends');
  });

  test('parseEpisodes maps numbers to ids for this show only', () {
    final body = jsonEncode({
      'status': true,
      'html': '<a class="ssl-item ep-item" data-number="1" data-id="111" href="/watch/vig-19544?ep=111">1</a>'
          '<a class="ssl-item ep-item" data-number="2" data-id="222" href="/watch/vig-19544?ep=222">2</a>'
          '<a class="ssl-item ep-item" data-number="1" data-id="999" href="/watch/other-show-5?ep=999">x</a>',
    });

    expect(HianimeService.parseEpisodes(body, 'vig-19544'), {'1': '111', '2': '222'});
  });

  test('parseServers reads type, server name and hash', () {
    final body = jsonEncode({
      'html': '<div class="server-item" data-type="sub" data-id="1" data-server-name="ZokoAnime" data-hash="aGFzaDE=">Z</div>'
          '<div class="server-item" data-type="dub" data-id="2" data-server-name="Other" data-hash="aGFzaDI=">O</div>',
    });

    final servers = HianimeService.parseServers(body);
    expect(servers.length, 2);
    expect(servers.first, (type: 'sub', name: 'ZokoAnime', hash: 'aGFzaDE='));
  });

  test('deobfuscate reverses base64(json XOR key) and finds the subtitle', () {
    const config = '{"sources":[{"src":"https://cdn.example/master.m3u8"}],'
        '"subtitles":[{"src":"https://cdn.example/es.vtt","default":false},'
        '{"src":"https://cdn.example/en.vtt","default":true}]}';
    final key = ascii.encode('otaku-embed-v1');
    final bytes = utf8.encode(config);
    final blob = base64.encode(
        List<int>.generate(bytes.length, (i) => bytes[i] ^ key[i % key.length]));

    final decoded = HianimeService.deobfuscate(blob);
    expect(decoded, config);
    expect(HianimeService.defaultSubtitle(decoded), 'https://cdn.example/en.vtt');
  });
}
