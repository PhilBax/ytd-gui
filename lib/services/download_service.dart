import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/download_item.dart';
import 'update_service.dart';

final downloadServiceProvider = Provider((ref) {
  final updateService = ref.read(updateServiceProvider);
  return DownloadService(updateService);
});

/// Lets a caller cancel the process (if any) currently running on behalf
/// of a [DownloadService.downloadItem] call.
class CancelToken {
  Process? _process;
  bool cancelled = false;

  void _attach(Process process) {
    _process = process;
    // Cancel arrived before this process was attached — kill it immediately.
    if (cancelled) process.kill();
  }

  void cancel() {
    cancelled = true;
    _process?.kill();
  }
}

class DownloadService {
  final UpdateService _updateService;
  DownloadService(this._updateService);

  static final _progressRe = RegExp(r'\[download\]\s+([\d.]+)%');
  // Captures the JSON block loudnorm prints after analysis
  static final _loudnormJsonRe = RegExp(r'\{[\s\S]+?\}', multiLine: true);
  // Unique marker so we can pick yt-dlp's --print output out of the rest
  // of its console noise unambiguously (see _filepathRe below).
  static const _filepathMarker = 'YTDGUI_FILEPATH::';
  static final _filepathRe = RegExp('^${RegExp.escape(_filepathMarker)}(.+)\$');

  Future<void> downloadItem({
    required DownloadItem item,
    required String outputDir,
    required void Function(DownloadItem updated) onUpdate,
    required CancelToken cancelToken,
    bool normalize = false,
    double normalizeLufs = -14.0,
    String ffmpegOverride = '',
  }) async {
    if (cancelToken.cancelled) {
      _fail(item, 'Canceled', onUpdate);
      return;
    }

    // Use the user-specified path if set, otherwise rely on PATH
    final ffmpeg = ffmpegOverride.isNotEmpty ? ffmpegOverride : 'ffmpeg';

    String nativeFile;

    if (item.isLocal) {
      if (!File(item.url).existsSync()) {
        _fail(item, 'File not found: ${item.url}', onUpdate);
        return;
      }
      nativeFile = item.url;
    } else {
      final ytdlp = _updateService.ytdlpPath;

      if (!File(ytdlp).existsSync()) {
        _fail(item, 'yt-dlp not found. Please restart the app to download it.', onUpdate);
        return;
      }

      // Download best audio to a filename based on the video ID rather than
      // its title. Video IDs are plain ASCII, so this — and the --print
      // marker below — sidestep a Windows console encoding bug where
      // non-ASCII title characters (e.g. the fullwidth "？" yt-dlp
      // substitutes for "?" in titles) get silently dropped when yt-dlp's
      // subprocess output is decoded, corrupting any path built from them.
      // The human-readable title is applied ourselves, in Dart, further
      // down for the final output filename.
      final outputTemplate = p.join(outputDir, '%(id)s.%(ext)s');
      final args = [
        '--no-playlist',
        '-f', 'bestaudio',
        if (ffmpegOverride.isNotEmpty) ...['--ffmpeg-location', p.dirname(ffmpeg)],
        '--output', outputTemplate,
        '--newline',
        '--progress',
        // Have yt-dlp tell us the exact final filename itself (id + real
        // container extension), instead of us scraping it out of the
        // human-readable progress log or guessing.
        '--print', 'after_move:$_filepathMarker%(id)s.%(ext)s',
        item.url,
      ];

      item.logBuffer.writeln('> $ytdlp ${args.join(' ')}\n');
      onUpdate(item.copyWith(status: DownloadStatus.downloading, progress: 0.0));

      String? downloadedPath;

      try {
        // Force yt-dlp's Python runtime to emit UTF-8 regardless of the
        // Windows console code page, and decode as UTF-8 on our end — a
        // mismatch here silently mangles non-ASCII characters (e.g. a
        // fullwidth "？" yt-dlp substitutes for "?" in titles), which
        // corrupts the printed Destination path.
        final process = await Process.start(ytdlp, args, environment: {
          'PYTHONUTF8': '1',
          'PYTHONIOENCODING': 'utf-8',
        });
        cancelToken._attach(process);

        process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen((chunk) {
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
            final dest = _filepathRe.firstMatch(line);
            if (dest != null) downloadedPath = dest.group(1)!.trim();
          }
        });

        process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen((chunk) => item.logBuffer.write(chunk));

        final exitCode = await process.exitCode;
        if (cancelToken.cancelled) {
          _fail(item, 'Canceled', onUpdate);
          return;
        }
        if (exitCode != 0) {
          _fail(item, 'yt-dlp exited with code $exitCode', onUpdate);
          return;
        }
      } catch (e) {
        _fail(item, e.toString(), onUpdate);
        return;
      }

      if (downloadedPath == null) {
        _fail(item, 'Could not locate downloaded file', onUpdate);
        return;
      }
      // downloadedPath is just "<id>.<ext>" — join with our own outputDir
      // rather than trusting an absolute path round-tripped through the
      // subprocess, so this stays correct even if outputDir itself
      // contains non-ASCII characters.
      nativeFile = p.join(outputDir, downloadedPath!);
      if (!File(nativeFile).existsSync()) {
        _fail(item, 'Could not locate downloaded file', onUpdate);
        return;
      }
    }

