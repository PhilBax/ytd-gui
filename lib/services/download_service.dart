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

  static final _progressRe = RegExp(r'\[download\]\s+([\d.]+)%');
  static final _destinationRe = RegExp(r'\[download\] Destination: (.+)');
  // Captures the JSON block loudnorm prints after analysis
  static final _loudnormJsonRe = RegExp(r'\{[\s\S]+?\}', multiLine: true);

  Future<void> downloadItem({
    required DownloadItem item,
    required String outputDir,
    required void Function(DownloadItem updated) onUpdate,
    bool normalize = false,
    double normalizeLufs = -14.0,
    String ffmpegOverride = '',
  }) async {
    final ytdlp = _updateService.ytdlpPath;
    // Use the user-specified path if set, otherwise rely on PATH
    final ffmpeg = ffmpegOverride.isNotEmpty ? ffmpegOverride : 'ffmpeg';

    if (!File(ytdlp).existsSync()) {
      _fail(item, 'yt-dlp not found. Please restart the app to download it.', onUpdate);
      return;
    }

    // Download best audio in native format — we handle conversion ourselves
    final outputTemplate = p.join(outputDir, '%(title)s.%(ext)s');
    final args = [
      '--no-playlist',
      '-f', 'bestaudio',
      if (ffmpegOverride.isNotEmpty) ...['--ffmpeg-location', p.dirname(ffmpeg)],
      '--output', outputTemplate,
      '--newline',
      '--progress',
      item.url,
    ];

    item.logBuffer.writeln('> $ytdlp ${args.join(' ')}\n');
    onUpdate(item.copyWith(status: DownloadStatus.downloading, progress: 0.0));

    String? downloadedPath;

    try {
      final process = await Process.start(ytdlp, args);

      process.stdout.transform(const SystemEncoding().decoder).listen((chunk) {
        item.logBuffer.write(chunk);
        for (final line in chunk.split('\n')) {
          final progress = _progressRe.firstMatch(line);
          if (progress != null) {
            final pct = double.tryParse(progress.group(1)!) ?? 0;
            onUpdate(item.copyWith(
              status: DownloadStatus.downloading,
              progress: pct / 100.0,
            ));
          }
          final dest = _destinationRe.firstMatch(line);
          if (dest != null) downloadedPath = dest.group(1)!.trim();
        }
      });

      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen((chunk) => item.logBuffer.write(chunk));

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        _fail(item, 'yt-dlp exited with code $exitCode', onUpdate);
        return;
      }
    } catch (e) {
      _fail(item, e.toString(), onUpdate);
      return;
    }

    // Fall back to finding the newest audio file if yt-dlp didn't print a path
    final String nativeFile =
        downloadedPath ?? _findLatestAudio(outputDir) ?? '';
    if (nativeFile.isEmpty || !File(nativeFile).existsSync()) {
      _fail(item, 'Could not locate downloaded file', onUpdate);
      return;
    }

    final baseName = p.basenameWithoutExtension(nativeFile);
    final m4aPath = p.join(outputDir, '$baseName.m4a');

    if (normalize) {
      onUpdate(item.copyWith(status: DownloadStatus.normalizing, progress: 0.0));

      // Pass 1: measure integrated loudness
      item.logBuffer.writeln('\n[normalize] Pass 1: measuring loudness...');
      final lufsFilter = 'loudnorm=I=$normalizeLufs:print_format=json';
      String pass1Json = '';
      try {
        final pass1 = await Process.run(ffmpeg, [
          '-i', nativeFile,
          '-af', lufsFilter,
          '-vn', '-f', 'null',
          'NUL',
        ]);
        // loudnorm prints its JSON to stderr
        final output = '${pass1.stdout}\n${pass1.stderr}';
        item.logBuffer.writeln(output);
        final match = _loudnormJsonRe.firstMatch(output);
        if (match != null) pass1Json = match.group(0)!;
      } catch (e) {
        _fail(item, 'loudnorm analysis failed: $e', onUpdate);
        return;
      }

      if (pass1Json.isEmpty) {
        _fail(item, 'Could not read loudnorm analysis from ffmpeg output', onUpdate);
        return;
      }

      // Parse the JSON fields ffmpeg emits
      double? measuredI = _jsonDouble(pass1Json, 'input_i');
      double? measuredLra = _jsonDouble(pass1Json, 'input_lra');
      double? measuredTp = _jsonDouble(pass1Json, 'input_tp');
      double? measuredThresh = _jsonDouble(pass1Json, 'input_thresh');

      if (measuredI == null || measuredLra == null ||
          measuredTp == null || measuredThresh == null) {
        _fail(item, 'Failed to parse loudnorm measurement values', onUpdate);
        return;
      }

      item.logBuffer.writeln(
          '[normalize] measured I=$measuredI LUFS  target=$normalizeLufs LUFS');

      // Pass 2: convert to m4a applying the measured loudnorm in linear mode
      item.logBuffer.writeln('[normalize] Pass 2: converting to m4a with loudnorm...');
      onUpdate(item.copyWith(status: DownloadStatus.normalizing, progress: 0.5));
      final applyFilter =
          'loudnorm=I=$normalizeLufs'
          ':measured_I=$measuredI'
          ':measured_LRA=$measuredLra'
          ':measured_TP=$measuredTp'
          ':measured_thresh=$measuredThresh'
          ':linear=true';
      try {
        final pass2 = await Process.run(ffmpeg, [
          '-i', nativeFile,
          '-vn',
          '-af', applyFilter,
          '-c:a', 'aac',
          '-b:a', '256k',
          '-y',
          m4aPath,
        ]);
        item.logBuffer.writeln('${pass2.stdout}\n${pass2.stderr}');
        if (pass2.exitCode != 0) {
          _fail(item, 'ffmpeg conversion failed (exit ${pass2.exitCode})', onUpdate);
          return;
        }
      } catch (e) {
        _fail(item, 'ffmpeg conversion failed: $e', onUpdate);
        return;
      }
    } else {
      // No normalization — straight convert to m4a
      onUpdate(item.copyWith(status: DownloadStatus.converting, progress: 0.0));
      item.logBuffer.writeln('\n[convert] Converting to m4a...');
      try {
        final result = await Process.run(ffmpeg, [
          '-i', nativeFile,
          '-vn',
          '-c:a', 'aac',
          '-b:a', '256k',
          '-y',
          m4aPath,
        ]);
        item.logBuffer.writeln('${result.stdout}\n${result.stderr}');
        if (result.exitCode != 0) {
          _fail(item, 'ffmpeg conversion failed (exit ${result.exitCode})', onUpdate);
          return;
        }
      } catch (e) {
        _fail(item, 'ffmpeg conversion failed: $e', onUpdate);
        return;
      }
    }

    // Clean up the native file after successful conversion
    if (nativeFile != m4aPath) {
      try { File(nativeFile).deleteSync(); } catch (_) {}
    }

    onUpdate(item.copyWith(
      status: DownloadStatus.done,
      progress: 1.0,
      outputPath: m4aPath,
    ));
  }

  void _fail(DownloadItem item, String msg, void Function(DownloadItem) onUpdate) {
    item.logBuffer.writeln('\nERROR: $msg');
    onUpdate(item.copyWith(status: DownloadStatus.failed, errorMessage: msg));
  }

  double? _jsonDouble(String json, String key) {
    final match = RegExp('"$key"\\s*:\\s*"([^"]+)"').firstMatch(json);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  String? _findLatestAudio(String dir) {
    const exts = {'.webm', '.opus', '.m4a', '.mp4', '.ogg', '.flac', '.wav', '.mp3'};
    try {
      final files = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => exts.contains(p.extension(f.path).toLowerCase()))
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files.isEmpty ? null : files.first.path;
    } catch (_) {
      return null;
    }
  }
}
