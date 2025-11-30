import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
    final position = player.state.position;
    final duration = player.state.duration;
    if (duration.inSeconds > 0) {
      _saveWatchHistory(position, duration);
    }

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
            ? Video(
                controller: controller,
                controls: MaterialVideoControls,
                fit: BoxFit.contain,
                fill: Colors.black,
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
