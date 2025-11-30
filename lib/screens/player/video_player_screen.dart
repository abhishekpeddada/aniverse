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

  // Gesture State
  double _volume = 0.5;
  double _brightness = 0.5;
  bool _showFeedback = false;
  IconData? _feedbackIcon;
  String? _feedbackText;
  Timer? _feedbackTimer;
  
  // Drag State
  bool _isDragging = false;
  double _dragStartVolume = 0.5;
  double _dragStartBrightness = 0.5;
  Duration _dragStartPosition = Duration.zero;
  Duration _targetSeekPosition = Duration.zero;

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
    }
  }

  Future<void> _initializePlayer() async {
    try {
      debugPrint('🎬 Fetching fresh video sources for: ${widget.episodeId}');
      
      final sources = await ref.read(episodeSourcesProvider(widget.episodeId).future);
      
      if (sources == null || sources['sources'] == null || (sources['sources'] as List).isEmpty) {
        setState(() {
          hasError = true;
          errorMessage = 'No video sources available';
        });
        return;
      }

      final videoUrl = sources['sources'][0]['url'];
      debugPrint('🎥 Playing URL: ${videoUrl.substring(0, videoUrl.length > 80 ? 80 : videoUrl.length)}...');
      
      if (defaultTargetPlatform == TargetPlatform.linux) {
        debugPrint('🐧 Launching mpv on Linux');
        
        setState(() {
          errorMessage = 'Launching mpv player...';
        });
        
        final mpvProcess = await Process.start('mpv', [
          '--http-header-fields=Referer: https://allanime.to',
          '--user-agent=Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
          '--title=Anime Watcher - ${widget.animeTitle} Episode ${widget.episodeNumber}',
          videoUrl,
        ]);
        
        mpvProcess.exitCode.then((code) {
          debugPrint('🛑 mpv exited with code: $code');
        });
        
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }
      
      final storageService = ref.read(storageServiceProvider);
      // Get history for this specific episode
      final history = storageService.getEpisodeHistory(widget.animeId, widget.episodeId);
      
      await player.open(
        Media(videoUrl,
          httpHeaders: {
            'Referer': 'https://allanime.to',
            'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
            'Origin': 'https://allanime.to',
          },
        ),
      );
      
      debugPrint('✅ Video player initialized successfully');
      
      setState(() {
        isInitialized = true;
      });

      if (history != null && history.position.inSeconds > 0) {
        debugPrint('⏩ Resuming from ${history.position.inMinutes}:${history.position.inSeconds % 60}');
        await player.seek(history.position);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to load video: $e');
      debugPrint('📍 Stack: $stackTrace');
      setState(() {
        hasError = true;
        errorMessage = 'Failed to load video: $e';
      });
    }
  }

  void _setupPositionListener() {
    player.stream.position.listen((position) {
      final duration = player.state.duration;
      if (duration.inSeconds > 0 && position.inSeconds % 5 == 0) {
        _saveWatchHistory(position, duration);
      }
    });
  }

  void _saveWatchHistory(Duration position, Duration duration) {
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
    
    ref.read(historyProvider.notifier).saveHistory(history);
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
                        const Spacer(),
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
                        const Spacer(),
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

                  // 2. Gesture Detector - Limited to center area to not block controls
                  Positioned.fill(
                    top: 60, // Avoid top button bar
                    bottom: 100, // Avoid bottom controls
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (details) {
                        _isDragging = true;
                        _dragStartVolume = _volume;
                        _dragStartBrightness = _brightness;
                        _dragStartPosition = player.state.position;
                        _targetSeekPosition = _dragStartPosition;
                      },
                      onPanUpdate: (details) {
                        if (details.delta.dx.abs() > details.delta.dy.abs()) {
                          // Horizontal -> Seek
                          final seekDelta = Duration(milliseconds: (details.delta.dx * 500).toInt());
                          _targetSeekPosition += seekDelta;
                          
                          if (_targetSeekPosition < Duration.zero) _targetSeekPosition = Duration.zero;
                          if (_targetSeekPosition > player.state.duration) _targetSeekPosition = player.state.duration;
                          
                          setState(() {
                            _showFeedback = true;
                            _feedbackIcon = seekDelta.isNegative ? Icons.fast_rewind : Icons.fast_forward;
                            _feedbackText = _formatDuration(_targetSeekPosition);
                          });
                        } else {
                          // Vertical -> Volume/Brightness
                          final width = MediaQuery.of(context).size.width;
                          final dx = details.globalPosition.dx;
                          final delta = -details.delta.dy / 200;
                          
                          if (dx > width / 2) {
                            _handleVolumeDrag(delta);
                          } else {
                            _handleBrightnessDrag(delta);
                          }
                        }
                      },
                      onPanEnd: (details) async {
                        _isDragging = false;
                        if (_targetSeekPosition != _dragStartPosition) {
                          await player.seek(_targetSeekPosition);
                        }
                        
                        _feedbackTimer?.cancel();
                        _feedbackTimer = Timer(const Duration(milliseconds: 500), () {
                          if (mounted) {
                            setState(() {
                              _showFeedback = false;
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

                  // 3. Feedback Overlay
                  if (_showFeedback)
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
