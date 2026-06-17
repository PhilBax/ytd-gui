import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/download_provider.dart';

class FolderPickerRow extends ConsumerWidget {
  const FolderPickerRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return settingsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
      data: (settings) => Row(
        children: [
          const Icon(Icons.folder_open, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              settings.downloadDir,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: Theme.of(context).colorScheme.primary.withAlpha(128)),
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () async {
              final result = await FilePicker.platform.getDirectoryPath(
                dialogTitle: 'Choose download folder',
                initialDirectory: settings.downloadDir,
              );
              if (result != null) {
                ref.read(settingsProvider.notifier).setDownloadDir(result);
              }
            },
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Change'),
          ),
        ],
      ),
    );
  }
}
