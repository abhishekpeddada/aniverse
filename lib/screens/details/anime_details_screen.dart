import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/anime_provider.dart';
import '../../providers/lists_provider.dart';
import '../../providers/storage_provider.dart';
import '../../providers/raiden_provider.dart';
import '../../providers/download_provider.dart';
import '../../models/episode_model.dart';
import '../../models/anime_model.dart';
import '../../models/download_model.dart';
import '../../services/raiden_api_service.dart';
import '../../providers/history_provider.dart';
import '../../utils/playback_rules.dart';
import '../player/video_player_screen.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

class AnimeDetailsScreen extends ConsumerStatefulWidget {
  final String animeId;
  final String? continueEpisodeId;

  const AnimeDetailsScreen({
    super.key,
    required this.animeId,
    this.continueEpisodeId,
  });

  @override
  ConsumerState<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends ConsumerState<AnimeDetailsScreen> {
  /// Episodes whose download was requested and is still being set up or
  /// running; their button shows progress instead of a snackbar.
  final Set<String> _preparingDownloads = {};

  /// Episodes waiting their turn in a "download all" batch.
  final Set<String> _queuedDownloads = {};
  bool _downloadingAll = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // For Raiden anime, we now use the standard provider which handles the data conversion
    
    // For AllAnime, use existing logic
    final animeDetails = ref.watch(animeDetailsProvider(widget.animeId));
    final watchlist = ref.watch(watchlistProvider);
    final favorites = ref.watch(favoritesProvider);

    final isInWatchlist = watchlist.contains(widget.animeId);
    final isInFavorites = favorites.contains(widget.animeId);
    final storageService = ref.watch(storageServiceProvider);

    return Scaffold(
      body: animeDetails.when(
        data: (data) {
          if (data == null) {
            return const Center(
              child: Text('Failed to load anime details'),
            );
          }

          final anime = data['anime'];
          final episodes = data['episodes'] as List<Episode>;

          // Recomputed from live history, so finishing an episode moves the
          // highlight without reopening the app.
          final continueEpisodeId = PlaybackRules.continueEpisodeId(
            history: ref.watch(historyProvider),
            animeId: widget.animeId,
            episodes: episodes,
            fallback: widget.continueEpisodeId,
          );

          // Cache the anime for watchlist/favorites display
          storageService.cacheAnime(anime);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    anime.title,
                    style: const TextStyle(
                      shadows: [Shadow(color: Colors.black, blurRadius: 10)],
                    ),
                  ),
                  background: anime.image != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: anime.image!,
                              fit: BoxFit.cover,
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    const Color.fromRGBO(0, 0, 0, 0.7),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(color: Colors.grey[900]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (isInWatchlist) {
                                  ref
                                      .read(watchlistProvider.notifier)
                                      .removeFromWatchlist(widget.animeId);
                                } else {
                                  ref
                                      .read(watchlistProvider.notifier)
                                      .addToWatchlist(widget.animeId);
                                }
                              },
                              icon: Icon(
                                isInWatchlist
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                              ),
                              label: Text(isInWatchlist
                                  ? 'In Watchlist'
                                  : 'Add to Watchlist'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (isInFavorites) {
                                  ref
                                      .read(favoritesProvider.notifier)
                                      .removeFromFavorites(widget.animeId);
                                } else {
                                  ref
                                      .read(favoritesProvider.notifier)
                                      .addToFavorites(widget.animeId);
                                }
                              },
                              icon: Icon(
                                isInFavorites
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                              ),
                              label: Text(isInFavorites
                                  ? 'Favorited'
                                  : 'Add to Favorites'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (anime.genres != null && anime.genres!.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: anime.genres!
                              .map((genre) => Chip(
                                    label: Text(genre),
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (anime.status != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 18),
                            const SizedBox(width: 8),
                            Text('Status: ${anime.status}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (anime.totalEpisodes != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.video_library, size: 18),
                            const SizedBox(width: 8),
                            Text('Total Episodes: ${anime.totalEpisodes}'),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (anime.description != null) ...[
                        const Text(
                          'Synopsis',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        HtmlWidget(
                          anime.description!,
                          textStyle: TextStyle(color: Colors.grey[300]),
                        ),
                        const SizedBox(height: 24),
                      ],
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Episodes',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (_downloadingAll)
                            const SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                ),
                              ),
                            )
                          else
                            IconButton(
                              tooltip: 'Download all episodes',
                              icon: const Icon(Icons.download_for_offline_outlined),
                              onPressed: () =>
                                  _downloadAll(context, episodes, anime),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Episode Search
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search episodes...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[900],
                        ),
                        onChanged: (value) {
                          setState(() => _searchQuery = value.toLowerCase());
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    // Filter episodes
                    final filteredEpisodes = episodes.where((ep) {
                      if (_searchQuery.isEmpty) return true;
                      final epNum = ep.number.toString();
                      final epTitle = ep.title?.toLowerCase() ?? '';
                      return epNum.contains(_searchQuery) ||
                          epTitle.contains(_searchQuery);
                    }).toList();

                    if (index >= filteredEpisodes.length) return null;

                    final episode = filteredEpisodes[index];
                    final isNextToWatch = episode.id == continueEpisodeId;

                    return Container(
                      color:
                          isNextToWatch ? Colors.red.withOpacity(0.15) : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isNextToWatch ? Colors.red : null,
                          foregroundColor: isNextToWatch ? Colors.white : null,
                          child: Text('${episode.number}'),
                        ),
                        title: Text(
                          episode.title ?? 'Episode ${episode.number}',
                          style: isNextToWatch
                              ? const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold)
                              : null,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Consumer(
                              builder: (context, ref, _) {
                                final isDownloadedById = ref.watch(
                                  isEpisodeDownloadedProvider(episode.id),
                                );
                                final isDownloadedByDetails = ref.watch(
                                  downloadByAnimeAndEpisodeProvider((animeId: widget.animeId, episodeNumber: episode.number)),
                                ) != null;
                                final isDownloaded = isDownloadedById || isDownloadedByDetails;

                                // While fetching the link or downloading, show progress
                                // in place of the button: a ring filling with the
                                // download, or a spinner until its size is known.
                                final active = ref.watch(activeDownloadProvider(
                                    (animeId: widget.animeId, episodeNumber: episode.number)));
                                if (!isDownloaded &&
                                    active == null &&
                                    _queuedDownloads.contains(episode.id)) {
                                  return const SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                      child: Icon(Icons.hourglass_empty,
                                          size: 22, color: Colors.grey),
                                    ),
                                  );
                                }
                                if (!isDownloaded &&
                                    (active != null ||
                                        _preparingDownloads.contains(episode.id))) {
                                  final progress = active != null && active.totalBytes > 0
                                      ? (active.downloadedBytes / active.totalBytes)
                                          .clamp(0.0, 1.0)
                                      : null;
                                  return SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          value: progress,
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                return IconButton(
                                  icon: Icon(
                                    isDownloaded
                                        ? Icons.download_done
                                        : Icons.download_outlined,
                                    color: isDownloaded ? Colors.green : null,
                                  ),
                                  onPressed: () {
                                    if (isDownloaded) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Episode already downloaded'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    } else {
                                      _showDownloadDialog(
                                        context,
                                        ref,
                                        episode,
                                        anime,
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                            Consumer(
                              builder: (context, ref, _) {
                                // Check for downloaded file for play button
                                final downloadedEp = ref.watch(downloadByEpisodeProvider(episode.id)) ?? 
                                                     ref.watch(downloadByAnimeAndEpisodeProvider((animeId: widget.animeId, episodeNumber: episode.number)));
                                final isDownloaded = downloadedEp != null;

                                return IconButton(
                                  icon: Icon(
                                    Icons.play_arrow,
                                    color: isNextToWatch ? Colors.red : null,
                                  ),
                                  onPressed: () {
                                      // If downloaded, play offline
                                      if (isDownloaded) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => VideoPlayerScreen(
                                                  episodeId: episode.id,
                                                  animeId: widget.animeId,
                                                  animeTitle: anime.title,
                                                  animeImage: anime.image,
                                                  episodeNumber: episode.number,
                                                  isOffline: true,
                                                  offlineFilePath: downloadedEp.filePath,
                                                ),
                                              ),
                                            );
                                      } else {
                                        // Online playback
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => VideoPlayerScreen(
                                              episodeId: episode.id,
                                              animeId: widget.animeId,
                                              animeTitle: anime.title,
                                              animeImage: anime.image,
                                              episodeNumber: episode.number,
                                            ),
                                          ),
                                        );
                                      }
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          // Also handle ListTile tap
                          final downloadedEp = ref.read(downloadByEpisodeProvider(episode.id)) ?? 
                                               ref.read(downloadByAnimeAndEpisodeProvider((animeId: widget.animeId, episodeNumber: episode.number)));
                           
                          if (downloadedEp != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VideoPlayerScreen(
                                      episodeId: episode.id,
                                      animeId: widget.animeId,
                                      animeTitle: anime.title,
                                      animeImage: anime.image,
                                      episodeNumber: episode.number,
                                      isOffline: true,
                                      offlineFilePath: downloadedEp.filePath,
                                    ),
                                  ),
                                );
                          } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VideoPlayerScreen(
                                      episodeId: episode.id,
                                      animeId: widget.animeId,
                                      animeTitle: anime.title,
                                      animeImage: anime.image,
                                      episodeNumber: episode.number,
                                    ),
                                  ),
                                );
                          }
                        },
                      ),
                    );
                  },
                  childCount: null, // Dynamic based on filter
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _pickTranslationType(BuildContext context,
      {String title = 'Select Audio'}) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('SUB (Subtitled)'),
              leading: const Icon(Icons.subtitles),
              onTap: () => Navigator.pop(context, 'sub'),
            ),
            ListTile(
              title: const Text('DUB (Dubbed)'),
              leading: const Icon(Icons.record_voice_over),
              onTap: () => Navigator.pop(context, 'dub'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDownloadDialog(
    BuildContext context,
    WidgetRef ref,
    Episode episode,
    Anime anime,
  ) async {
    final translationType = await _pickTranslationType(context);
    if (translationType == null || !context.mounted) return;

    final error = await _downloadEpisode(
      ProviderScope.containerOf(context, listen: false),
      episode,
      anime,
      translationType,
    );
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// Downloads every episode that isn't downloaded or downloading yet, one
  /// at a time, with a single sub/dub choice. Failures are reported once at
  /// the end rather than per episode.
  Future<void> _downloadAll(
    BuildContext context,
    List<Episode> episodes,
    Anime anime,
  ) async {
    // The app-wide container outlives this screen, so the batch keeps going
    // if the user navigates away.
    final container = ProviderScope.containerOf(context, listen: false);
    final pending = episodes.where((e) {
      final key = (animeId: widget.animeId, episodeNumber: e.number);
      return !container.read(isEpisodeDownloadedProvider(e.id)) &&
          container.read(downloadByAnimeAndEpisodeProvider(key)) == null &&
          container.read(activeDownloadProvider(key)) == null &&
          !_preparingDownloads.contains(e.id);
    }).toList();

    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('All episodes are already downloaded'),
        duration: Duration(seconds: 2),
      ));
      return;
    }

    final translationType = await _pickTranslationType(
      context,
      title: 'Download ${pending.length} episode${pending.length == 1 ? '' : 's'}',
    );
    if (translationType == null || !mounted) return;

    setState(() {
      _downloadingAll = true;
      _queuedDownloads.addAll(pending.map((e) => e.id));
    });

    final failed = <int>[];
    try {
      for (final episode in pending) {
        if (mounted) setState(() => _queuedDownloads.remove(episode.id));
        final error =
            await _downloadEpisode(container, episode, anime, translationType);
        if (error != null) failed.add(episode.number);
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingAll = false;
          _queuedDownloads.clear();
        });
      }
    }

    if (failed.isNotEmpty && mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
        content: Text('Couldn\'t download episode${failed.length == 1 ? '' : 's'} '
            '${failed.join(', ')}'),
      ));
    }
  }

  /// Downloads one episode and returns an error message, or null on success.
  Future<String?> _downloadEpisode(
    ProviderContainer container,
    Episode episode,
    Anime anime,
    String translationType,
  ) async {
    final downloadService = container.read(downloadServiceProvider);
    if (mounted) setState(() => _preparingDownloads.add(episode.id));

    try {
      String? downloadUrl;
      String quality = 'default'; // Use default quality
      Map<String, String>? headers;
      String? subtitleUrl;
      String? malId;

      if (episode.id.startsWith('raiden_')) {
        final raidenData = container.read(raidenAnimeDetailsProvider(episode.id));
        if (raidenData != null && raidenData['download_url'] != null) {
          downloadUrl = raidenData['download_url'] as String;
          headers = RaidenApiService.streamHeaders;
        }
      } else {
        final sources = await container.read(episodeSourcesWithTypeProvider((
          episodeId: episode.id,
          translationType: translationType, // Use selected type
        )).future);

        if (sources != null &&
            sources['sources'] != null &&
            (sources['sources'] as List).isNotEmpty) {
          final sourcesList =
              List<Map<String, dynamic>>.from(sources['sources'] as List);

          // Prefer non-M3U8 sources, otherwise use first available
          var nonM3u8Sources = sourcesList
              .where((s) => !s['url'].toString().contains('.m3u8'))
              .toList();

          final Map<String, dynamic> source;
          if (nonM3u8Sources.isNotEmpty) {
            source = nonM3u8Sources.first;
            quality = source['quality']?.toString() ?? 'default';
          } else {
            // HLS streams are saved segment by segment. Label them by
            // sub/dub so a resumed download fetches the same stream type.
            source = sourcesList.first;
            quality = translationType;
          }
          downloadUrl = source['url'] as String?;
          headers = (source['headers'] as Map?)?.cast<String, String>();
          subtitleUrl = source['subtitle'] as String?;
          malId = source['malId'] as String?;
        }
      }

      if (downloadUrl == null) return 'No video URL available for download';

      await downloadService.startDownload(
        animeId: widget.animeId,
        animeTitle: anime.title,
        animeImage: anime.image,
        episodeId: episode.id,
        episodeNumber: episode.number,
        episodeTitle: episode.title,
        downloadUrl: downloadUrl,
        quality: quality,
        headers: headers,
        subtitleUrl: subtitleUrl,
        malId: malId,
      );
      return null;
    } catch (e) {
      return 'Download failed: $e';
    } finally {
      if (mounted) setState(() => _preparingDownloads.remove(episode.id));
    }
  }

  String _getQualitySize(String quality) {
    switch (quality) {
      case '360p':
        return '~100MB';
      case '480p':
        return '~200MB';
      case '720p':
        return '~400MB';
      case '1080p':
        return '~800MB';
      default:
        return '';
    }
  }
}
