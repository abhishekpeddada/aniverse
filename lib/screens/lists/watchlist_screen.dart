import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/lists_provider.dart';
import '../../providers/storage_provider.dart';
import '../../models/anime_model.dart';
import '../search/widgets/anime_grid.dart';

class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlistIds = ref.watch(watchlistProvider);
    final storageService = ref.watch(storageServiceProvider);

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
          : FutureBuilder<List<Anime?>>(
              future: Future.wait<Anime?>(
                watchlistIds.map((id) async {
                  final cached = storageService.getCachedAnime(id);
                  if (cached != null) return cached;
                  // Return a placeholder if not cached
                  return Anime(id: id, title: 'Loading...');
                }).toList(),
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final animes = snapshot.data?.whereType<Anime>().toList() ?? [];
                return AnimeGrid(animes: animes);
              },
            ),
    );
  }
}
