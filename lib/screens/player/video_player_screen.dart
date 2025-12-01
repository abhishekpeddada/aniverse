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
import '../../providers/anime_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/storage_provider.dart';
import '../../models/watch_history_model.dart';
import 'widgets/quality_selector.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String episodeId;
  final String animeId;
  final String animeTitle;
  final String? animeImage;
  final int episodeNumber;

  const VideoPlayerScreen({
    super.key,
    required this.episodeId,
    required this.animeId,
    required this.animeTitle,
    this.animeImage,
    required this.episodeNumber,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> with WidgetsBindingObserver {
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
  DateTime? _lastSeekTime; // To prevent error triggering during seek

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${duration.inHours > 0 ? '${twoDigits(duration.inHours)}:' : ''}$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    player = Player();
    controller = VideoController(player);
    
    _initializePlayer();
    _setupPositionListener();
    _initSystemControls();
  }

  Future<void> _initSystemControls() async {
    try {
      _volume = await VolumeController.instance.getVolume();
      _brightness = await ScreenBrightness().current;
    } catch (e) {
      debugPrint('Error initializing system controls: $e');
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
      _volume > 0.5 ? Icons.volume_up : _volume > 0 ? Icons.volume_down : Icons.volume_off,
      '${(_volume * 100).toInt()}%',
    );
  }

  Future<void> _handleBrightnessDrag(double delta) async {
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
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
      debugPrint('🎬 Fetching video sources for: ${widget.episodeId} (type: $_translationType)');
      
      final sources = await ref.read(episodeSourcesWithTypeProvider((
        episodeId: widget.episodeId,
        translationType: _translationType,
      )).future);
      
      if (sources == null || sources['sources'] == null || (sources['sources'] as List).isEmpty) {
        setState(() {
          hasError = true;
          errorMessage = 'No video sources available for $_translationType';
        });
        return;
      }

      _availableSources = List<Map<String, dynamic>>.from(sources['sources'] as List);
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
      debugPrint('🎥 Playing URL (source ${_currentSourceIndex + 1}/${_availableSources.length}): ${videoUrl.substring(0, videoUrl.length > 80 ? 80 : videoUrl.length)}...');
      
      setState(() {
        hasError = false;
        errorMessage = null;
        isInitialized = false; // Show loading indicator
        _hasPlayedSuccessfully = false; // Reset success flag for new source
      });

      if (defaultTargetPlatform == TargetPlatform.linux) {
        // ... Linux specific code (omitted for brevity, assuming it handles its own errors or we wrap it)
        // For now, keeping existing Linux logic but wrapping in try-catch
        debugPrint('🐧 Launching mpv on Linux');
        await player.stop(); // Ensure internal player is stopped
        final mpvProcess = await Process.start('mpv', [
          '--http-header-fields=Referer: https://allanime.to',
          '--user-agent=Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
          '--title=Anime Watcher - ${widget.animeTitle} Episode ${widget.episodeNumber}',
          videoUrl,
        ]);
        mpvProcess.exitCode.then((code) {
          if (code != 0) _playNextSource();
        });
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop();
        return;
      }

      await player.open(
        Media(videoUrl,
          httpHeaders: {
            'Referer': 'https://allanime.to',
            'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
            'Origin': 'https://allanime.to',
          },
        ),
        play: false,
      );

      final storage = ref.read(storageServiceProvider);
      final savedHistory = storage.getEpisodeHistory(widget.animeId, widget.episodeId);
      
      if (savedHistory != null && savedHistory.position > Duration.zero) {
        await player.seek(savedHistory.position);
      }

      await player.play();

      // Sync history immediately when playback starts (without position)
      _saveWatchHistory(
        savedHistory?.position ?? Duration.zero, 
        player.state.duration, 
        syncToCloud: true
      );

      setState(() {
        isInitialized = true;
      });
      
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
    
    player.stream.error.listen((error) {
      debugPrint('❌ Player error: $error');
      
      // If we haven't played successfully yet, assume source is bad and switch
      if (!_hasPlayedSuccessfully) {
        debugPrint('⚠️ Source failed at start, switching...');
        _playNextSource();
        return;
      }

      // If we HAVE played successfully, this is likely a network/seek error.
      // Do NOT switch source automatically. Just notify user and try to resume.
      debugPrint('⚠️ Error during playback/seek. Retrying...');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Buffering error. Waiting...'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Next Source',
            onPressed: _playNextSource,
            textColor: Colors.yellow,
          ),
        ),
      );
      
      // Attempt to resume after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && !player.state.playing) {
          player.play();
        }
      });
    });
  }

  Future<void> _switchSource(int newIndex) async {
    if (newIndex == _currentSourceIndex || newIndex >= _availableSources.length) return;
    
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

  void _saveWatchHistory(Duration position, Duration duration, {bool syncToCloud = false}) {
    final history = WatchHistory(
      animeId: widget.animeId,
      animeTitle: widget.animeTitle,
      animeImage: widget.animeImage,
      episodeNumber: widget.episodeNumber,
      episodeId: widget.episodeId,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      lastWatched: DateTime.now(),
    );
    
    ref.read(historyProvider.notifier).saveHistory(history, syncToCloud: syncToCloud);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feedbackTimer?.cancel(); // Cancel feedback timer
    final position = player.state.position;
    final duration = player.state.duration;
    if (duration.inSeconds > 0) {
      _saveWatchHistory(position, duration);
    }
    
    // Reset brightness
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

    player.stop(); // Force stop playback
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
                  // 1. Video Player with Native Controls
                  MaterialVideoControlsTheme(
                    normal: MaterialVideoControlsThemeData(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
                      topButtonBar: [
                        // Sub/Dub Toggle
                        // Always show sub/dub button
                          MaterialCustomButton(
                            onPressed: _toggleTranslationType,
                            icon: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _translationType.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        // Quality Selector
                        if (_availableSources.length > 1)
                          MaterialCustomButton(
                            onPressed: () {
                              QualitySelector.show(
                                context: context,
                                sources: _availableSources,
                                currentIndex: _currentSourceIndex,
                                onQualitySelected: _switchSource,
                              );
                            },
                            icon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.hd, color: Colors.white, size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  _availableSources[_currentSourceIndex]['quality'] as String,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Spacer(),
                        // Fit/Zoom Toggle
                        MaterialCustomButton(
                          onPressed: () {
                            setState(() {
                              switch (_fit) {
                                case BoxFit.contain: _fit = BoxFit.cover; break;
                                case BoxFit.cover: _fit = BoxFit.fill; break;
                                case BoxFit.fill: _fit = BoxFit.fitWidth; break;
                                default: _fit = BoxFit.contain;
                              }
                            });
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _fit == BoxFit.contain ? 'Fit to Screen' :
                                  _fit == BoxFit.cover ? 'Zoom to Fill' :
                                  _fit == BoxFit.fill ? 'Stretch to Fill' : 'Full Width',
                                  textAlign: TextAlign.center,
                                ),
                                duration: const Duration(milliseconds: 1000),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.black87,
                                width: 200,
                              ),
                            );
                          },
                          icon: Icon(
                            _fit == BoxFit.contain ? Icons.fullscreen_exit :
                            _fit == BoxFit.cover ? Icons.zoom_out_map :
                            _fit == BoxFit.fill ? Icons.aspect_ratio : Icons.fit_screen,
                            color: Colors.white,
                          ),
                        ),
                      ],
                      bottomButtonBar: [
                        const MaterialPlayOrPauseButton(),
                        const MaterialPositionIndicator(),
                        const Spacer(),
                      ],
                    ),
                    fullscreen: MaterialVideoControlsThemeData(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
                      topButtonBar: [
                        // Sub/Dub Toggle
                        // Always show sub/dub button
                          MaterialCustomButton(
                            onPressed: _toggleTranslationType,
                            icon: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _translationType.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        // Quality Selector
                        if (_availableSources.length > 1)
                          MaterialCustomButton(
                            onPressed: () {
                              QualitySelector.show(
                                context: context,
                                sources: _availableSources,
                                currentIndex: _currentSourceIndex,
                                onQualitySelected: _switchSource,
                              );
                            },
                            icon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.hd, color: Colors.white, size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  _availableSources[_currentSourceIndex]['quality'] as String,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Spacer(),
                        // Fit/Zoom Toggle
                        MaterialCustomButton(
                          onPressed: () {
                            setState(() {
                              switch (_fit) {
                                case BoxFit.contain: _fit = BoxFit.cover; break;
                                case BoxFit.cover: _fit = BoxFit.fill; break;
                                case BoxFit.fill: _fit = BoxFit.fitWidth; break;
                                default: _fit = BoxFit.contain;
                              }
                            });
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _fit == BoxFit.contain ? 'Fit to Screen' :
                                  _fit == BoxFit.cover ? 'Zoom to Fill' :
                                  _fit == BoxFit.fill ? 'Stretch to Fill' : 'Full Width',
                                  textAlign: TextAlign.center,
                                ),
                                duration: const Duration(milliseconds: 1000),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.black87,
                                width: 200,
                              ),
                            );
                          },
                          icon: Icon(
                            _fit == BoxFit.contain ? Icons.fullscreen_exit :
                            _fit == BoxFit.cover ? Icons.zoom_out_map :
                            _fit == BoxFit.fill ? Icons.aspect_ratio : Icons.fit_screen,
                            color: Colors.white,
                          ),
                        ),
                      ],
                      bottomButtonBar: [
                        const MaterialPlayOrPauseButton(),
                        const MaterialPositionIndicator(),
                        const Spacer(),
                      ],
                    ),
                    child: Center(
                      child: Video(
                        controller: controller,
                        controls: MaterialVideoControls,
                        fit: _fit,
                        fill: Colors.black,
                      ),
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
                        if (_seekStartPosition != null && _seekTargetPosition != null) {
                          final dragDistance = details.globalPosition.dx - _seekStartPosition!;
                          final seekAmount = (dragDistance / MediaQuery.of(context).size.width) * 90; // 90 seconds per full screen width
                          
                          final newPosition = _seekTargetPosition! + Duration(seconds: seekAmount.round());
                          final duration = player.state.duration;
                          
                          setState(() {
                            _seekTargetPosition = Duration(
                              milliseconds: newPosition.inMilliseconds.clamp(0, duration.inMilliseconds),
                            );
                            _feedbackIcon = seekAmount > 0 ? Icons.fast_forward : Icons.fast_rewind;
                            _feedbackText = '${_seekTargetPosition!.inMinutes}:${(_seekTargetPosition!.inSeconds % 60).toString().padLeft(2, '0')}';
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
                        _feedbackTimer = Timer(const Duration(milliseconds: 500), () {
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
                        _feedbackTimer = Timer(const Duration(milliseconds: 500), () {
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
                  if (_isSeeking && _feedbackIcon != null && _feedbackText != null)
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
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Transient feedback overlay (for volume/brightness)
                  if (!_isSeeking && _feedbackIcon != null && _feedbackText != null)                  Center(
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
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ],
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
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
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
