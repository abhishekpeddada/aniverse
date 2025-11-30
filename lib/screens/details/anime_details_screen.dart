import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/anime_provider.dart';
import '../../providers/lists_provider.dart';
import '../../providers/storage_provider.dart';
import '../../models/episode_model.dart';
import '../player/video_player_screen.dart';

class AnimeDetailsScreen extends ConsumerWidget {
  final String animeId;

  const AnimeDetailsScreen({super.key, required this.animeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animeDetails = ref.watch(animeDetailsProvider(animeId));
    final isInWatchlist = ref.watch(watchlistProvider.notifier).isInWatchlist(animeId);
    final isInFavorites = ref.watch(favoritesProvider.notifier).isInFavorites(animeId);
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
                                  ref.read(watchlistProvider.notifier).removeFromWatchlist(animeId);
                                } else {
                                  ref.read(watchlistProvider.notifier).addToWatchlist(animeId);
                                }
                              },
                              icon: Icon(
                                isInWatchlist ? Icons.bookmark : Icons.bookmark_border,
                              ),
                              label: Text(isInWatchlist ? 'In Watchlist' : 'Add to Watchlist'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (isInFavorites) {
                                  ref.read(favoritesProvider.notifier).removeFromFavorites(animeId);
                                } else {
                                  ref.read(favoritesProvider.notifier).addToFavorites(animeId);
                                }
                              },
                              icon: Icon(
                                isInFavorites ? Icons.favorite : Icons.favorite_border,
                              ),
                              label: Text(isInFavorites ? 'Favorited' : 'Add to Favorites'),
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
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
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
                        Text(
                          anime.description!,
                          style: TextStyle(color: Colors.grey[300]),
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
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final episode = episodes[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text('${episode.number}'),
                      ),
                      title: Text(episode.title ?? 'Episode ${episode.number}'),
                      trailing: const Icon(Icons.play_arrow),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VideoPlayerScreen(
                              episodeId: episode.id,
                              animeId: animeId,
                              animeTitle: anime.title,
                              animeImage: anime.image,
                              episodeNumber: episode.number,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  childCount: episodes.length,
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
}
