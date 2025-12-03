  // Build Raiden anime details (simplified - direct to video)
  Widget _buildRaidenDetails(BuildContext context, Map<String, dynamic>? raidenData) {
    if (raidenData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Not Found')),
        body: const Center(child: Text('Raiden content not found in cache')),
      );
    }

    final title = raidenData['title'] as String? ?? 'Unknown';
    final thumbnail = raidenData['thumbnail'] as String?;
    final downloadUrl = raidenData['download_url'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (thumbnail != null)
              CachedNetworkImage(
                imageUrl: thumbnail,
                width: 200,
                height: 300,
                fit: BoxFit.cover,
              ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: downloadUrl != null
                  ? () {
                      // Direct video playback for Raiden
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(
                            episodeId: widget.animeId,
                            animeId: widget.animeId,
                            animeTitle: title,
                            animeImage: thumbnail,
                            episodeNumber: 1,
                          ),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play Video'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
