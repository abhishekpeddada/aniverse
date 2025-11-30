import 'package:flutter/material.dart';

class QualitySelector extends StatelessWidget {
  final List<Map<String, dynamic>> sources;
  final int currentIndex;
  final Function(int) onQualitySelected;

  const QualitySelector({
    super.key,
    required this.sources,
    required this.currentIndex,
    required this.onQualitySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.high_quality, color: Colors.white),
                const SizedBox(width: 12),
                const Text(
                  'Select Quality',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1, color: Colors.grey),
          
          // Quality options
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sources.length,
              itemBuilder: (context, index) {
                final source = sources[index];
                final isSelected = index == currentIndex;
                final quality = source['quality'] as String;
                final sourceName = source['sourceName'] as String;
                final isM3U8 = source['isM3U8'] as bool;
                
                return ListTile(
                  leading: Icon(
                    isM3U8 ? Icons.stream : Icons.movie,
                    color: isSelected ? Colors.blue : Colors.grey,
                  ),
                  title: Text(
                    quality,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    sourceName,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.blue)
                      : null,
                  selected: isSelected,
                  selectedTileColor: Colors.blue.withOpacity(0.1),
                  onTap: () {
                    onQualitySelected(index);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static void show({
    required BuildContext context,
    required List<Map<String, dynamic>> sources,
    required int currentIndex,
    required Function(int) onQualitySelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => QualitySelector(
        sources: sources,
        currentIndex: currentIndex,
        onQualitySelected: onQualitySelected,
      ),
    );
  }
}
