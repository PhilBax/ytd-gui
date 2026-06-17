import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'dart:convert';

final updateServiceProvider = Provider((ref) => UpdateService());

class UpdateInfo {
  final String current;
  final String latest;
  UpdateInfo({required this.current, required this.latest});
}

class UpdateService {
  static const _ytdlpReleasesUrl =
      'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest';
  static const _ytdlpDownloadUrl =
      'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';
  static const _ffmpegZipUrl =
      'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip';

  String get _exeDir {
    final exe = Platform.resolvedExecutable;
    return p.dirname(exe);
  }

  String get ytdlpPath => p.join(_exeDir, 'yt-dlp.exe');
  String get ffmpegPath => p.join(_exeDir, 'ffmpeg.exe');

  // Returns UpdateInfo if a newer version exists, null if up-to-date or unreachable.
  Future<UpdateInfo?> checkYtdlpUpdate() async {
    try {
      final current = await _currentYtdlpVersion();
      final latest = await _latestYtdlpVersion();
      if (latest == null) return null;
      if (current == null || current != latest) {
        return UpdateInfo(current: current ?? 'not installed', latest: latest);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _currentYtdlpVersion() async {
    if (!File(ytdlpPath).existsSync()) return null;
    try {
      final result = await Process.run(ytdlpPath, ['--version']);
      return (result.stdout as String).trim();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _latestYtdlpVersion() async {
    final resp = await http
        .get(Uri.parse(_ytdlpReleasesUrl),
            headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return json['tag_name'] as String?;
  }

  Future<bool> downloadYtdlp(String version) async {
    try {
      final resp = await http
          .get(Uri.parse(_ytdlpDownloadUrl))
          .timeout(const Duration(minutes: 3));
      if (resp.statusCode != 200) return false;
      await File(ytdlpPath).writeAsBytes(resp.bodyBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ensureYtdlp() async {
    if (File(ytdlpPath).existsSync()) return true;
    return downloadYtdlp('latest');
  }

  Future<bool> ensureFfmpeg() async {
    if (File(ffmpegPath).existsSync()) return true;
    try {
      final resp = await http
          .get(Uri.parse(_ffmpegZipUrl))
          .timeout(const Duration(minutes: 10));
      if (resp.statusCode != 200) return false;

      final archive = ZipDecoder().decodeBytes(resp.bodyBytes);
      for (final file in archive) {
        if (file.isFile &&
            (file.name.endsWith('bin/ffmpeg.exe') ||
                file.name.endsWith('bin\\ffmpeg.exe'))) {
          await File(ffmpegPath)
              .writeAsBytes(file.content as List<int>);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
