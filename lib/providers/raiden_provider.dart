import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/raiden_api_service.dart';

/// Provider to store Raiden anime data for quick access
/// Maps anime ID to the full Raiden data including download_url
final raidenAnimeDataProvider = StateProvider<Map<String, Map<String, dynamic>>>((ref) => {});

/// Provider to get Raiden anime details by ID
final raidenAnimeDetailsProvider = Provider.family<Map<String, dynamic>?, String>((ref, animeId) {
  final data = ref.watch(raidenAnimeDataProvider);
  return data[animeId];
});

/// Provider to check if anime is from Raiden source
final isRaidenAnimeProvider = Provider.family<bool, String>((ref, animeId) {
  return animeId.startsWith('raiden_');
});
