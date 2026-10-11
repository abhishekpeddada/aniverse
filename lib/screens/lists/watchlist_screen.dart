import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/lists_provider.dart';
import '../../providers/anime_provider.dart';
import '../../models/anime_model.dart';
import '../search/widgets/anime_grid.dart';

class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlistIds = ref.watch(watchlistProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist'),
      ),
      body: watchlistIds.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Your watchlist is empty',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Add anime to your watchlist to watch later',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            )
          : AnimeGrid(
              // Each card fills in as its details load from the cache or API.
              animes: [
                for (final id in watchlistIds)
                  ref.watch(listAnimeProvider(id)).valueOrNull ??
                      Anime(id: id, title: 'Loading...'),
              ],
            ),
    );
  }
}
