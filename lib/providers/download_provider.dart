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

    // Resolve entries (url + title) for playlist or single video
    final entries = await _resolveEntries(url, updateService.ytdlpPath);

    final newItems = entries.map((e) {
      return DownloadItem(
        id: '${DateTime.now().microsecondsSinceEpoch}_${e.url.hashCode}',
        url: e.url,
        title: e.title,
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

  /// Resolves a URL into one or more (url, title) pairs.
  /// For playlists, expands every entry. For single videos, fetches the title.
  Future<List<({String url, String title})>> _resolveEntries(
      String url, String ytdlpExe) async {
    final isPlaylist =
        url.contains('playlist') || url.contains('list=');

    if (isPlaylist) {
      try {
        // Print "title<TAB>url" for every entry in the playlist
        final result = await Process.run(ytdlpExe, [
          '--flat-playlist',
          '--print', '%(title)s\t%(url)s',
          '--no-warnings',
          url,
        ]);
        final lines = (result.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty);
        final entries = <({String url, String title})>[];
        for (final line in lines) {
          final tab = line.indexOf('\t');
          if (tab == -1) continue;
          final title = line.substring(0, tab).trim();
          final entryUrl = line.substring(tab + 1).trim();
          if (entryUrl.startsWith('http')) {
            entries.add((url: entryUrl, title: title));
          }
        }
        if (entries.isNotEmpty) return entries;
      } catch (_) {/* fall through */}
      return [(url: url, title: 'Playlist')];
    }

    // Single video — fetch the title quickly
    try {
      final result = await Process.run(ytdlpExe, [
        '--print', 'title',
        '--no-warnings',
        '--no-download',
        url,
      ]);
      final title = (result.stdout as String).trim();
      if (title.isNotEmpty) {
        return [(url: url, title: title)];
      }
    } catch (_) {/* fall through */}

    // Fallback: use the video ID as a temporary placeholder
    final fallback =
        Uri.parse(url).queryParameters['v'] ?? url;
    return [(url: url, title: fallback)];
  }
}
