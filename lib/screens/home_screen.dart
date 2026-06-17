import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/download_provider.dart';
import '../widgets/url_input_bar.dart';
import '../widgets/folder_picker_row.dart';
import '../widgets/download_list.dart';
import '../widgets/dependency_banner.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.play_circle_fill,
                color: Theme.of(context).colorScheme.primary, size: 28),
            const SizedBox(width: 10),
            const Text('YTD GUI'),
          ],
        ),
        actions: [
          _ClearButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: const Column(
        children: [
          DependencyBanner(),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: FolderPickerRow(),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: UrlInputBar(),
          ),
          Expanded(child: DownloadList()),
        ],
      ),
    );
  }
}

class _ClearButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(downloadsProvider);
    final hasFinished = items.any((i) => i.isTerminal);
    if (!hasFinished) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => ref.read(downloadsProvider.notifier).clear(),
      icon: const Icon(Icons.clear_all, size: 18),
      label: const Text('Clear finished'),
    );
  }
}
