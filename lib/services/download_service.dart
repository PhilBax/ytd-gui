import 'dart:io';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/download_item.dart';
import 'update_service.dart';

final downloadServiceProvider = Provider((ref) {
  final updateService = ref.read(updateServiceProvider);
  return DownloadService(updateService);
});

class DownloadService {
  final UpdateService _updateService;
  DownloadService(this._updateService);

  // Parses a yt-dlp progress line like: [download]  45.3% of 12.34MiB at 1.23MiB/s ETA 00:10
  static final _progressRe = RegExp(r'\[download\]\s+([\d.]+)%');

  Future<void> downloadItem({
    required DownloadItem item,
    required String outputDir,
    required void Function(DownloadItem updated) onUpdate,
  }) async {
    final ytdlp = _updateService.ytdlpPath;
    final ffmpeg = _updateService.ffmpegPath;

    if (!File(ytdlp).existsSync()) {
      _fail(item, 'yt-dlp not found. Please restart the app to download it.',
          onUpdate);
      return;
    }

    final safeTitle = item.title.isNotEmpty ? item.title : item.id;
    final outputTemplate = p.join(outputDir, '%(title)s.%(ext)s');

    final args = [
      '--no-playlist',
      '-x',
      '--audio-format', 'm4a',
      '--audio-quality', '0',
      '--ffmpeg-location', p.dirname(ffmpeg),
      '--output', outputTemplate,
      '--newline',
      '--progress',
      item.url,
    ];

    item.logBuffer.writeln('> $ytdlp ${args.join(' ')}\n');
    onUpdate(item.copyWith(status: DownloadStatus.downloading, progress: 0.0));

    try {
      final process = await Process.start(ytdlp, args);

      process.stdout
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
        item.logBuffer.write(chunk);
        for (final line in chunk.split('\n')) {
          final m = _progressRe.firstMatch(line);
          if (m != null) {
            final pct = double.tryParse(m.group(1)!) ?? 0;
            onUpdate(item.copyWith(
              status: DownloadStatus.downloading,
              progress: pct / 100.0,
            ));
          }
          if (line.contains('[ExtractAudio]') || line.contains('[Merger]')) {
            onUpdate(item.copyWith(status: DownloadStatus.converting));
          }
          // Try to extract the actual output filename
          if (line.startsWith('[ExtractAudio] Destination:')) {
            final path = line.replaceFirst('[ExtractAudio] Destination:', '').trim();
            item = item.copyWith(outputPath: path);
          }
        }
      });

      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen((chunk) => item.logBuffer.write(chunk));

      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        // If we didn't catch the exact path, find the newest m4a in outputDir
        final path = item.outputPath ?? _findLatestM4a(outputDir, safeTitle);
        onUpdate(item.copyWith(
          status: DownloadStatus.done,
          progress: 1.0,
          outputPath: path,
        ));
      } else {
        _fail(item, 'yt-dlp exited with code $exitCode', onUpdate);
      }
    } catch (e) {
      _fail(item, e.toString(), onUpdate);
    }
  }

  void _fail(
      DownloadItem item, String msg, void Function(DownloadItem) onUpdate) {
    item.logBuffer.writeln('\nERROR: $msg');
    onUpdate(item.copyWith(
        status: DownloadStatus.failed, errorMessage: msg));
  }

  String? _findLatestM4a(String dir, String hint) {
    try {
      final files = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.m4a'))
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files.isEmpty ? null : files.first.path;
    } catch (_) {
      return null;
    }
  }
}
