import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/download_provider.dart';
import '../services/update_service.dart';

final _depStateProvider =
    StateNotifierProvider<_DepNotifier, _DepState>((ref) {
  final svc = ref.read(updateServiceProvider);
  final settings = ref.read(settingsProvider).valueOrNull;
  return _DepNotifier(svc, settings?.ffmpegOverride ?? '');
});

enum _DepPhase { checking, downloading, ready, error }

class _DepState {
  final _DepPhase phase;
  final String message;
  _DepState(this.phase, this.message);
}

class _DepNotifier extends StateNotifier<_DepState> {
  final UpdateService _svc;
  final String _ffmpegOverride;

  _DepNotifier(this._svc, this._ffmpegOverride)
      : super(_DepState(_DepPhase.checking, 'Checking dependencies…')) {
    _check();
  }

  Future<void> _check() async {
    final ytOk = File(_svc.ytdlpPath).existsSync();

    // Check ffmpeg by running it — works whether it's on PATH or a custom path
    final ffmpegExe = _ffmpegOverride.isNotEmpty ? _ffmpegOverride : 'ffmpeg';
    final ffOk = await _isFfmpegRunnable(ffmpegExe);

    if (ytOk && ffOk) {
      state = _DepState(_DepPhase.ready, '');
      return;
    }

    if (!ffOk && ytOk) {
      state = _DepState(_DepPhase.error,
          'ffmpeg not found. Install it and ensure it\'s on your PATH, or set a custom path in Settings.');
      return;
    }

    // yt-dlp missing — auto-download it
    state = _DepState(_DepPhase.downloading, 'yt-dlp not found — downloading…');

    final ytDownloaded = await _svc.ensureYtdlp();
    if (!ytDownloaded) {
      state = _DepState(_DepPhase.error,
          'Failed to download yt-dlp. Check your internet connection.');
      return;
    }

    if (!ffOk) {
      state = _DepState(_DepPhase.error,
          'ffmpeg not found. Install it and ensure it\'s on your PATH, or set a custom path in Settings.');
      return;
    }

    state = _DepState(_DepPhase.ready, '');
  }

  Future<bool> _isFfmpegRunnable(String exe) async {
    try {
      final result = await Process.run(exe, ['-version'])
          .timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

class DependencyBanner extends ConsumerWidget {
  const DependencyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dep = ref.watch(_depStateProvider);
    if (dep.phase == _DepPhase.ready) return const SizedBox.shrink();

    final color = dep.phase == _DepPhase.error
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withAlpha(26),
      child: Row(
        children: [
          if (dep.phase == _DepPhase.downloading ||
              dep.phase == _DepPhase.checking)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(Icons.warning_amber, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(dep.message,
                style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
