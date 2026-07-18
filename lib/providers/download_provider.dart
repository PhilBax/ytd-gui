import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/download_item.dart';
import '../services/download_service.dart';
import '../services/update_service.dart';

// ----- Settings -----

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class AppSettings {
  final String downloadDir;
  final bool normalize;
  final double normalizeLufs;
  final String ffmpegOverride; // empty = use PATH

  AppSettings({
    required this.downloadDir,
    this.normalize = false,
    this.normalizeLufs = -14.0,
    this.ffmpegOverride = '',
  });

  AppSettings copyWith({
    String? downloadDir,
    bool? normalize,
    double? normalizeLufs,
    String? ffmpegOverride,
  }) =>
      AppSettings(
        downloadDir: downloadDir ?? this.downloadDir,
        normalize: normalize ?? this.normalize,
        normalizeLufs: normalizeLufs ?? this.normalizeLufs,
        ffmpegOverride: ffmpegOverride ?? this.ffmpegOverride,
      );
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _keyDir = 'download_dir';
  static const _keyNormalize = 'normalize';
  static const _keyNormalizeLufs = 'normalize_lufs';
  static const _keyFfmpegOverride = 'ffmpeg_override';

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyDir);
    final dir = saved ?? (await getDownloadsDirectory())?.path ?? '.';
    return AppSettings(
      downloadDir: dir,
      normalize: prefs.getBool(_keyNormalize) ?? false,
      normalizeLufs: prefs.getDouble(_keyNormalizeLufs) ?? -14.0,
      ffmpegOverride: prefs.getString(_keyFfmpegOverride) ?? '',
    );
  }

  Future<void> setDownloadDir(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDir, path);
    state = AsyncData(state.value!.copyWith(downloadDir: path));
  }

  Future<void> setNormalize(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNormalize, value);
    state = AsyncData(state.value!.copyWith(normalize: value));
  }

  Future<void> setNormalizeLufs(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyNormalizeLufs, value);
    state = AsyncData(state.value!.copyWith(normalizeLufs: value));
  }

  Future<void> setFfmpegOverride(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFfmpegOverride, value);
    state = AsyncData(state.value!.copyWith(ffmpegOverride: value));
  }
}

// ----- Downloads -----

final downloadsProvider =
    NotifierProvider<DownloadsNotifier, List<DownloadItem>>(
        DownloadsNotifier.new);

class DownloadsNotifier extends Notifier<List<DownloadItem>> {
  static const _maxConsecutiveFailures = 3;

  bool _draining = false;
  bool _stopRequested = false;
  CancelToken? _activeCancelToken;

  @override
  List<DownloadItem> build() => [];

  void _update(DownloadItem updated) {
    state = [
      for (final item in state)
        if (item.id == updated.id) updated else item,
    ];
  }

  Future<void> enqueue(String url) async {
    final updateService = ref.read(updateServiceProvider);

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
    _startDrain();
  }

  void enqueueLocalFiles(List<String> paths) {
    final newItems = paths.map((path) {
      return DownloadItem(
        id: '${DateTime.now().microsecondsSinceEpoch}_${path.hashCode}',
        url: path,
        title: p.basenameWithoutExtension(path),
        isLocal: true,
      );
    }).toList();

    state = [...state, ...newItems];
    _startDrain();
  }

  /// Kicks off the background drain loop if one isn't already running.
  /// Safe to call any time — new items just get picked up by the loop
  /// that's already in flight.
  void _startDrain() {
    if (_draining) return;
    _draining = true;
    _drainLoop();
  }

  Future<void> _drainLoop() async {
    final downloadService = ref.read(downloadServiceProvider);
    int consecutiveFailures = 0;

    while (true) {
      final next = _nextQueued();
      if (next == null) break;

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

      final settings = ref.read(settingsProvider).valueOrNull;
      final outputDir = settings?.downloadDir ?? '.';
      final cancelToken = CancelToken();
      _activeCancelToken = cancelToken;

      await downloadService.downloadItem(
        item: next,
        outputDir: outputDir,
        normalize: settings?.normalize ?? false,
        normalizeLufs: settings?.normalizeLufs ?? -14.0,
        ffmpegOverride: settings?.ffmpegOverride ?? '',
        cancelToken: cancelToken,
        onUpdate: _update,
      );

      _activeCancelToken = null;

      // Stop leaves the rest of the queue untouched, ready for Resume.
      if (_stopRequested) {
        _stopRequested = false;
        break;
      }

      final finished = state.firstWhere((i) => i.id == next.id, orElse: () => next);
      if (finished.status == DownloadStatus.failed) {
        consecutiveFailures++;
      } else {
        consecutiveFailures = 0;
      }
    }

    _draining = false;
  }

  DownloadItem? _nextQueued() {
    for (final item in state) {
      if (item.status == DownloadStatus.queued) return item;
    }
    return null;
  }

  /// Cancels whatever is currently downloading/converting/normalizing. The
  /// active item is marked failed with "Canceled"; remaining queued items
  /// are left alone so Resume can pick them back up.
  void stop() {
    if (_activeCancelToken == null) return;
    _stopRequested = true;
    _activeCancelToken!.cancel();
  }

  /// Resumes processing of whatever is still queued. Does not retry
  /// failed/canceled items — only items still in the "queued" state.
  void resume() => _startDrain();

  void retry(String itemId) {
    final item = state.firstWhere((i) => i.id == itemId);
    _update(item.copyWith(
      status: DownloadStatus.queued,
      progress: 0,
      errorMessage: null,
      retryCount: item.retryCount + 1,
    ));
    _startDrain();
  }

  void clear() {
    state = state.where((i) => !i.isTerminal).toList();
  }

  /// Removes items that haven't started processing yet. Leaves the item
  /// currently downloading/converting/normalizing (if any) alone.
  void clearQueued() {
    state = state.where((i) => i.status != DownloadStatus.queued).toList();
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
