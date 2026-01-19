import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final authService = ref.watch(authServiceProvider);

    if (user == null) {
      return const LoginScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (user.photoURL != null)
                CircleAvatar(
                  radius: 50,
                  backgroundImage: NetworkImage(user.photoURL!),
                )
              else
                const CircleAvatar(
                  radius: 50,
                  child: Icon(Icons.person, size: 50),
                ),
              const SizedBox(height: 24),
              Text(
                user.displayName ?? 'User',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                user.email ?? '',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              const SizedBox(height: 48),

              //Adult Content Toggle
              Consumer(
                builder: (context, ref, _) {
                  final prefs = ref.watch(userPreferencesProvider);
                  final user = ref.watch(currentUserProvider);
                  final firestoreService = ref.watch(firestoreServiceProvider);

                  if (user == null) return const SizedBox.shrink();

                  return prefs.when(
                    data: (data) {
                      final allowAdult = data['allowAdult'] as bool? ?? false;

                      return Card(
                        child: SwitchListTile(
                          title: const Text('Adult Content'),
                          subtitle: const Text(
                              'Enable adult content from multiple sources'),
                          value: allowAdult,
                          onChanged: (value) async {
                            if (value) {
                              // Show confirmation dialog when enabling
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Enable Adult Content?'),
                                  content: const Text(
                                    'This will show adult content in search results and latest releases from multiple sources.\\n\\nYou can disable this at any time.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Enable'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true) {
                                await firestoreService.updateUserPreferences(
                                    user.uid, {'allowAdult': true});
                              }
                            } else {
                              // Disable without confirmation
                              await firestoreService.updateUserPreferences(
                                  user.uid, {'allowAdult': false});
                            }
                          },
                        ),
                      );
                    },
                    loading: () => const Card(
                      child: ListTile(
                        title: Text('Adult Content'),
                        trailing: CircularProgressIndicator(),
                      ),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),

              Card(
                child: Consumer(
                  builder: (context, ref, _) {
                    final prefs = ref.watch(userPreferencesProvider);
                    final user = ref.watch(currentUserProvider);
                    final firestoreService =
                        ref.watch(firestoreServiceProvider);

                    if (user == null) return const SizedBox.shrink();

                    return prefs.when(
                      data: (data) {
                        final autoRotateEnabled =
                            data['autoRotateEnabled'] as bool? ?? true;

                        return SwitchListTile(
                          title: const Text('Auto-Rotate Video'),
                          subtitle: const Text(
                              'Automatically rotate video based on device orientation'),
                          value: autoRotateEnabled,
                          onChanged: (value) async {
                            await firestoreService.updateUserPreferences(
                                user.uid, {'autoRotateEnabled': value});
                          },
                        );
                      },
                      loading: () => const ListTile(
                        title: Text('Auto-Rotate Video'),
                        trailing: CircularProgressIndicator(),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  },
                ),
              ),



              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await authService.signOut();
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.2),
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
