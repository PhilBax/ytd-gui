import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../models/download_item.dart';
import '../providers/download_provider.dart';

const _mediaExtensions = [
  'mp3', 'm4a', 'wav', 'flac', 'ogg', 'opus', 'aac', 'wma',
  'mp4', 'mkv', 'mov', 'avi', 'webm', 'flv', 'wmv', 'm4v',
];

const _activeStatuses = {
  DownloadStatus.downloading,
  DownloadStatus.converting,
  DownloadStatus.normalizing,
};

class UrlInputBar extends ConsumerStatefulWidget {
  const UrlInputBar({super.key});

  @override
  ConsumerState<UrlInputBar> createState() => _UrlInputBarState();
}

class _UrlInputBarState extends ConsumerState<UrlInputBar> {
  final _controller = TextEditingController();
  bool _resolving = false;

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    setState(() => _resolving = true);
    _controller.clear();
    await ref.read(downloadsProvider.notifier).enqueue(url);
    if (mounted) setState(() => _resolving = false);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _controller.text = data!.text!;
    }
  }

  Future<void> _pickLocalFiles() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select audio or video files',
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _mediaExtensions,
    );
    final paths = result?.files
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    if (paths == null || paths.isEmpty) return;

    ref.read(downloadsProvider.notifier).enqueueLocalFiles(paths);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(downloadsProvider);
    final isActive = items.any((i) => _activeStatuses.contains(i.status));
    final hasQueued = items.any((i) => i.status == DownloadStatus.queued);

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: !_resolving,
            decoration: InputDecoration(
              hintText: 'Enter YouTube link or select local files…',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste),
                tooltip: 'Paste from clipboard',
                onPressed: _resolving ? null : _paste,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _resolving ? null : _pickLocalFiles,
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('Browse'),
        ),
        const SizedBox(width: 12),
        _buildActionButton(isActive, hasQueued),
      ],
    );
  }

  Widget _buildActionButton(bool isActive, bool hasQueued) {
    if (isActive) {
      return Tooltip(
        message: 'Stop',
        child: SizedBox(
          width: 48,
          height: 48,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => ref.read(downloadsProvider.notifier).stop(),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_resolving) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (hasQueued) {
      return FilledButton.icon(
        onPressed: () => ref.read(downloadsProvider.notifier).resume(),
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text('Resume'),
      );
    }

    return FilledButton.icon(
      onPressed: _submit,
      icon: const Icon(Icons.download, size: 18),
      label: const Text('Download'),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
