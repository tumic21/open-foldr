import 'package:flutter/material.dart';

class UploadProgressItem {
  final String name;
  final double progress;
  final bool complete;
  final String? error;

  const UploadProgressItem({
    required this.name,
    required this.progress,
    this.complete = false,
    this.error,
  });
}

class UploadProgressOverlay extends StatelessWidget {
  final List<UploadProgressItem> items;

  const UploadProgressOverlay({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              spreadRadius: 1,
              color: Color(0x22000000),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Uploading files',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (item.error != null)
                      Text(
                        item.error!,
                        style: const TextStyle(color: Colors.red),
                      )
                    else if (item.complete)
                      const Text(
                        'Done',
                        style: TextStyle(color: Colors.green),
                      )
                    else
                      LinearProgressIndicator(value: item.progress),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
