import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/download_provider.dart';
import '../../models/download_model.dart';
import '../player/video_player_screen.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloadsAsync = ref.watch(downloadsProvider);
    final storageUsageAsync = ref.watch(storageUsageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
            Tab(text: 'Failed'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _showClearDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (storageUsageAsync.hasValue && storageUsageAsync.value! > 0)
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  const Icon(Icons.storage, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Storage Used: ${_formatBytes(storageUsageAsync.value!)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          Expanded(
            child: downloadsAsync.when(
              data: (downloads) {
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildActiveDownloads(downloads),
                    _buildCompletedDownloads(downloads),
                    _buildFailedDownloads(downloads),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDownloads(List<Download> downloads) {
    final active = downloads
        .where((d) =>
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.queued ||
            d.status == DownloadStatus.paused)
        .toList();

    if (active.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No active downloads'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: active.length,
      itemBuilder: (context, index) => _buildDownloadCard(active[index]),
    );
  }

  Widget _buildCompletedDownloads(List<Download> downloads) {
    final completed =
        downloads.where((d) => d.status == DownloadStatus.completed).toList();

    if (completed.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No completed downloads'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: completed.length,
      itemBuilder: (context, index) => _buildDownloadCard(completed[index]),
    );
  }

  Widget _buildFailedDownloads(List<Download> downloads) {
    final failed =
        downloads.where((d) => d.status == DownloadStatus.failed).toList();

    if (failed.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text('All downloads successful!'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: failed.length,
      itemBuilder: (context, index) => _buildDownloadCard(failed[index]),
    );
  }

  Widget _buildDownloadCard(Download download) {
    final canPlay = download.status == DownloadStatus.completed &&
        download.filePath != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: canPlay
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(
                      episodeId: download.episodeId,
                      animeId: download.animeId,
                      animeTitle: download.animeTitle,
                      animeImage: download.animeImage,
                      episodeNumber: download.episodeNumber,
                      isOffline: true,
                      offlineFilePath: download.filePath,
                    ),
                  ),
                );
              }
            : null,
        child: Column(
          children: [
            ListTile(
              leading: download.animeImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: download.animeImage!,
                        width: 50,
                        height: 70,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Container(
                      width: 50,
                      height: 70,
                      color: Colors.grey[800],
                      child: const Icon(Icons.movie),
                    ),
              title: Text(
                download.animeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Episode ${download.episodeNumber}'),
                  Text('${download.quality} - ${download.formattedSize}'),
                ],
              ),
              trailing: _buildActionButtons(download),
            ),
            if (download.status == DownloadStatus.downloading)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    LinearProgressIndicator(value: download.progress),
                    const SizedBox(height: 4),
                    Text(
                      download.progressPercentage,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(Download download) {
    final downloadService = ref.read(downloadServiceProvider);

    switch (download.status) {
      case DownloadStatus.downloading:
        return IconButton(
          icon: const Icon(Icons.pause),
          onPressed: () => downloadService.pauseDownload(download.id),
        );
      case DownloadStatus.paused:
        return IconButton(
          icon: const Icon(Icons.cancel),
          onPressed: () => downloadService.cancelDownload(download.id),
        );
      case DownloadStatus.completed:
        return IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => downloadService.deleteDownload(download.id),
        );
      case DownloadStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => downloadService.deleteDownload(download.id),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _showClearDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Downloads'),
        content: const Text(
          'This will delete all downloaded episodes. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(downloadServiceProvider).clearAllDownloads();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All downloads cleared')),
        );
      }
    }
  }
}
