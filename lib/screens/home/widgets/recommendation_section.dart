import 'package:flutter/material.dart';
import '../../../models/anime_model.dart';
import '../../details/anime_details_screen.dart';

class RecommendationSection extends StatelessWidget {
  final String title;
  final List<Anime> animeList;
  final bool isLoading;

  const RecommendationSection({
    super.key,
    required this.title,
    required this.animeList,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildLoadingState();
    }

    if (animeList.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        SizedBox(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            itemCount: animeList.length,
            itemBuilder: (context, index) {
              final anime = animeList[index];
              return _buildAnimeCard(context, anime);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAnimeCard(BuildContext context, Anime anime) {
    if (anime.image == null || anime.image!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 130,
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AnimeDetailsScreen(animeId: anime.id),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  anime.image!,
                  width: 130,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: 130,
                      color: Colors.grey[850],
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 130,
                      color: Colors.grey[850],
                      child: const Icon(Icons.broken_image,
                          color: Colors.grey, size: 40),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 6),

            // Title - ALWAYS SHOWN
            SizedBox(
              width: 130,
              child: Text(
                anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(
          height: 250,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
