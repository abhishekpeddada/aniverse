import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../providers/history_provider.dart';
import '../../details/anime_details_screen.dart';

class ContinueWatchingSection extends ConsumerWidget {
  const ContinueWatchingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final continueWatching = ref.watch(continueWatchingProvider);

    if (continueWatching.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            children: [
              SizedBox(height: 32),
              Icon(Icons.play_circle_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No anime in progress',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Start watching anime to see them here',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Continue Watching',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.55,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: continueWatching.length,
          itemBuilder: (context, index) {
            final history = continueWatching[index];
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AnimeDetailsScreen(
                      animeId: history.animeId,
                      continueEpisodeId: history.episodeId,
                    ),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail with progress indicator
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          CachedNetworkImage(
                            imageUrl: history.animeImage ?? '',
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[900],
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[900],
                              child: const Icon(Icons.movie, size: 32),
                            ),
                          ),
                          
                          // Episode badge
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'EP ${history.episodeNumber}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          
                          // Progress indicator at bottom
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(
                              value: history.progress,
                              backgroundColor: Colors.grey[800],
                              minHeight: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 6),
                  
                  // Title
                  Text(
                    history.animeTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
