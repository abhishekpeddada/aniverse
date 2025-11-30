import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/lists_provider.dart';
import '../../providers/storage_provider.dart';
import '../../models/anime_model.dart';
import '../search/widgets/anime_grid.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesIds = ref.watch(favoritesProvider);
    final storageService = ref.watch(storageServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
      ),
      body: favoritesIds.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No favorites yet',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Mark your favorite anime here',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            )
          : FutureBuilder<List<Anime?>>(
              future: Future.wait<Anime?>(
                favoritesIds.map((id) async {
                  final cached = storageService.getCachedAnime(id);
                  if (cached != null) return cached;
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
