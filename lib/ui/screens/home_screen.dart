import 'package:flutter/material.dart';
import '../../../app.dart';
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
    final appState = OpenFoldrApp.maybeOf(context);
    final themeMode = appState?.themeMode ?? ThemeMode.system;
    final subtitleColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<ThemeMode>(
                    tooltip: 'Theme: ${_themeLabel(themeMode)}',
                    icon: const Icon(Icons.brightness_6),
                    onSelected: appState?.setThemeMode,
                    itemBuilder: (context) => [
                      PopupMenuItem<ThemeMode>(
                        value: ThemeMode.system,
                        child: Row(
                          children: [
                            Icon(
                              ThemeMode.system == themeMode
                                  ? Icons.radio_button_checked
                                  : Icons.brightness_auto,
                            ),
                            const SizedBox(width: 12),
                            const Text('Auto (System)'),
                          ],
                        ),
                      ),
                      PopupMenuItem<ThemeMode>(
                        value: ThemeMode.light,
                        child: Row(
                          children: [
                            Icon(
                              ThemeMode.light == themeMode
                                  ? Icons.radio_button_checked
                                  : Icons.light_mode,
                            ),
                            const SizedBox(width: 12),
                            const Text('Light'),
                          ],
                        ),
                      ),
                      PopupMenuItem<ThemeMode>(
                        value: ThemeMode.dark,
                        child: Row(
                          children: [
                            Icon(
                              ThemeMode.dark == themeMode
                                  ? Icons.radio_button_checked
                                  : Icons.dark_mode,
                            ),
                            const SizedBox(width: 12),
                            const Text('Dark'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
                        color: subtitleColor,
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

  static String _themeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };
  }
}
