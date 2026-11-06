import 'package:AniVerse/utils/player_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('actionFor', () {
    test('arrows seek, and Shift makes the jump longer', () {
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.arrowLeft),
          PlayerShortcut.seekBack);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.arrowRight),
          PlayerShortcut.seekForward);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.arrowLeft, shift: true),
          PlayerShortcut.seekBackLong);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.arrowRight, shift: true),
          PlayerShortcut.seekForwardLong);
    });

    test('Up and Down change the volume', () {
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.arrowUp),
          PlayerShortcut.volumeUp);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.arrowDown),
          PlayerShortcut.volumeDown);
    });

    test('Space and K both toggle playback', () {
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.space),
          PlayerShortcut.playPause);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.keyK),
          PlayerShortcut.playPause);
    });

    test('speed keys work however the platform reports Shift+comma', () {
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.comma, shift: true),
          PlayerShortcut.speedDown);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.less),
          PlayerShortcut.speedDown);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.period, shift: true),
          PlayerShortcut.speedUp);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.greater),
          PlayerShortcut.speedUp);
    });

    test('unshifted punctuation and other keys are left alone', () {
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.comma), isNull);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.period), isNull);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.tab), isNull);
      expect(PlayerShortcuts.actionFor(LogicalKeyboardKey.keyQ), isNull);
    });
  });

  test('only seeking and volume repeat while a key is held', () {
    final repeating =
        PlayerShortcut.values.where((action) => action.repeats).toSet();
    expect(repeating, {
      PlayerShortcut.seekBack,
      PlayerShortcut.seekForward,
      PlayerShortcut.seekBackLong,
      PlayerShortcut.seekForwardLong,
      PlayerShortcut.volumeUp,
      PlayerShortcut.volumeDown,
    });
  });

  test('number keys jump to a tenth of the episode', () {
    expect(PlayerShortcuts.jumpFractionFor(LogicalKeyboardKey.digit0), 0);
    expect(PlayerShortcuts.jumpFractionFor(LogicalKeyboardKey.digit5), 0.5);
    expect(PlayerShortcuts.jumpFractionFor(LogicalKeyboardKey.numpad9), 0.9);
    expect(PlayerShortcuts.jumpFractionFor(LogicalKeyboardKey.keyA), isNull);
  });

  group('stepSpeed', () {
    const speeds = [0.5, 1.0, 1.5, 2.0];

    test('moves one step each way', () {
      expect(PlayerShortcuts.stepSpeed(speeds, 1.0, up: true), 1.5);
      expect(PlayerShortcuts.stepSpeed(speeds, 1.0, up: false), 0.5);
    });

    test('stays put at either end', () {
      expect(PlayerShortcuts.stepSpeed(speeds, 2.0, up: true), 2.0);
      expect(PlayerShortcuts.stepSpeed(speeds, 0.5, up: false), 0.5);
    });
  });
}
