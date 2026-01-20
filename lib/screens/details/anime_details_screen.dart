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
                      const Text(
                        'Episodes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
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
                    final isNextToWatch =
                        episode.id == widget.continueEpisodeId;

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

  Future<void> _showDownloadDialog(
    BuildContext context,
    WidgetRef ref,
    Episode episode,
    Anime anime,
  ) async {
    final translationType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Audio'),
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

    if (translationType != null && context.mounted) {
      final downloadService = ref.read(downloadServiceProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fetching video URL...'),
          duration: Duration(seconds: 2),
        ),
      );

      try {
        String? downloadUrl;
        String quality = 'default'; // Use default quality

        if (episode.id.startsWith('raiden_')) {
          final raidenData = ref.read(raidenAnimeDetailsProvider(episode.id));
          if (raidenData != null && raidenData['download_url'] != null) {
            downloadUrl = raidenData['download_url'] as String;
          }
        } else {
          final sources = await ref.read(episodeSourcesWithTypeProvider((
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

            if (nonM3u8Sources.isNotEmpty) {
              downloadUrl = nonM3u8Sources.first['url'] as String?;
              quality =
                  nonM3u8Sources.first['quality']?.toString() ?? 'default';
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Only streaming sources available - download may not work'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
              downloadUrl = sourcesList[0]['url'] as String?;
              quality = sourcesList[0]['quality']?.toString() ?? 'default';
            }
          }
        }

        if (downloadUrl == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('No video URL available for download')),
            );
          }
          return;
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Download started! (${translationType.toUpperCase()})'),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        await downloadService.startDownload(
          animeId: widget.animeId,
          animeTitle: anime.title,
          animeImage: anime.image,
          episodeId: episode.id,
          episodeNumber: episode.number,
          episodeTitle: episode.title,
          downloadUrl: downloadUrl,
          quality: quality,
        );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $e')),
          );
        }
      }
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
