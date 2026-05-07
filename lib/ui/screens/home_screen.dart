import 'package:flutter/material.dart';
import '../../../server/server.dart';
import '../../../core/session_store.dart';
import 'host/session_screen.dart';
import 'guest/discovery_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _startSession(BuildContext context) async {
    final server = OpenFoldrServer();
    try {
      await server.start();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start server: \$e')),
      );
      return;
    }

    // Restore last session's folders
    final savedRoots = await SessionStore.loadRoots();
    for (final root in savedRoots) {
      try {
        server.roots.register(root);
      } catch (_) {}
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SessionScreen(server: server)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/icons/icon.png',
                  width: 96,
                  height: 96,
                ),
                const SizedBox(height: 16),
                Text(
                  'OpenFoldr',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Local network file sharing',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: 56),
                FilledButton.icon(
                  icon: const Icon(Icons.folder_shared),
                  label: const Text('Start Share Session'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  onPressed: () => _startSession(context),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.wifi_find),
                  label: const Text('Join a Share'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DiscoveryScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
