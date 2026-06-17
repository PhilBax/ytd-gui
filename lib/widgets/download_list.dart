import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/download_provider.dart';
import 'download_item_tile.dart';

class DownloadList extends ConsumerWidget {
  const DownloadList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(downloadsProvider);

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note,
                size: 64,
                color: Theme.of(context).colorScheme.primary.withAlpha(77)),
            const SizedBox(height: 16),
            Text(
              'Paste a YouTube URL above to start downloading',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF757575)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: items.length,
      separatorBuilder: (context, idx) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[items.length - 1 - index]; // newest first
        return DownloadItemTile(itemId: item.id);
      },
    );
  }
}
