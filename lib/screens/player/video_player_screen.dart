import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../services/firestore_service.dart';
import '../../models/watch_history_model.dart';
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
  Timer? _hideControlsTimer;

  // Playback speed
  double _playbackSpeed = 1.0;

  // Picture-in-Picture state
  bool _isInPipMode = false;

  Timer? _historySaveTimer;

  // Buffering state
  bool _isBuffering = false;

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

    _initializePlayer();
    _setupPositionListener();
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

        List<DeviceOrientation> preferredOrientations;

        switch (orientation) {
          case NativeDeviceOrientation.landscapeLeft:
            preferredOrientations = [DeviceOrientation.landscapeLeft];
            break;
          case NativeDeviceOrientation.landscapeRight:
            preferredOrientations = [DeviceOrientation.landscapeRight];
            break;
          case NativeDeviceOrientation.portraitUp:
            preferredOrientations = [DeviceOrientation.portraitUp];
            break;
          case NativeDeviceOrientation.portraitDown:
            preferredOrientations = [DeviceOrientation.portraitDown];
            break;
          default:
            return;
        }

        SystemChrome.setPreferredOrientations(preferredOrientations);
      });
    } catch (e) {
      debugPrint('Orientation listener not available: $e');
    }
  }

  Future<void> _toggleAutoRotate() async {
    setState(() {
      _autoRotateEnabled = !_autoRotateEnabled;
    });

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
          debugPrint('🐧 Launching VLC for offline video on Linux');

          try {
            final vlcProcess = await Process.start('vlc', [
              '--meta-title=${widget.animeTitle} - Episode ${widget.episodeNumber}',
              widget.offlineFilePath!,
            ]);

            vlcProcess.exitCode.then((code) {
              debugPrint('VLC exited with code: $code');
            });

            await Future.delayed(const Duration(milliseconds: 500));
            _hasPlayedSuccessfully = true;

            if (mounted) {
              Navigator.of(context).pop();
            }
            return;
          } catch (e) {
            debugPrint('Failed to launch VLC: $e');
          }
        }

        await player.open(Media(widget.offlineFilePath!));

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
            if (resume) await player.seek(savedHistory.position);
          }
        }

        await player.play();
        return;
      }

      // Check if this is a Raiden source (episodeId starts with raiden_)
      if (widget.episodeId.startsWith('raiden_')) {
        debugPrint('🎬 Playing Raiden content: ${widget.episodeId}');

        // Get the Raiden data from cache
        final raidenData =
            ref.read(raidenAnimeDetailsProvider(widget.episodeId));

        if (raidenData != null && raidenData['download_url'] != null) {
          final directUrl = raidenData['download_url'] as String;
          debugPrint('✅ Got Raiden direct URL: $directUrl');

          if (!kIsWeb && Platform.isLinux) {
            debugPrint('🐧 Launching VLC for Raiden video on Linux');

            try {
              final vlcProcess = await Process.start('vlc', [
                '--meta-title=${widget.animeTitle} - Episode ${widget.episodeNumber}',
                directUrl,
              ]);

              vlcProcess.exitCode.then((code) {
                debugPrint('VLC exited with code: $code');
              });

              await Future.delayed(const Duration(milliseconds: 500));
              _hasPlayedSuccessfully = true;

              if (mounted) {
                Navigator.of(context).pop();
              }
              return;
            } catch (e) {
              debugPrint('Failed to launch VLC: $e');
            }
          }

          await player.open(Media(directUrl));

          setState(() {
            isInitialized = true;
          });

          // Resume Logic for Raiden
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
              if (resume) await player.seek(savedHistory.position);
            }
          }

          await player.play();
          return;
        } else {
          debugPrint('❌ No Raiden data found in cache');
          setState(() {
            hasError = true;
            errorMessage = 'Raiden content not found in cache';
          });
          return;
        }
      }

      // Original AllAnime logic
      debugPrint(
          '🎬 Fetching video sources for: ${widget.episodeId} (type: $_translationType)');

      final sources = await ref.read(episodeSourcesWithTypeProvider((
        episodeId: widget.episodeId,
        translationType: _translationType,
      )).future);

      if (sources == null ||
          sources['sources'] == null ||
          (sources['sources'] as List).isEmpty) {
        setState(() {
          hasError = true;
          errorMessage = 'No video sources available for $_translationType';
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

  Future<void> _playCurrentSource() async {
    if (_currentSourceIndex >= _availableSources.length) {
      setState(() {
        hasError = true;
        errorMessage = 'All video sources failed';
      });
      return;
    }

    try {
      final videoUrl = _availableSources[_currentSourceIndex]['url'];
      debugPrint(
          '🎥 Playing URL (source ${_currentSourceIndex + 1}/${_availableSources.length}): ${videoUrl.substring(0, videoUrl.length > 80 ? 80 : videoUrl.length)}...');

      setState(() {
        hasError = false;
        errorMessage = null;
        isInitialized = false; // Show loading indicator
        _hasPlayedSuccessfully = false; // Reset success flag for new source
      });

      if (!kIsWeb && Platform.isLinux) {
        debugPrint(
            '🐧 Launching VLC on Linux (media_kit has rendering issues)');

        try {
          final vlcProcess = await Process.start('vlc', [
            '--http-referrer=https://allanime.to',
            '--http-user-agent=Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
            '--meta-title=${widget.animeTitle} - Episode ${widget.episodeNumber}',
            videoUrl,
          ]);

          vlcProcess.exitCode.then((code) {
            debugPrint('VLC exited with code: $code');
            if (code != 0 && mounted) {
              _playNextSource();
            }
          });

          await Future.delayed(const Duration(milliseconds: 500));

          _hasPlayedSuccessfully = true;

          if (mounted) {
            Navigator.of(context).pop();
          }
          return;
        } catch (e) {
          debugPrint('Failed to launch VLC: $e');
        }
      }

      await player.open(
        Media(
          videoUrl,
          httpHeaders: {
            'Referer': 'https://allanime.to',
            'User-Agent':
                'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
            'Origin': 'https://allanime.to',
          },
        ),
        play: false,
      );

      final storage = ref.read(storageServiceProvider);
      final savedHistory =
          storage.getEpisodeHistory(widget.animeId, widget.episodeId);

      // Initialize player but don't play yet
      setState(() {
        isInitialized = true;
      });

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
            await player.seek(savedHistory.position);
          }
        }
      }

      await player.play();

      // Sync history immediately when playback starts
      _saveWatchHistory(
          player.state.position, player.state.duration,
          syncToCloud: true);

    } catch (e) {
      debugPrint('❌ Error playing source $_currentSourceIndex: $e');
      _playNextSource();
    }
  }

  void _playNextSource() {
    debugPrint('⚠️ Source $_currentSourceIndex failed, trying next...');
    if (_currentSourceIndex + 1 < _availableSources.length) {
      _currentSourceIndex++;
      _playCurrentSource();
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
                    onTap: _toggleControls,
                    behavior: HitTestBehavior.translucent,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: !_showControls,
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
                                                  icon: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black45,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      _translationType
                                                          .toUpperCase(),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
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
                                                if (_availableSources.length >
                                                    1)
                                                  IconButton(
                                                    icon: const Icon(Icons.hd,
                                                        color: Colors.white),
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
}
