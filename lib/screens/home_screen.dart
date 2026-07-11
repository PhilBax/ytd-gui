import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/download_item.dart';
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
          _ClearQueueButton(),
          _ClearButton(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const _SettingsDialog(),
            ),
          ),
          const SizedBox(width: 4),
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

class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog();

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  late TextEditingController _lufsController;
  late TextEditingController _ffmpegController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider).valueOrNull;
    _lufsController = TextEditingController(
      text: (settings?.normalizeLufs ?? -14.0).toStringAsFixed(1),
    );
    _ffmpegController = TextEditingController(
      text: settings?.ffmpegOverride ?? '',
    );
  }

  @override
  void dispose() {
    _lufsController.dispose();
    _ffmpegController.dispose();
    super.dispose();
  }

  Future<void> _browseFfmpeg() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe'],
      dialogTitle: 'Select ffmpeg.exe',
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      _ffmpegController.text = path;
      ref.read(settingsProvider.notifier).setFfmpegOverride(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final normalize = settings?.normalize ?? false;

    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Audio', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Normalize loudness'),
              subtitle: null,
              value: normalize,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setNormalize(v),
            ),
            AnimatedOpacity(
              opacity: normalize ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 150),
              child: Row(
                children: [
                  const Text('Target loudness:'),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _lufsController,
                      enabled: normalize,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^-?\d*\.?\d*')),
                      ],
                      decoration: const InputDecoration(
                        suffixText: ' LUFS',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null && parsed <= 0) {
                          ref
                              .read(settingsProvider.notifier)
                              .setNormalizeLufs(parsed);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Dependencies',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('ffmpeg path',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ffmpegController,
                    decoration: const InputDecoration(
                      hintText: 'Leave blank to use ffmpeg from PATH',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setFfmpegOverride(v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 20),
                  tooltip: 'Browse',
                  onPressed: _browseFfmpeg,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
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

class _ClearQueueButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(downloadsProvider);
    final hasQueued = items.any((i) => i.status == DownloadStatus.queued);
    if (!hasQueued) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => ref.read(downloadsProvider.notifier).clearQueued(),
      icon: const Icon(Icons.playlist_remove, size: 18),
      label: const Text('Clear queue'),
    );
  }
}
