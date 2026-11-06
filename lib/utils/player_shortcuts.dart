import 'package:flutter/services.dart';

/// What a key does in the desktop player. Keyboard input only runs on Windows
/// and Linux; Android keeps its touch gestures.
enum PlayerShortcut {
  playPause,
  seekBack,
  seekForward,
  seekBackLong,
  seekForwardLong,
  volumeUp,
  volumeDown,
  mute,
  fullscreen,
  back,
  speedDown,
  speedUp,
  nextEpisode,
  skipSegment;

  /// Whether holding the key keeps applying it. Toggles must not, or holding
  /// Space would flicker between playing and paused.
  bool get repeats => switch (this) {
        seekBack ||
        seekForward ||
        seekBackLong ||
        seekForwardLong ||
        volumeUp ||
        volumeDown =>
          true,
        _ => false,
      };
}

class PlayerShortcuts {
  const PlayerShortcuts._();

  static const seekStep = Duration(seconds: 10);
  static const longSeekStep = Duration(seconds: 60);

  /// Volume change per key press, out of 1.0.
  static const volumeStep = 0.05;

  /// The action for [key], or null if the player doesn't use it.
  static PlayerShortcut? actionFor(LogicalKeyboardKey key,
      {bool shift = false}) {
    if (key == LogicalKeyboardKey.arrowLeft) {
      return shift ? PlayerShortcut.seekBackLong : PlayerShortcut.seekBack;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return shift ? PlayerShortcut.seekForwardLong : PlayerShortcut.seekForward;
    }
    // Shift+comma and Shift+period report as either the punctuation or the
    // shifted symbol, depending on the platform.
    if (shift && key == LogicalKeyboardKey.comma) return PlayerShortcut.speedDown;
    if (shift && key == LogicalKeyboardKey.period) return PlayerShortcut.speedUp;
    return _plainKeys[key];
  }

  /// The fraction of the episode a number key jumps to (5 is 50%), or null if
  /// [key] isn't a number key.
  static double? jumpFractionFor(LogicalKeyboardKey key) {
    final digit = _digits[key];
    return digit == null ? null : digit / 10;
  }

  /// The next speed from [speeds] (ascending) in a direction, staying at the
  /// end of the list once it's reached.
  static double stepSpeed(List<double> speeds, double current, {required bool up}) {
    final faster = speeds.where((speed) => speed > current);
    final slower = speeds.where((speed) => speed < current);
    if (up) return faster.isEmpty ? current : faster.first;
    return slower.isEmpty ? current : slower.last;
  }

  static final _plainKeys = <LogicalKeyboardKey, PlayerShortcut>{
    LogicalKeyboardKey.space: PlayerShortcut.playPause,
    LogicalKeyboardKey.keyK: PlayerShortcut.playPause,
    LogicalKeyboardKey.mediaPlayPause: PlayerShortcut.playPause,
    LogicalKeyboardKey.keyJ: PlayerShortcut.seekBack,
    LogicalKeyboardKey.keyL: PlayerShortcut.seekForward,
    LogicalKeyboardKey.arrowUp: PlayerShortcut.volumeUp,
    LogicalKeyboardKey.arrowDown: PlayerShortcut.volumeDown,
    LogicalKeyboardKey.keyM: PlayerShortcut.mute,
    LogicalKeyboardKey.keyF: PlayerShortcut.fullscreen,
    LogicalKeyboardKey.f11: PlayerShortcut.fullscreen,
    LogicalKeyboardKey.escape: PlayerShortcut.back,
    LogicalKeyboardKey.bracketLeft: PlayerShortcut.speedDown,
    LogicalKeyboardKey.bracketRight: PlayerShortcut.speedUp,
    LogicalKeyboardKey.less: PlayerShortcut.speedDown,
    LogicalKeyboardKey.greater: PlayerShortcut.speedUp,
    LogicalKeyboardKey.keyN: PlayerShortcut.nextEpisode,
    LogicalKeyboardKey.keyS: PlayerShortcut.skipSegment,
  };

  static final _digits = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.numpad9: 9,
  };
}