    // For yt-dlp downloads, name the final file after the (human-readable)
    // title we already have in Dart, sanitized for Windows ourselves —
    // rather than round-tripping the title through yt-dlp's own filename
    // template, which is what triggered the encoding bug above. Local
    // files just keep their existing filename.
    final baseName = item.isLocal
        ? p.basenameWithoutExtension(nativeFile)
        : _sanitizeFilename(item.title);
    final m4aPath = p.join(outputDir, '$baseName.m4a');

    if (normalize) {
      onUpdate(item.copyWith(status: DownloadStatus.normalizing, progress: 0.0));

      // Pass 1: measure integrated loudness
      item.logBuffer.writeln('\n[normalize] Pass 1: measuring loudness...');
      final lufsFilter = 'loudnorm=I=$normalizeLufs:print_format=json';
      String pass1Json = '';
      try {
        final pass1 = await _runCaptured(ffmpeg, [
          '-i', nativeFile,
          '-af', lufsFilter,
          '-vn', '-f', 'null',
          'NUL',
        ], cancelToken);
        item.logBuffer.writeln(pass1.output);
        if (cancelToken.cancelled) {
          _fail(item, 'Canceled', onUpdate);
          return;
        }
        final match = _loudnormJsonRe.firstMatch(pass1.output);
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

      if (measuredI == null) {
        _fail(item, 'Failed to parse loudnorm measurement values', onUpdate);
        return;
      }

      item.logBuffer.writeln(
          '[normalize] measured I=$measuredI LUFS  target=$normalizeLufs LUFS');

      // Pass 2: apply a single linear gain to hit the target loudness,
      // then a transparent limiter that only catches the rare peak that
      // would otherwise clip. This avoids loudnorm's own "dynamic" mode,
      // which falls back to a continuous compander (and audibly pumps/
      // distorts) whenever linear gain would exceed its true-peak ceiling.
      final gainDb = (normalizeLufs - measuredI).toStringAsFixed(2);
      item.logBuffer.writeln('[normalize] Pass 2: applying ${gainDb}dB gain...');
      onUpdate(item.copyWith(status: DownloadStatus.normalizing, progress: 0.5));
      final applyFilter = 'volume=${gainDb}dB,alimiter=limit=-1dB:level=false';
      try {
        final pass2 = await _runCaptured(ffmpeg, [
          '-i', nativeFile,
          '-vn',
          '-af', applyFilter,
          '-ac', '2',
          '-c:a', 'aac',
          '-b:a', '256k',
          '-y',
          m4aPath,
        ], cancelToken);
        item.logBuffer.writeln(pass2.output);
        if (cancelToken.cancelled) {
          _fail(item, 'Canceled', onUpdate);
          return;
        }
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
        final result = await _runCaptured(ffmpeg, [
          '-i', nativeFile,
          '-vn',
          '-ac', '2',
          '-c:a', 'aac',
          '-b:a', '256k',
          '-y',
          m4aPath,
        ], cancelToken);
        item.logBuffer.writeln(result.output);
        if (cancelToken.cancelled) {
          _fail(item, 'Canceled', onUpdate);
          return;
        }
        if (result.exitCode != 0) {
          _fail(item, 'ffmpeg conversion failed (exit ${result.exitCode})', onUpdate);
          return;
        }
      } catch (e) {
        _fail(item, 'ffmpeg conversion failed: $e', onUpdate);
        return;
      }
    }

    // Clean up the native file after successful conversion (never delete
    // the user's own local source file)
    if (!item.isLocal && nativeFile != m4aPath) {
      try { File(nativeFile).deleteSync(); } catch (_) {}
    }

    onUpdate(item.copyWith(
      status: DownloadStatus.done,
      progress: 1.0,
      outputPath: m4aPath,
    ));
  }

  /// Runs a process to completion, capturing combined stdout+stderr, while
  /// registering it with [cancelToken] so it can be killed mid-run.
  Future<({int exitCode, String output})> _runCaptured(
      String exe, List<String> args, CancelToken cancelToken) async {
    final process = await Process.start(exe, args);
    cancelToken._attach(process);
    final buf = StringBuffer();
    final stdoutDone =
        process.stdout.transform(const SystemEncoding().decoder).forEach(buf.write);
    final stderrDone =
        process.stderr.transform(const SystemEncoding().decoder).forEach(buf.write);
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    return (exitCode: exitCode, output: buf.toString());
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

  static final _illegalFilenameChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

  /// Makes a title safe to use as a Windows filename. Unlike yt-dlp's own
  /// sanitization (which round-trips through a subprocess and can mangle
  /// non-ASCII substitutions), this runs entirely in Dart on the title text
  /// we already have.
  String _sanitizeFilename(String title) {
    var name = title.replaceAll(_illegalFilenameChars, '_').trim();
    while (name.isNotEmpty && (name.endsWith('.') || name.endsWith(' '))) {
      name = name.substring(0, name.length - 1);
    }
    return name.isEmpty ? 'download' : name;
  }
}
