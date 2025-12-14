import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../screens/search/search_screen.dart';
import '../screens/latest/latest_releases_screen.dart';
import '../screens/downloads/downloads_screen.dart';
import '../screens/lists/watchlist_screen.dart';
import '../screens/lists/favorites_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/auth/login_screen.dart';
import 'dart:io';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final currentRoute = ModalRoute.of(context)?.settings.name ?? '/';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildDrawerHeader(context, user),
          _buildDrawerItem(
            context,
            icon: Icons.home,
            title: 'Home',
            route: '/',
            currentRoute: currentRoute,
            onTap: () {
              Navigator.pop(context);
              if (currentRoute != '/') {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
          ),
          _buildDrawerItem(
            context,
            icon: Icons.search,
            title: 'Search',
            route: '/search',
            currentRoute: currentRoute,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchScreen()),
              );
            },
          ),
          _buildDrawerItem(
            context,
            icon: Icons.new_releases,
            title: 'Latest Releases',
            route: '/latest',
            currentRoute: currentRoute,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const LatestReleasesScreen()),
              );
            },
          ),
          _buildDrawerItem(
            context,
            icon: Icons.download,
            title: 'Downloads',
            route: '/downloads',
            currentRoute: currentRoute,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const DownloadsScreen()),
              );
            },
          ),
          _buildDrawerItem(
            context,
            icon: Icons.bookmark,
            title: 'Watchlist',
            route: '/watchlist',
            currentRoute: currentRoute,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const WatchlistScreen()),
              );
            },
          ),
          _buildDrawerItem(
            context,
            icon: Icons.favorite,
            title: 'Favorites',
            route: '/favorites',
            currentRoute: currentRoute,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const FavoritesScreen()),
              );
            },
          ),
          const Divider(),
          _buildDrawerItem(
            context,
            icon: Icons.person,
            title: user == null ? 'Login' : 'Profile',
            route: '/profile',
            currentRoute: currentRoute,
            onTap: () {
              Navigator.pop(context);
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
    );
  }

  Widget _buildDrawerHeader(BuildContext context, user) {
    return UserAccountsDrawerHeader(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      accountName: Text(
        user?.displayName ?? 'Guest User',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
      accountEmail: Text(
        user?.email ?? 'Not logged in',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      currentAccountPicture: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        backgroundImage:
            user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
        child: user?.photoURL == null
            ? Text(
                user?.displayName?.substring(0, 1).toUpperCase() ?? 'G',
                style:
                    const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              )
            : null,
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
    required String currentRoute,
    required VoidCallback onTap,
  }) {
    final isActive = currentRoute == route;

    return ListTile(
      leading: Icon(
        icon,
        color: isActive ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      selected: isActive,
      selectedTileColor:
          Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      onTap: onTap,
    );
  }
}
