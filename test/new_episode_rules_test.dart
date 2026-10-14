import 'package:flutter_test/flutter_test.dart';
import 'package:AniVerse/services/new_episode_rules.dart';

void main() {
  final now = DateTime(2026, 10, 14);

  test('checks favorites, watchlist and recent history once each', () {
    final ids = NewEpisodeRules.animeToCheck(
      favorites: ['a', 'b'],
      watchlist: ['b', 'c', 'raiden_x'],
      history: [
        (animeId: 'a', lastWatched: now),
        (animeId: 'd', lastWatched: now.subtract(const Duration(days: 10))),
        (animeId: 'old', lastWatched: now.subtract(const Duration(days: 200))),
      ],
      now: now,
    );
    expect(ids, unorderedEquals(['a', 'b', 'c', 'd']));
  });

  test('first sighting records a baseline without notifying', () {
    final d = NewEpisodeRules.evaluate(knownCount: null, currentCount: 12);
    expect(d.notify, isFalse);
    expect(d.baseline, 12);
  });

  test('new episodes notify once, then the same count stays quiet', () {
    final first = NewEpisodeRules.evaluate(knownCount: 12, currentCount: 13);
    expect(first.notify, isTrue);
    expect(first.newEpisodes, 1);

    final repeat =
        NewEpisodeRules.evaluate(knownCount: first.baseline, currentCount: 13);
    expect(repeat.notify, isFalse);
  });

  test('a temporary drop does not re-announce the episode later', () {
    final drop = NewEpisodeRules.evaluate(knownCount: 13, currentCount: 11);
    expect(drop.notify, isFalse);
    expect(drop.baseline, 13);

    final recover =
        NewEpisodeRules.evaluate(knownCount: drop.baseline, currentCount: 13);
    expect(recover.notify, isFalse);
  });

  test('notification ids are stable per anime and episode', () {
    final id = NewEpisodeRules.notificationId('abc123', 13);
    expect(NewEpisodeRules.notificationId('abc123', 13), id);
    expect(NewEpisodeRules.notificationId('abc123', 14), isNot(id));
    expect(id, inInclusiveRange(0, 0x7fffffff));
  });

  test('messages describe one or several new episodes', () {
    expect(
      NewEpisodeRules.message(animeTitle: 'Frieren', episodeCount: 13, newEpisodes: 1),
      (title: 'New episode of Frieren!', body: 'Episode 13 is now available'),
    );
    expect(
      NewEpisodeRules.message(animeTitle: 'Frieren', episodeCount: 14, newEpisodes: 2).body,
      'Episodes 13-14 are now available',
    );
  });
}
