import 'package:flutter/material.dart';

class UploadProgressItem {
  final String name;
  final double progress;
  final bool complete;
  final bool paused;
  final String? error;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onAbort;

  const UploadProgressItem({
    required this.name,
    required this.progress,
    this.complete = false,
    this.paused = false,
    this.error,
    this.onPause,
    this.onResume,
    this.onAbort,
  });
}

class UploadProgressOverlay extends StatelessWidget {
  final List<UploadProgressItem> items;
  final String title;

  const UploadProgressOverlay({
    super.key,
    required this.items,
    this.title = 'Uploading files',
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = screenWidth > 444
        ? 420.0
        : (screenWidth - 24).clamp(220, 420).toDouble();

    return Container(
      width: panelWidth,
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(blurRadius: 10, spreadRadius: 1, color: Color(0x22000000)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (item.error != null)
                    Text(item.error!, style: const TextStyle(color: Colors.red))
                  else if (item.complete)
                    const Text('Done', style: TextStyle(color: Colors.green))
                  else ...[
                    if (item.paused)
                      const Text(
                        'Paused',
                        style: TextStyle(color: Colors.orange),
                      )
                    else
                      LinearProgressIndicator(value: item.progress),
                    if (item.onPause != null ||
                        item.onResume != null ||
                        item.onAbort != null)
                      Row(
                        children: [
                          if (item.paused && item.onResume != null)
                            TextButton.icon(
                              onPressed: item.onResume,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Continue'),
                            )
                          else if (!item.paused && item.onPause != null)
                            TextButton.icon(
                              onPressed: item.onPause,
                              icon: const Icon(Icons.pause),
                              label: const Text('Pause'),
                            ),
                          if (item.onAbort != null)
                            TextButton.icon(
                              onPressed: item.onAbort,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: const Text('Abort'),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
