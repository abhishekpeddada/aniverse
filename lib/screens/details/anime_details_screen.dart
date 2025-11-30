import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/anime_provider.dart';
import '../../providers/lists_provider.dart';
import '../../providers/storage_provider.dart';
import '../../models/episode_model.dart';
import '../player/video_player_screen.dart';

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
                                  ref.read(watchlistProvider.notifier).removeFromWatchlist(widget.animeId);
                                } else {
                                  ref.read(watchlistProvider.notifier).addToWatchlist(widget.animeId);
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
                                  ref.read(favoritesProvider.notifier).removeFromFavorites(widget.animeId);
                                } else {
                                  ref.read(favoritesProvider.notifier).addToFavorites(widget.animeId);
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
                      return epNum.contains(_searchQuery) || epTitle.contains(_searchQuery);
                    }).toList();
                    
                    if (index >= filteredEpisodes.length) return null;
                    
                    final episode = filteredEpisodes[index];
                    final isNextToWatch = episode.id == widget.continueEpisodeId;
                    
                    return Container(
                      color: isNextToWatch ? Colors.red.withOpacity(0.15) : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isNextToWatch ? Colors.red : null,
                          foregroundColor: isNextToWatch ? Colors.white : null,
                          child: Text('${episode.number}'),
                        ),
                        title: Text(
                          episode.title ?? 'Episode ${episode.number}',
                          style: isNextToWatch 
                              ? const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)
                              : null,
                        ),
                        trailing: Icon(
                          Icons.play_arrow,
                          color: isNextToWatch ? Colors.red : null,
                        ),
                        onTap: () {
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
}
