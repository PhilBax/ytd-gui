import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import '../models/download_item.dart';
import '../providers/download_provider.dart';
import 'log_viewer_dialog.dart';

class DownloadItemTile extends ConsumerWidget {
  final String itemId;
  const DownloadItemTile({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(downloadsProvider);
    final item = items.firstWhere(
      (i) => i.id == itemId,
      orElse: () => DownloadItem(id: itemId, url: ''),
    );

    final color = _statusColor(context, item.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusIcon(status: item.status),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title.isNotEmpty ? item.title : item.url,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.status == DownloadStatus.failed &&
                          item.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            item.errorMessage!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _ActionButtons(item: item),
              ],
            ),
            if (item.status == DownloadStatus.downloading ||
                item.status == DownloadStatus.converting) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.status == DownloadStatus.converting
                      ? null
                      : item.progress,
                  backgroundColor:
                      Theme.of(context).colorScheme.surface.withAlpha(100),
                  color: color,
                  minHeight: 4,
                ),
              ),
              if (item.status == DownloadStatus.downloading)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${(item.progress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ),
              if (item.status == DownloadStatus.converting)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Converting to M4A…',
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(BuildContext context, DownloadStatus status) {
    switch (status) {
      case DownloadStatus.done:
        return Colors.green;
      case DownloadStatus.failed:
        return Theme.of(context).colorScheme.error;
      case DownloadStatus.downloading:
      case DownloadStatus.converting:
        return Theme.of(context).colorScheme.primary;
      case DownloadStatus.queued:
        return const Color(0xFF757575);
    }
  }
}

class _StatusIcon extends StatelessWidget {
  final DownloadStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case DownloadStatus.queued:
        return const Icon(Icons.schedule, size: 20, color: Color(0xFF757575));
      case DownloadStatus.downloading:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      case DownloadStatus.converting:
        return Icon(Icons.sync,
            size: 20, color: Theme.of(context).colorScheme.primary);
      case DownloadStatus.done:
        return const Icon(Icons.check_circle, size: 20, color: Colors.green);
      case DownloadStatus.failed:
        return Icon(Icons.error_outline,
            size: 20, color: Theme.of(context).colorScheme.error);
    }
  }
}

class _ActionButtons extends ConsumerWidget {
  final DownloadItem item;
  const _ActionButtons({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.status == DownloadStatus.done && item.outputPath != null)
          IconButton(
            icon: const Icon(Icons.folder_open, size: 18),
            tooltip: 'Show in folder',
            onPressed: () => _openFolder(item.outputPath!),
          ),
        if (item.status == DownloadStatus.failed)
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Retry',
            onPressed: () =>
                ref.read(downloadsProvider.notifier).retry(item.id),
          ),
        IconButton(
          icon: const Icon(Icons.open_in_browser, size: 18),
          tooltip: 'Open in browser',
          onPressed: () => launchUrl(Uri.parse(item.url),
              mode: LaunchMode.externalApplication),
        ),
        IconButton(
          icon: const Icon(Icons.terminal, size: 18),
          tooltip: 'View log',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => LogViewerDialog(item: item),
          ),
        ),
      ],
    );
  }

  void _openFolder(String filePath) {
    final dir = p.dirname(filePath);
    if (Platform.isWindows) {
      Process.run('explorer', ['/select,', filePath]);
    } else {
      launchUrl(Uri.directory(dir));
    }
  }
}
