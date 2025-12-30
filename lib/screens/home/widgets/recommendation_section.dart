import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
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
            childAspectRatio: 0.50,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: animeList.length,
          itemBuilder: (context, index) {
            final anime = animeList[index];
            return _buildAnimeCard(context, anime);
          },
        ),
      ],
    );
  }

  Widget _buildAnimeCard(BuildContext context, Anime anime) {
    if (anime.image == null || anime.image!.isEmpty) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
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
              child: CachedNetworkImage(
                imageUrl: anime.image!,
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
            ),
          ),
          
          const SizedBox(height: 6),
          
          // Title
          Text(
            anime.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.2,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(
          height: 200,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ],
    );
  }
}
