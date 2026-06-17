import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/update_service.dart';

final _depStateProvider =
    StateNotifierProvider<_DepNotifier, _DepState>((ref) {
  return _DepNotifier(ref.read(updateServiceProvider));
});

enum _DepPhase { checking, downloading, ready, error }

class _DepState {
  final _DepPhase phase;
  final String message;
  _DepState(this.phase, this.message);
}

class _DepNotifier extends StateNotifier<_DepState> {
  final UpdateService _svc;
  _DepNotifier(this._svc) : super(_DepState(_DepPhase.checking, 'Checking dependencies…')) {
    _check();
  }

  Future<void> _check() async {
    final ytOk = File(_svc.ytdlpPath).existsSync();
    final ffOk = File(_svc.ffmpegPath).existsSync();

    if (ytOk && ffOk) {
      state = _DepState(_DepPhase.ready, '');
      return;
    }

    state = _DepState(_DepPhase.downloading,
        '${!ytOk ? 'yt-dlp' : ''}${!ytOk && !ffOk ? ' & ' : ''}${!ffOk ? 'ffmpeg' : ''} not found — downloading…');

    if (!ytOk) {
      final ok = await _svc.ensureYtdlp();
      if (!ok) {
        state = _DepState(_DepPhase.error, 'Failed to download yt-dlp. Check your internet connection.');
        return;
      }
    }

    if (!ffOk) {
      state = _DepState(_DepPhase.downloading, 'Downloading ffmpeg (this may take a minute)…');
      final ok = await _svc.ensureFfmpeg();
      if (!ok) {
        state = _DepState(_DepPhase.error, 'Failed to download ffmpeg. You may need to install it manually.');
        return;
      }
    }

    state = _DepState(_DepPhase.ready, '');
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
