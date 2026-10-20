import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import '../../providers/anime_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/storage_provider.dart';
import '../../providers/raiden_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/download_service.dart';
import '../../services/firestore_service.dart';
import '../../models/episode_model.dart';
import '../../models/watch_history_model.dart';
import '../../providers/download_provider.dart';
import '../../utils/playback_rules.dart';
import 'widgets/quality_selector.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String episodeId;
  final String animeId;
  final String animeTitle;
  final String? animeImage;
  final int episodeNumber;
  final bool isOffline;
  final String? offlineFilePath;

  const VideoPlayerScreen({
    super.key,
    required this.episodeId,
    required this.animeId,
    required this.animeTitle,
    this.animeImage,
    required this.episodeNumber,
    this.isOffline = false,
    this.offlineFilePath,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with WidgetsBindingObserver {
  late final Player player;
  late final VideoController controller;
  bool isInitialized = false;
  bool hasError = false;
  String? errorMessage;
  BoxFit _fit = BoxFit.contain; // Default fit mode

  // Source & Quality State
  List<Map<String, dynamic>> _availableSources = [];
  int _currentSourceIndex = 0;

  /// Each attempt to open a source gets a number, so the burst of errors
  /// mpv can log for one failure only counts as one failure.
  int _sourceAttempt = 0;
  int? _failedSourceAttempt;

  /// One extra pass over the sources before reporting that all failed:
  /// a stream that errors on first open often plays on the next try.
  bool _retriedSources = false;
  String _translationType = 'sub'; // 'sub' or 'dub'

  // Gesture State
  double _volume = 0.5;
  double _brightness = 0.5;
  bool _showFeedback = false;
  IconData? _feedbackIcon;
  String? _feedbackText;
  Timer? _feedbackTimer;

  // Seek gesture state
  double? _seekStartPosition;
  Duration? _seekTargetPosition;
  bool _isSeeking = false;

  // Drag State
  bool _isDragging = false;
  double _dragStartVolume = 0.5;
  double _dragStartBrightness = 0.5;
  Duration _dragStartPosition = Duration.zero;
  Duration _targetSeekPosition = Duration.zero;
  DateTime? _lastSeekTime;

  bool _autoRotateEnabled = true;
  StreamSubscription<NativeDeviceOrientation>?
      _orientationSubscription; // To prevent error triggering during seek

  // Controls visibility
  bool _showControls = true;

  /// While locked, controls and gestures are disabled so the screen can be
  /// touched without seeking or pausing; a tap only reveals the unlock button.
  bool _controlsLocked = false;
  bool _showUnlockButton = false;

  /// The episode to autoplay when this one ends, and the countdown shown
  /// before it starts (null when no countdown is running).
  Episode? _nextEpisode;
  int? _nextCountdown;
  Timer? _nextTimer;
  bool _autoNextHandled = false;

  /// Intro/outro segments from AniSkip, and the one under the playhead.
  List<SkipSegment> _skipSegments = const [];
  SkipSegment? _activeSkip;
  bool _skipTimesRequested = false;
  Timer? _unlockButtonTimer;
  Timer? _hideControlsTimer;

  // Playback speed
  double _playbackSpeed = 1.0;

  // Picture-in-Picture state
  bool _isInPipMode = false;

  Timer? _historySaveTimer;

  // Buffering state
  bool _isBuffering = false;

  Future<void> _saveVlcWatchHistory({int positionMs = 0, int durationMs = 0}) async {
    final effectiveDuration = durationMs > 0 ? durationMs : 24 * 60 * 1000;
    
    final history = WatchHistory(
      animeId: widget.animeId,
      episodeId: widget.episodeId,
      animeTitle: widget.animeTitle,
      animeImage: widget.animeImage,
      episodeNumber: widget.episodeNumber,
      positionMs: positionMs,
      durationMs: effectiveDuration,
      lastWatched: DateTime.now(),
    );

    try {
      await ref
          .read(historyProvider.notifier)
          .saveHistory(history, syncToCloud: true);
      debugPrint('📝 VLC watch history saved: pos=$positionMs, dur=$effectiveDuration');
    } catch (e) {
      debugPrint('Failed to save VLC watch history: $e');
    }
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    setState(() {
      _showControls = true;
    });
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _lockControls() {
    _hideControlsTimer?.cancel();
    setState(() {
      _controlsLocked = true;
      _showControls = false;
    });
    _flashUnlockButton();
  }

  void _unlockControls() {
    _unlockButtonTimer?.cancel();
    setState(() {
      _controlsLocked = false;
      _showUnlockButton = false;
    });
    _resetHideTimer();
  }

  void _flashUnlockButton() {
    _unlockButtonTimer?.cancel();
    setState(() => _showUnlockButton = true);
    _unlockButtonTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showUnlockButton = false);
    });
  }

  /// Seeks once the media has loaded. mpv drops a seek issued while a stream
  /// is still opening, so streams restarted from the beginning even after
  /// choosing Resume; local files load fast enough that it went unnoticed.
  Future<void> _seekWhenReady(Duration target) async {
    try {
      if (player.state.duration == Duration.zero) {
        await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 30));
      }
    } on TimeoutException {
      debugPrint('⚠️ Media not loaded after 30s, seeking anyway');
    }
    await player.seek(target);

    // Some streams still ignore the first seek while buffering; retry once.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if ((player.state.position - target).abs() > const Duration(seconds: 5)) {
      await player.seek(target);
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _resetHideTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _showPlaybackSpeedDialog() {
    _resetHideTimer();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Playback Speed'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((speed) {
                return RadioListTile<double>(
                  title: Text('${speed}x'),
                  value: speed,
                  groupValue: _playbackSpeed,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _playbackSpeed = value;
                      });
                      player.setRate(value);
                      Navigator.pop(context);
                    }
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _showVolumeDialog() {
    _resetHideTimer();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Volume'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${(_volume * 100).round()}%',
                      style: const TextStyle(fontSize: 24)),
                  Slider(
                    value: _volume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label: '${(_volume * 100).round()}%',
                    onChanged: (value) {
                      setDialogState(() {
                        _volume = value;
                      });
                      setState(() {
                        _volume = value;
                      });
                      player.setVolume(_volume * 100);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${duration.inHours > 0 ? '${twoDigits(duration.inHours)}:' : ''}$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _enterPictureInPicture() async {
    if (!Platform.isAndroid) {
      _showMessage('PiP is only available on Android');
      return;
    }

    try {
      const platform = MethodChannel('com.animeapp.aniverse/pip');
      final result = await platform.invokeMethod('enterPipMode');

      if (result == true) {
        setState(() {
          _isInPipMode = true;
          _showControls = false;
        });
        debugPrint('Entered PiP mode');
      } else {
        _showMessage('PiP not available on this device');
      }
    } on PlatformException catch (e) {
      debugPrint('PiP PlatformException: ${e.code} - ${e.message}');
      _showMessage('Failed to enter PiP: ${e.message}');
    } catch (e) {
      debugPrint('PiP error: $e');
      _showMessage('PiP error: ${e.toString()}');
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadAutoRotatePreference();
    _setupOrientationListener();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    player = Player(
      configuration: const PlayerConfiguration(
        title: 'AniVerse Player',
        bufferSize: 64 * 1024 * 1024, // 64MB buffer for smoother streaming
      ),
    );
    controller = VideoController(player);
    
    // Defer initialization to allow context to be ready for dialogs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlayer();
    });

    _setupPositionListener();
    _resolveNextEpisode();
    _initSystemControls();

    // Start auto-hide timer for controls
    _resetHideTimer();

    _historySaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final position = player.state.position;
      final duration = player.state.duration;
      if (duration.inSeconds > 0 && position.inSeconds > 0) {
        _saveWatchHistory(position, duration);
      }
    });
  }

  Future<void> _loadAutoRotatePreference() async {
    final user = ref.read(currentUserProvider);
    if (user != null) {
      final prefs = await ref
          .read(firestoreServiceProvider)
          .getUserPreferences(user.uid)
          .first;
      if (mounted) {
        setState(() {
          _autoRotateEnabled = prefs['autoRotateEnabled'] as bool? ?? true;
        });
      }
    }
    await _applyCurrentOrientation();
  }

  void _setupOrientationListener() {
    if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return;
    }

    try {
      _orientationSubscription = NativeDeviceOrientationCommunicator()
          .onOrientationChanged(useSensor: true)
          .listen((orientation) {
        if (!mounted || !_autoRotateEnabled) return;
        _applyOrientation(orientation);
      });
    } catch (e) {
      debugPrint('Orientation listener not available: $e');
    }
  }

  void _applyOrientation(NativeDeviceOrientation orientation) {
    final DeviceOrientation preferred;
    switch (orientation) {
      case NativeDeviceOrientation.landscapeLeft:
        preferred = DeviceOrientation.landscapeLeft;
        break;
      case NativeDeviceOrientation.landscapeRight:
        preferred = DeviceOrientation.landscapeRight;
        break;
      case NativeDeviceOrientation.portraitUp:
        preferred = DeviceOrientation.portraitUp;
        break;
      case NativeDeviceOrientation.portraitDown:
        preferred = DeviceOrientation.portraitDown;
        break;
      default:
        return;
    }
    SystemChrome.setPreferredOrientations([preferred]);
  }

  /// The sensor stream only reports changes, so when auto-rotate is turned
  /// on (or the player opens) with the phone already sideways, nothing
  /// rotated until the phone moved again. Apply the current orientation now.
  Future<void> _applyCurrentOrientation() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      final orientation =
          await NativeDeviceOrientationCommunicator().orientation(useSensor: true);
      if (mounted && _autoRotateEnabled) _applyOrientation(orientation);
    } catch (e) {
      debugPrint('Could not read device orientation: $e');
    }
  }

  Future<void> _toggleAutoRotate() async {
    setState(() {
      _autoRotateEnabled = !_autoRotateEnabled;
    });
    if (_autoRotateEnabled) unawaited(_applyCurrentOrientation());

    final user = ref.read(currentUserProvider);
    if (user != null) {
      await ref.read(firestoreServiceProvider).updateUserPreferences(
        user.uid,
        {'autoRotateEnabled': _autoRotateEnabled},
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _autoRotateEnabled ? 'Auto-Rotate Enabled' : 'Auto-Rotate Disabled',
            textAlign: TextAlign.center,
          ),
          duration: const Duration(milliseconds: 1000),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
          width: 200,
        ),
      );
    }
  }

  Future<void> _initSystemControls() async {
    if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      _volume = 0.5;
      _brightness = 0.5;
      return;
    }

    try {
      _volume = await VolumeController.instance.getVolume();
      _brightness = await ScreenBrightness().current;
    } catch (e) {
      debugPrint('System controls not available: $e');
      _volume = 0.5;
      _brightness = 0.5;
    }
  }

  void _showGestureFeedback(IconData icon, String text) {
    setState(() {
      _showFeedback = true;
      _feedbackIcon = icon;
      _feedbackText = text;
    });

    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showFeedback = false;
          _feedbackIcon = null;
          _feedbackText = null;
        });
      }
    });
  }

  Future<void> _handleVolumeDrag(double delta) async {
    _volume += delta;
    _volume = _volume.clamp(0.0, 1.0);
    VolumeController.instance.setVolume(_volume);
    _showGestureFeedback(
      _volume > 0.5
          ? Icons.volume_up
          : _volume > 0
              ? Icons.volume_down
              : Icons.volume_off,
      '${(_volume * 100).toInt()}%',
    );
  }

  Future<void> _handleBrightnessDrag(double delta) async {
    if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return;
    }

    _brightness += delta;
    _brightness = _brightness.clamp(0.0, 1.0);
    try {
      await ScreenBrightness().setScreenBrightness(_brightness);
    } catch (e) {
      debugPrint('Failed to set brightness: $e');
    }
    _showGestureFeedback(
      _brightness > 0.5 ? Icons.brightness_7 : Icons.brightness_4,
      '${(_brightness * 100).toInt()}%',
    );
  }

  Future<void> _handleSeek(Duration delta) async {
    final current = player.state.position;
    final duration = player.state.duration;
    var newPos = current + delta;

    if (newPos < Duration.zero) newPos = Duration.zero;
    if (newPos > duration) newPos = duration;

    if (newPos > duration) newPos = duration;

    _lastSeekTime = DateTime.now();
    await player.seek(newPos);

    _showGestureFeedback(
      delta.isNegative ? Icons.replay_10 : Icons.forward_10,
      '${delta.isNegative ? "-" : "+"}${delta.inSeconds.abs()}s',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // App is in background or closed
      if (player.state.playing) {
        player.pause();
      }
      // Sync history to cloud when app goes to background
      final position = player.state.position;
      final duration = player.state.duration;
      if (duration.inSeconds > 0) {
        _saveWatchHistory(position, duration, syncToCloud: true);
      }
    }
  }

  Future<void> _initializePlayer() async {
    try {
      if (widget.isOffline && widget.offlineFilePath != null) {
        debugPrint('🎬 Playing offline: ${widget.offlineFilePath}');

        if (!kIsWeb && Platform.isLinux) {
          final externalPlayer = await _showExternalPlayerDialog();

          if (externalPlayer == null) {
            debugPrint('🐧 User cancelled external player selection for offline video');
             if (mounted) Navigator.of(context).pop();
            return;
          }

          debugPrint('🐧 Launching $externalPlayer for offline video on Linux');

          try {
            if (externalPlayer == 'vlc') {
              await _saveVlcWatchHistory(positionMs: 0);

              final vlcProcess = await Process.start('vlc', [
                '--meta-title=${widget.animeTitle} - Episode ${widget.episodeNumber}',
                widget.offlineFilePath!,
              ]);

              vlcProcess.exitCode.then((code) async {
                debugPrint('VLC exited with code: $code');
                if (code == 0) {
                  await _saveVlcWatchHistory(
                      positionMs: 22 * 60 * 1000, durationMs: 24 * 60 * 1000);
                }
              });
            } else if (externalPlayer == 'mpv') {
              // MPV Logic
              await _saveVlcWatchHistory(positionMs: 0); // Reuse history logic for now

              final mpvProcess = await Process.start('mpv', [
                '--title=${widget.animeTitle} - Episode ${widget.episodeNumber}',
                widget.offlineFilePath!,
              ]);

              mpvProcess.exitCode.then((code) async {
                 debugPrint('MPV exited with code: $code');
                 if (code == 0) {
                   await _saveVlcWatchHistory(
                      positionMs: 22 * 60 * 1000, durationMs: 24 * 60 * 1000);
                 }
              });
            }

            await Future.delayed(const Duration(milliseconds: 500));
            _hasPlayedSuccessfully = true;

            if (mounted) {
              Navigator.of(context).pop();
            }
            return;
          } catch (e) {
            debugPrint('Failed to launch external player: $e');
          }
        }




        await player.open(Media(widget.offlineFilePath!));

        final subtitleFile =
            File(DownloadService.subtitlePathFor(widget.offlineFilePath!));
        if (await subtitleFile.exists()) {
          unawaited(_loadSubtitle(subtitleFile.readAsString));
        }

        setState(() {
          isInitialized = true;
        });

        // Resume Logic for Offline
        final storage = ref.read(storageServiceProvider);
        final savedHistory = storage.getEpisodeHistory(widget.animeId, widget.episodeId);

        if (savedHistory != null && savedHistory.position > const Duration(seconds: 5)) {
          if (mounted) {
             await Future.delayed(Duration.zero);
             bool resume = false;
             await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.grey[900],
                title: const Text('Resume Playback', style: TextStyle(color: Colors.white)),
                content: Text(
                  'Resume from ${_formatDuration(savedHistory!.position)}?',
                  style: const TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      resume = false;
                      Navigator.pop(context);
                    },
                    child: const Text('Start Over', style: TextStyle(color: Colors.redAccent)),
                  ),
                  TextButton(
                    onPressed: () {
                      resume = true;
                      Navigator.pop(context);
                    },
                    child: const Text('Resume', style: TextStyle(color: Colors.blueAccent)),
                  ),
                ],
              ),
            );
            if (resume) await _seekWhenReady(savedHistory.position);
          }
        }

        await player.play();
        return;
      }

      // Standardize Raiden to use the same provider pipeline
      debugPrint(
          '🎬 Fetching video sources for: ${widget.episodeId} (type: $_translationType)');

      final sources = await ref.read(episodeSourcesWithTypeProvider((
        episodeId: widget.episodeId,
        translationType: _translationType,
      )).future);

      if (sources == null ||
          sources['sources'] == null ||
          (sources['sources'] as List).isEmpty) {
        final reason = ref.read(animeApiServiceProvider).lastSourceError;
        setState(() {
          hasError = true;
          errorMessage = 'No video sources available for $_translationType'
              '${reason == null ? '' : '\n\n$reason'}';
        });
        return;
      }

      _availableSources =
          List<Map<String, dynamic>>.from(sources['sources'] as List);
      debugPrint('✅ Loaded ${_availableSources.length} sources');

      await _playCurrentSource();
    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing player: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      setState(() {
        hasError = true;
        errorMessage = 'Failed to load video: $e';
      });
    }
  }

  static const _defaultStreamHeaders = {
    'Referer': 'https://mkissa.to',
    'User-Agent':
        'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
    'Origin': 'https://mkissa.to',
  };

  Future<void> _playCurrentSource() async {
    _sourceAttempt++;
    if (_currentSourceIndex >= _availableSources.length) {
      setState(() {
        hasError = true;
        errorMessage = 'All video sources failed';
      });
      return;
    }

    try {
      final source = _availableSources[_currentSourceIndex];
      final malId = source['malId'] as String?;
      if (malId != null && !_skipTimesRequested) {
        _skipTimesRequested = true;
        unawaited(_loadSkipTimes(malId));
      }
      final videoUrl = source['url'];
      // Each provider needs its own Referer; fall back to the AllAnime one.
      final headers = Map<String, String>.from(
          (source['headers'] as Map?) ?? _defaultStreamHeaders);
      final subtitleUrl = source['subtitle'] as String?;
      debugPrint(
          '🎥 Playing URL (source ${_currentSourceIndex + 1}/${_availableSources.length}): ${videoUrl.substring(0, videoUrl.length > 80 ? 80 : videoUrl.length)}...');

      setState(() {
        hasError = false;
        errorMessage = null;
        isInitialized = false; // Show loading indicator
        _hasPlayedSuccessfully = false; // Reset success flag for new source
      });

      if (!kIsWeb && Platform.isLinux) {
        final externalPlayer = await _showExternalPlayerDialog();
        if (externalPlayer == null) {
          debugPrint('🐧 User cancelled external player selection');
          // If cancelling player selection, we probably shouldn't just fallback to internal player 
          // if the intent was to watch externally. But for now, returning stops the flow.
          // Or we could let it fall through to internal player? 
          // Let's assume on Linux if we are here we want external.
          // But wait, the original logic fell through to media_kit if not linux.
          // If we return here, we stop playback. The user can just play again if they want.
           setState(() {
            isInitialized = true; // Stop loading
          });
          return;
        }

        debugPrint(
            '🐧 Launching $externalPlayer on Linux (media_kit has rendering issues)');

        try {
          if (externalPlayer == 'vlc') {
            await _saveVlcWatchHistory(positionMs: 0);

            final vlcProcess = await Process.start('vlc', [
              '--http-referrer=${headers['Referer'] ?? ''}',
              '--http-user-agent=${headers['User-Agent'] ?? ''}',
              if (subtitleUrl != null) '--sub-file=$subtitleUrl',
              '--meta-title=${widget.animeTitle} - Episode ${widget.episodeNumber}',
              videoUrl,
            ]);

            vlcProcess.exitCode.then((code) async {
              debugPrint('VLC exited with code: $code');
              if (code == 0) {
                await _saveVlcWatchHistory(
                    positionMs: 22 * 60 * 1000, durationMs: 24 * 60 * 1000);
              } else if (mounted) {
                _playNextSource();
              }
            });
          } else if (externalPlayer == 'mpv') {
             await _saveVlcWatchHistory(positionMs: 0);

            final mpvProcess = await Process.start('mpv', [
              '--referrer=${headers['Referer'] ?? ''}',
              '--user-agent=${headers['User-Agent'] ?? ''}',
              if (subtitleUrl != null) '--sub-file=$subtitleUrl',
              '--title=${widget.animeTitle} - Episode ${widget.episodeNumber}',
              videoUrl,
            ]);

            mpvProcess.exitCode.then((code) async {
              debugPrint('MPV exited with code: $code');
              if (code == 0) {
                await _saveVlcWatchHistory(
                    positionMs: 22 * 60 * 1000, durationMs: 24 * 60 * 1000);
              } else if (mounted) {
                _playNextSource();
              }
            });
          }
          
          // Exit early - external player is handling playback
          await Future.delayed(const Duration(milliseconds: 500));
          _hasPlayedSuccessfully = true;
          
          if (mounted) {
            Navigator.of(context).pop();
          }
          return;
        } catch (e) {
          debugPrint('Failed to launch external player: $e');
        }
      }

      await player.open(
        Media(videoUrl, httpHeaders: headers),
        play: false,
      );

      if (subtitleUrl != null) {
        unawaited(_loadSubtitle(() => _fetchSubtitle(subtitleUrl, headers)));
      }

      final storage = ref.read(storageServiceProvider);
      final savedHistory =
          storage.getEpisodeHistory(widget.animeId, widget.episodeId);

      // Initialize player but don't play yet
      setState(() {
        isInitialized = true;
      });

      Duration? resumedFrom;
      if (savedHistory != null && savedHistory.position > const Duration(seconds: 5)) {
        // Show resume dialog
        if (mounted) {
           // We need to delay slightly to ensure context is valid if called immediately
           await Future.delayed(Duration.zero);
           
           bool resume = false;
           await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text('Resume Playback', style: TextStyle(color: Colors.white)),
              content: Text(
                'Resume from ${_formatDuration(savedHistory!.position)}?',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    resume = false;
                    Navigator.pop(context);
                  },
                  child: const Text('Start Over', style: TextStyle(color: Colors.redAccent)),
                ),
                TextButton(
                  onPressed: () {
                    resume = true;
                    Navigator.pop(context);
                  },
                  child: const Text('Resume', style: TextStyle(color: Colors.blueAccent)),
                ),
              ],
            ),
          );

          if (resume) {
            await _seekWhenReady(savedHistory.position);
            resumedFrom = savedHistory.position;
          }
        }
      }

      await player.play();

      // Sync history immediately when playback starts. Use the resume point:
      // the reported position can still be 0 while a stream loads, and saving
      // that would overwrite where the user left off.
      _saveWatchHistory(
          resumedFrom ?? player.state.position, player.state.duration,
          syncToCloud: true);

    } catch (e) {
      debugPrint('❌ Error playing source $_currentSourceIndex: $e');
      _playNextSource();
    }
  }

  /// Adds an external subtitle once the video has loaded.
  ///
  /// mpv only accepts `sub-add` for a loaded file, so adding the track right
  /// after `open()` worked or failed depending on timing. Waiting for the
  /// duration (known once the file is loaded) makes it deterministic, and
  /// fetching the text ourselves avoids mpv requesting it without headers.
  Future<void> _loadSubtitle(Future<String> Function() read) async {
    final attempt = _sourceAttempt;
    try {
      final text = await read();
      if (player.state.duration == Duration.zero) {
        await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 60));
      }
      // The user may have switched source or episode while this loaded.
      if (!mounted || attempt != _sourceAttempt) return;
      await player.setSubtitleTrack(
          SubtitleTrack.data(text, title: 'English', language: 'en'));
    } catch (e) {
      debugPrint('⚠️ Failed to load subtitles: $e');
      if (mounted && attempt == _sourceAttempt) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subtitles unavailable: $e')),
        );
      }
    }
  }

  Future<String> _fetchSubtitle(String url, Map<String, String> headers) async {
    for (var attempt = 1;; attempt++) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode} for subtitles');
        }
        return utf8.decode(response.bodyBytes, allowMalformed: true);
      } catch (_) {
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
  }

  /// Fetches intro/outro times from AniSkip, as ani-cli's ani-skip does.
  /// Optional: without them the skip button just doesn't appear.
  Future<void> _loadSkipTimes(String malId) async {
    try {
      final uri = Uri.parse('https://api.aniskip.com/v1/skip-times/'
          '$malId/${widget.episodeNumber}?types=op&types=ed');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return;
      final segments = PlaybackRules.parseSkipTimes(json);
      if (mounted) setState(() => _skipSegments = segments);
    } catch (e) {
      debugPrint('Skip times unavailable: $e');
    }
  }

  Future<void> _resolveNextEpisode() async {
    if (widget.animeId.startsWith('raiden_')) return;
    try {
      final details = await ref.read(animeDetailsProvider(widget.animeId).future);
      final episodes = details?['episodes'];
      if (episodes is List<Episode> && mounted) {
        _nextEpisode = PlaybackRules.nextEpisode(episodes, widget.episodeNumber);
      }
    } catch (e) {
      debugPrint('Could not resolve next episode: $e');
    }
  }

  void _onEpisodeCompleted() {
    if (_autoNextHandled || _nextEpisode == null || !mounted) return;
    _autoNextHandled = true;
    setState(() => _nextCountdown = 5);
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      final remaining = (_nextCountdown ?? 0) - 1;
      if (remaining <= 0) {
        timer.cancel();
        _playNextEpisode();
      } else {
        setState(() => _nextCountdown = remaining);
      }
    });
  }

  void _cancelAutoNext() {
    _nextTimer?.cancel();
    setState(() => _nextCountdown = null);
  }

  /// Opens the next episode in place of this one, using its download when
  /// there is one.
  void _playNextEpisode() {
    final next = _nextEpisode;
    if (next == null || !mounted) return;
    _nextTimer?.cancel();

    final download = ref.read(downloadByAnimeAndEpisodeProvider(
        (animeId: widget.animeId, episodeNumber: next.number)));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          episodeId: next.id,
          animeId: widget.animeId,
          animeTitle: widget.animeTitle,
          animeImage: widget.animeImage,
          episodeNumber: next.number,
          isOffline: download?.filePath != null,
          offlineFilePath: download?.filePath,
        ),
      ),
    );
  }

  void _playNextSource() {
    if (_failedSourceAttempt == _sourceAttempt) return;
    _failedSourceAttempt = _sourceAttempt;

    debugPrint('⚠️ Source $_currentSourceIndex failed, trying next...');
    if (_currentSourceIndex + 1 < _availableSources.length) {
      _currentSourceIndex++;
      _playCurrentSource();
    } else if (!_retriedSources && _availableSources.isNotEmpty) {
      debugPrint('🔁 All sources failed once, retrying from the first');
      _retriedSources = true;
      _currentSourceIndex = 0;
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _playCurrentSource();
      });
    } else {
      player.stop(); // Stop playback to prevent audio ghosting
      setState(() {
        hasError = true;
        errorMessage = 'Unable to play video. All sources failed.';
        isInitialized = true; // Stop loading indicator to show error
      });
    }
  }

  bool _hasPlayedSuccessfully = false; // Track if current source is valid

  void _setupPositionListener() {
    player.stream.position.listen((position) {
      final duration = player.state.duration;
      if (duration.inSeconds > 0) {
        // Mark as successfully played if we've played for more than 2 seconds
        if (!_hasPlayedSuccessfully && position.inSeconds > 2) {
          _hasPlayedSuccessfully = true;
          debugPrint('✅ Source marked as valid (played > 2s)');
        }

        if (position.inSeconds % 5 == 0) {
          _saveWatchHistory(position, duration);
        }
      }

      final skip = PlaybackRules.activeSkip(_skipSegments, position);
      if (!identical(skip, _activeSkip) && mounted) {
        setState(() => _activeSkip = skip);
      }
    });

    player.stream.completed.listen((completed) {
      if (completed) _onEpisodeCompleted();
    });

    // Track buffering state for loading indicator
    player.stream.buffering.listen((isBuffering) {
      if (mounted) {
        setState(() {
          _isBuffering = isBuffering;
        });
      }
    });

    player.stream.error.listen((error) {
      debugPrint('❌ Player error: $error');

      // A subtitle that fails to load doesn't stop the video from playing.
      if (error.contains('external file') || error.contains('.vtt')) {
        debugPrint('⚠️ Ignoring subtitle load error');
        return;
      }

      // If we haven't played successfully yet, assume source is bad and switch
      if (!_hasPlayedSuccessfully) {
        debugPrint('⚠️ Source failed at start, switching...');
        _playNextSource();
        return;
      }

      // Silently retry - buffering indicator will show automatically
      debugPrint('⚠️ Error during playback, retrying...');
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && !player.state.playing) {
          player.play();
        }
      });
    });
  }

  Future<void> _switchSource(int newIndex) async {
    if (newIndex == _currentSourceIndex || newIndex >= _availableSources.length)
      return;

    debugPrint('🔄 Switching to source $newIndex');
    // final currentPosition = player.state.position; // Optional: preserve position

    setState(() {
      _currentSourceIndex = newIndex;
    });

    await _playCurrentSource();
  }

  Future<void> _toggleTranslationType() async {
    debugPrint('🔄 Toggling translation type');
    final currentPosition = player.state.position;
    final newType = _translationType == 'sub' ? 'dub' : 'sub';

    setState(() {
      _translationType = newType;
      _currentSourceIndex = 0; // Reset to first source
      _retriedSources = false;
      isInitialized = false;
    });

    // Reload sources and player
    await _initializePlayer();

    // Seek to previous position if player initialized successfully
    if (isInitialized && currentPosition > Duration.zero) {
      await player.seek(currentPosition);
    }
  }

  Future<void> _saveWatchHistory(
    Duration position,
    Duration duration, {
    bool syncToCloud = false,
  }) async {
    if (!mounted) return;

    final history = WatchHistory(
      animeId: widget.animeId,
      episodeId: widget.episodeId,
      animeTitle: widget.animeTitle,
      animeImage: widget.animeImage,
      episodeNumber: widget.episodeNumber,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      lastWatched: DateTime.now(),
    );

    try {
      await ref
          .read(historyProvider.notifier)
          .saveHistory(history, syncToCloud: syncToCloud);
    } catch (e) {
      debugPrint('Failed to save watch history: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feedbackTimer?.cancel();
    _hideControlsTimer?.cancel();
    _unlockButtonTimer?.cancel();
    _nextTimer?.cancel();
    _historySaveTimer?.cancel();
    _orientationSubscription?.cancel();

    final position = player.state.position;
    final duration = player.state.duration;
    if (duration.inSeconds > 0 && mounted) {
      _saveWatchHistory(position, duration);
    }

    try {
      ScreenBrightness().resetScreenBrightness();
    } catch (_) {}

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    player.stop();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  errorMessage ?? 'An error occurred',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        // Force stop player before popping
        await player.stop();

        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: isInitialized
            ? Stack(
                children: [
                  // 1. Raw Video Player (no default controls)
                  Center(
                    child: Video(
                      controller: controller,
                      controls: NoVideoControls,
                      fit: _fit,
                      fill: Colors.black,
                      wakelock: true,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),

                  // 2. Gesture Controls Overlay (volume, brightness, seek)
                  Positioned.fill(
                    child: IgnorePointer(
                    ignoring: _controlsLocked,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      // Horizontal drag for seeking
                      onHorizontalDragStart: (details) {
                        final position = player.state.position;
                        setState(() {
                          _seekStartPosition = details.globalPosition.dx;
                          _seekTargetPosition = position;
                          _isSeeking = true;
                        });
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_seekStartPosition != null &&
                            _seekTargetPosition != null) {
                          final dragDistance =
                              details.globalPosition.dx - _seekStartPosition!;
                          final seekAmount = (dragDistance /
                                  MediaQuery.of(context).size.width) *
                              90; // 90 seconds per full screen width

                          final newPosition = _seekTargetPosition! +
                              Duration(seconds: seekAmount.round());
                          final duration = player.state.duration;

                          setState(() {
                            _seekTargetPosition = Duration(
                              milliseconds: newPosition.inMilliseconds
                                  .clamp(0, duration.inMilliseconds),
                            );
                            _feedbackIcon = seekAmount > 0
                                ? Icons.fast_forward
                                : Icons.fast_rewind;
                            _feedbackText =
                                '${_seekTargetPosition!.inMinutes}:${(_seekTargetPosition!.inSeconds % 60).toString().padLeft(2, '0')}';
                          });
                        }
                      },
                      onHorizontalDragEnd: (details) async {
                        if (_seekTargetPosition != null) {
                          _lastSeekTime = DateTime.now();
                          await player.seek(_seekTargetPosition!);
                        }
                        setState(() {
                          _isSeeking = false;
                          _seekStartPosition = null;
                          _seekTargetPosition = null;
                        });

                        // Hide feedback after a short delay
                        _feedbackTimer?.cancel();
                        _feedbackTimer =
                            Timer(const Duration(milliseconds: 500), () {
                          if (mounted) {
                            setState(() {
                              _feedbackIcon = null;
                              _feedbackText = null;
                            });
                          }
                        });
                      },
                      onVerticalDragStart: (details) {
                        _isDragging = true;
                        _dragStartVolume = _volume;
                        _dragStartBrightness = _brightness;
                      },
                      onVerticalDragUpdate: (details) {
                        // Vertical -> Volume/Brightness
                        final width = MediaQuery.of(context).size.width;
                        final dx = details.globalPosition.dx;
                        final delta = -details.delta.dy / 200;

                        if (dx > width / 2) {
                          _handleVolumeDrag(delta);
                        } else {
                          _handleBrightnessDrag(delta);
                        }
                      },
                      onVerticalDragEnd: (details) {
                        _isDragging = false;

                        _feedbackTimer?.cancel();
                        _feedbackTimer =
                            Timer(const Duration(milliseconds: 500), () {
                          if (mounted) {
                            setState(() {
                              _feedbackIcon = null;
                              _feedbackText = null;
                            });
                          }
                        });
                      },
                      onDoubleTapDown: (details) {
                        final width = MediaQuery.of(context).size.width;
                        final dx = details.globalPosition.dx;
                        if (dx < width / 3) {
                          _handleSeek(const Duration(seconds: -10));
                        } else if (dx > width * 2 / 3) {
                          _handleSeek(const Duration(seconds: 10));
                        }
                      },
                    ),
                    ),
                  ),

                  // Feedback overlay for seek
                  if (_isSeeking &&
                      _feedbackIcon != null &&
                      _feedbackText != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_feedbackIcon, color: Colors.white, size: 48),
                            const SizedBox(height: 8),
                            Text(
                              _feedbackText ?? '',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Transient feedback overlay (for volume/brightness)
                  if (!_isSeeking &&
                      _feedbackIcon != null &&
                      _feedbackText != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_feedbackIcon, color: Colors.white, size: 48),
                            const SizedBox(height: 8),
                            Text(
                              _feedbackText ?? '',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Buffering overlay (shows loading indicator when buffering)
                  if (_isBuffering)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                    ),

                  // 3. Modern Custom Controls Overlay
                  GestureDetector(
                    onTap: _controlsLocked ? _flashUnlockButton : _toggleControls,
                    behavior: HitTestBehavior.translucent,
                    child: AnimatedOpacity(
                      opacity: _showControls && !_controlsLocked ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: !_showControls || _controlsLocked,
                        child: StreamBuilder<bool>(
                          stream: player.stream.playing,
                          builder: (context, playingSnapshot) {
                            return StreamBuilder<Duration>(
                              stream: player.stream.position,
                              builder: (context, positionSnapshot) {
                                return StreamBuilder<Duration>(
                                  stream: player.stream.duration,
                                  builder: (context, durationSnapshot) {
                                    final isPlaying =
                                        playingSnapshot.data ?? false;
                                    final position =
                                        positionSnapshot.data ?? Duration.zero;
                                    final duration =
                                        durationSnapshot.data ?? Duration.zero;
                                    final progress = duration.inMilliseconds > 0
                                        ? position.inMilliseconds /
                                            duration.inMilliseconds
                                        : 0.0;

                                    return Stack(
                                      children: [
                                        // Top Bar
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            padding: EdgeInsets.only(
                                              top: MediaQuery.of(context)
                                                      .padding
                                                      .top +
                                                  4,
                                              left: 4,
                                              right: 4,
                                              bottom: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.black.withOpacity(0.7),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(
                                                      Icons.arrow_back,
                                                      color: Colors.white),
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '${widget.animeTitle} - Episode ${widget.episodeNumber}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Lock controls',
                                                  icon: const Icon(
                                                      Icons.lock_open,
                                                      color: Colors.white),
                                                  onPressed: _lockControls,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // Center Play/Pause Button
                                        Center(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color:
                                                  Colors.black.withOpacity(0.3),
                                            ),
                                            child: IconButton(
                                              iconSize: 72,
                                              icon: Icon(
                                                isPlaying
                                                    ? Icons.pause
                                                    : Icons.play_arrow,
                                                color: Colors.white,
                                                size: 72,
                                              ),
                                              onPressed: () {
                                                if (isPlaying) {
                                                  player.pause();
                                                } else {
                                                  player.play();
                                                }
                                              },
                                            ),
                                          ),
                                        ),

                                        // Bottom Bar
                                        Positioned(
                                          bottom: 0,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.bottomCenter,
                                                end: Alignment.topCenter,
                                                colors: [
                                                  Colors.black.withOpacity(0.8),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Timestamps Row
                                                Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(horizontal: 8),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        _formatDuration(
                                                            position),
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 12),
                                                      ),
                                                      Text(
                                                        _formatDuration(
                                                            duration),
                                                        style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(0.7),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                // Progress Slider
                                                SliderTheme(
                                                  data: SliderThemeData(
                                                    activeTrackColor:
                                                        Colors.red,
                                                    inactiveTrackColor: Colors
                                                        .white
                                                        .withOpacity(0.3),
                                                    thumbColor: Colors.red,
                                                    thumbShape:
                                                        const RoundSliderThumbShape(
                                                            enabledThumbRadius:
                                                                5),
                                                    overlayShape:
                                                        const RoundSliderOverlayShape(
                                                            overlayRadius: 10),
                                                    trackHeight: 3,
                                                  ),
                                                  child: Slider(
                                                    value: progress.clamp(
                                                        0.0, 1.0),
                                                    onChanged: (value) {
                                                      final seekPosition =
                                                          Duration(
                                                        milliseconds: (value *
                                                                duration
                                                                    .inMilliseconds)
                                                            .round(),
                                                      );
                                                      player.seek(seekPosition);
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                // Control Icons Row
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceEvenly,
                                                  children: [
                                                    // Sub/Dub toggle button
                                                    IconButton(
                                                      icon: Container(
                                                        padding: const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 6,
                                                            vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.black45,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                  3),
                                                        ),
                                                        child: Text(
                                                          _translationType
                                                              .toUpperCase(),
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                      onPressed: () {
                                                        _resetHideTimer();
                                                        _toggleTranslationType();
                                                      },
                                                    ),
                                                    // Quality selector
                                                    if (_availableSources.length >
                                                        1)
                                                      IconButton(
                                                        icon: const Icon(Icons.hd,
                                                            color: Colors.white,
                                                            size: 20),
                                                        onPressed: () {
                                                          QualitySelector.show(
                                                            context: context,
                                                            sources:
                                                                _availableSources,
                                                            currentIndex:
                                                                _currentSourceIndex,
                                                            onQualitySelected:
                                                                _switchSource,
                                                          );
                                                        },
                                                      ),
                                                    IconButton(
                                                      icon: Icon(
                                                        _autoRotateEnabled
                                                            ? Icons
                                                                .screen_rotation
                                                            : Icons
                                                                .screen_lock_rotation,
                                                        color: Colors.white,
                                                        size: 20,
                                                      ),
                                                      onPressed:
                                                          _toggleAutoRotate,
                                                    ),
                                                    IconButton(
                                                      icon: Icon(
                                                        _fit == BoxFit.contain
                                                            ? Icons.fit_screen
                                                            : _fit ==
                                                                    BoxFit.cover
                                                                ? Icons
                                                                    .zoom_out_map
                                                                : Icons
                                                                    .aspect_ratio,
                                                        color: Colors.white,
                                                        size: 20,
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          _fit = _fit ==
                                                                  BoxFit.contain
                                                              ? BoxFit.cover
                                                              : _fit ==
                                                                      BoxFit
                                                                          .cover
                                                                  ? BoxFit.fill
                                                                  : BoxFit
                                                                      .contain;
                                                        });
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.volume_up,
                                                          color: Colors.white,
                                                          size: 20),
                                                      onPressed: () {
                                                        _resetHideTimer();
                                                        _showVolumeDialog();
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.settings,
                                                          color: Colors.white,
                                                          size: 20),
                                                      onPressed: () {
                                                        _resetHideTimer();
                                                        _showPlaybackSpeedDialog();
                                                      },
                                                    ),
                                                    // Picture-in-Picture button (Android only)
                                                    if (Platform.isAndroid)
                                                      IconButton(
                                                        icon: const Icon(
                                                            Icons
                                                                .picture_in_picture_alt,
                                                            color: Colors.white,
                                                            size: 20),
                                                        onPressed: () {
                                                          _enterPictureInPicture();
                                                        },
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  // Skip intro/outro, shown while the playhead is in a segment
                  if (_activeSkip != null && !_controlsLocked)
                    Positioned(
                      right: 24,
                      bottom: 110,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        icon: const Icon(Icons.fast_forward),
                        label: Text(_activeSkip!.label),
                        onPressed: () {
                          final target = _activeSkip!.end;
                          setState(() => _activeSkip = null);
                          player.seek(target);
                        },
                      ),
                    ),

                  // Up next countdown after an episode ends
                  if (_nextCountdown != null && _nextEpisode != null)
                    Positioned(
                      right: 24,
                      bottom: 110,
                      child: Material(
                        color: Colors.black.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Up next: Episode ${_nextEpisode!.number}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Playing in $_nextCountdown s',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: _cancelAutoNext,
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: _playNextEpisode,
                                    child: const Text('Play now'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 4. Unlock button, shown briefly on tap while locked
                  if (_controlsLocked && _showUnlockButton)
                    Positioned(
                      left: 24,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Material(
                          color: Colors.black.withOpacity(0.6),
                          shape: const CircleBorder(),
                          child: IconButton(
                            iconSize: 32,
                            tooltip: 'Unlock controls',
                            icon: const Icon(Icons.lock, color: Colors.white),
                            onPressed: _unlockControls,
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        errorMessage!,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Future<String?> _showExternalPlayerDialog() async {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Select Video Player',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.video_library, color: Colors.orange),
                title: const Text('VLC Media Player',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'vlc'),
              ),
              ListTile(
                leading: const Icon(Icons.play_circle_outline, color: Colors.purple),
                title: const Text('MPV Player',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'mpv'),
              ),
            ],
          ),
        );
      },
    );
  }
}
