import 'package:flutter_test/flutter_test.dart';
import 'package:AniVerse/models/episode_model.dart';
import 'package:AniVerse/models/watch_history_model.dart';
import 'package:AniVerse/utils/playback_rules.dart';

void main() {
  final episodes = [
    for (final n in [1, 2, 3, 5]) Episode(id: 'show-$n', number: n),
  ];

  WatchHistory entry(int ep, {required int pos, int dur = 1000, int minute = 0}) =>
      WatchHistory(
        animeId: 'show',
        animeTitle: 'Show',
        episodeNumber: ep,
        episodeId: 'show-$ep',
        positionMs: pos,
        durationMs: dur,
        lastWatched: DateTime(2026, 10, 20, 10, minute),
      );

  test('nextEpisode skips gaps and returns null at the end', () {
    expect(PlaybackRules.nextEpisode(episodes, 3)?.id, 'show-5');
    expect(PlaybackRules.nextEpisode(episodes, 5), isNull);
  });

  test('continue episode is the latest unfinished one', () {
    final id = PlaybackRules.continueEpisodeId(
      history: [entry(1, pos: 1000, minute: 1), entry(2, pos: 300, minute: 2)],
      animeId: 'show',
      episodes: episodes,
    );
    expect(id, 'show-2');
  });

  test('continue moves to the next episode once the latest is finished', () {
    final id = PlaybackRules.continueEpisodeId(
      history: [entry(2, pos: 950, minute: 5)],
      animeId: 'show',
      episodes: episodes,
    );
    expect(id, 'show-3');
  });

  test('continue falls back when there is no history for the anime', () {
    expect(
      PlaybackRules.continueEpisodeId(
          history: const [], animeId: 'show', episodes: episodes, fallback: 'x'),
      'x',
    );
  });

  test('parseSkipTimes reads op and ed and ignores others', () {
    final segments = PlaybackRules.parseSkipTimes({
      'found': true,
      'results': [
        {'interval': {'start_time': 30.5, 'end_time': 120.0}, 'skip_type': 'op'},
        {'interval': {'start_time': 1300, 'end_time': 1390}, 'skip_type': 'ed'},
        {'interval': {'start_time': 1, 'end_time': 5}, 'skip_type': 'recap'},
      ],
    });
    expect(segments.map((s) => s.type), ['op', 'ed']);
    expect(segments.first.start, const Duration(milliseconds: 30500));
    expect(PlaybackRules.parseSkipTimes({'found': false}), isEmpty);
  });

  test('activeSkip covers the segment except its last second', () {
    const op = SkipSegment(
        type: 'op', start: Duration(seconds: 30), end: Duration(seconds: 120));
    expect(PlaybackRules.activeSkip([op], const Duration(seconds: 29)), isNull);
    expect(PlaybackRules.activeSkip([op], const Duration(seconds: 60)), op);
    expect(PlaybackRules.activeSkip([op], const Duration(milliseconds: 119500)), isNull);
  });
}
