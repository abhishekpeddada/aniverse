import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/continue_watching_section.dart';
import 'widgets/recommendation_section.dart';
import '../profile/profile_screen.dart';
import '../auth/login_screen.dart';
import '../../providers/auth_provider.dart';
import '../../providers/local_settings_provider.dart';
import '../../providers/recommendation_provider.dart';
import '../../widgets/app_drawer.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const HomePage();
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  void _showSettingsDialog(BuildContext context, WidgetRef ref) {
    final localSettings = ref.read(localSettingsProvider);
    final allowAdult = localSettings['allowAdult'] as bool? ?? false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final currentSettings = ref.read(localSettingsProvider);
          final currentAllowAdult =
              currentSettings['allowAdult'] as bool? ?? false;

          return AlertDialog(
            title: const Text('Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Adult Content'),
                  subtitle: const Text('Show adult content in search results'),
                  value: currentAllowAdult,
                  onChanged: (value) async {
                    if (value) {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Enable Adult Content?'),
                          content: const Text(
                            'This will show adult content in search results. Are you sure?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Enable'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await ref
                            .read(localSettingsProvider.notifier)
                            .updateSetting('allowAdult', value);
                        setState(() {});
                      }
                    } else {
                      await ref
                          .read(localSettingsProvider.notifier)
                          .updateSetting('allowAdult', value);
                      setState(() {});
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final becauseYouWatched = ref.watch(becauseYouWatchedProvider);
    final trending = ref.watch(trendingAnimeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AniVerse'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menu',
          ),
        ),
        actions: [
          if (!kIsWeb &&
              (Platform.isLinux || Platform.isWindows || Platform.isMacOS))
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => _showSettingsDialog(context, ref),
              tooltip: 'Settings',
            ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              if (user == null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ProfileScreen()),
                );
              }
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ContinueWatchingSection(),
            const SizedBox(height: 16),
            recommendations.when(
              data: (animeList) => RecommendationSection(
                title: 'Recommended for You',
                animeList: animeList,
              ),
              loading: () => const RecommendationSection(
                title: 'Recommended for You',
                animeList: [],
                isLoading: true,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
            becauseYouWatched.when(
              data: (data) {
                final sourceAnime = data['sourceAnime'];
                final similar = data['recommendations'] as List;

                if (sourceAnime == null || similar.isEmpty) {
                  return const SizedBox.shrink();
                }

                return RecommendationSection(
                  title: 'Because You Watched ${sourceAnime.title}',
                  animeList: similar.cast(),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            trending.when(
              data: (animeList) => RecommendationSection(
                title: 'Trending Now',
                animeList: animeList,
              ),
              loading: () => const RecommendationSection(
                title: 'Trending Now',
                animeList: [],
                isLoading: true,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
