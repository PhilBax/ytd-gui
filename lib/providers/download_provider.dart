import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_item.dart';
import '../services/download_service.dart';
import '../services/update_service.dart';

// ----- Settings -----

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class AppSettings {
  final String downloadDir;
  AppSettings({required this.downloadDir});
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _keyDir = 'download_dir';

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyDir);
    if (saved != null) return AppSettings(downloadDir: saved);
    final dl = await getDownloadsDirectory();
    return AppSettings(downloadDir: dl?.path ?? '.');
  }

  Future<void> setDownloadDir(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDir, path);
    state = AsyncData(AppSettings(downloadDir: path));
  }
}

// ----- Downloads -----

final downloadsProvider =
    NotifierProvider<DownloadsNotifier, List<DownloadItem>>(
        DownloadsNotifier.new);

class DownloadsNotifier extends Notifier<List<DownloadItem>> {
  static const _maxConsecutiveFailures = 3;

  @override
  List<DownloadItem> build() => [];

  void _update(DownloadItem updated) {
    state = [
      for (final item in state)
        if (item.id == updated.id) updated else item,
    ];
  }

  Future<void> enqueue(String url) async {
    final downloadService = ref.read(downloadServiceProvider);
    final updateService = ref.read(updateServiceProvider);
    final settingsAsync = ref.read(settingsProvider);
    final settings = settingsAsync.valueOrNull;
    final outputDir = settings?.downloadDir ?? '.';

    // Resolve playlist vs single
    final urls = await _resolveUrls(url, updateService.ytdlpPath);

    final newItems = urls.map((u) {
      return DownloadItem(
        id: '${DateTime.now().microsecondsSinceEpoch}_${u.hashCode}',
        url: u,
        title: _guessTitle(u),
      );
    }).toList();

    state = [...state, ...newItems];

    int consecutiveFailures = 0;

    for (final item in newItems) {
      if (consecutiveFailures >= _maxConsecutiveFailures) {
        // Mark remaining queued items as failed
        for (final remaining in state
            .where((i) => i.status == DownloadStatus.queued)) {
          _update(remaining.copyWith(
            status: DownloadStatus.failed,
            errorMessage: 'Stopped after $_maxConsecutiveFailures consecutive failures.',
          ));
        }
        break;
      }

      final current =
          state.firstWhere((i) => i.id == item.id, orElse: () => item);
      if (current.status != DownloadStatus.queued) continue;

      await downloadService.downloadItem(
        item: current,
        outputDir: outputDir,
        onUpdate: (updated) {
          _update(updated);
        },
      );

      final finished = state.firstWhere((i) => i.id == item.id);
      if (finished.status == DownloadStatus.failed) {
        consecutiveFailures++;
      } else {
        consecutiveFailures = 0;
      }
    }
  }

  Future<void> retry(String itemId) async {
    final item = state.firstWhere((i) => i.id == itemId);
    final downloadService = ref.read(downloadServiceProvider);
    final settings = ref.read(settingsProvider).valueOrNull;
    final outputDir = settings?.downloadDir ?? '.';

    _update(item.copyWith(
      status: DownloadStatus.queued,
      progress: 0,
      errorMessage: null,
      retryCount: item.retryCount + 1,
    ));

    final updated = state.firstWhere((i) => i.id == itemId);
    await downloadService.downloadItem(
      item: updated,
      outputDir: outputDir,
      onUpdate: _update,
    );
  }

  void clear() {
    state = state.where((i) => !i.isTerminal).toList();
  }

  Future<List<String>> _resolveUrls(String url, String ytdlpExe) async {
    // Check if it looks like a playlist URL
    if (!url.contains('playlist') && !url.contains('list=')) {
      return [url];
    }
    try {
      final result = await Process.run(ytdlpExe, [
        '--flat-playlist',
        '--print', 'url',
        '--no-warnings',
        url,
      ]);
      final lines = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l.startsWith('http'))
          .toList();
      return lines.isEmpty ? [url] : lines;
    } catch (_) {
      return [url];
    }
  }

  String _guessTitle(String url) {
    // Will be overwritten once yt-dlp runs; just a placeholder
    return Uri.parse(url).queryParameters['v'] ?? url;
  }
}
