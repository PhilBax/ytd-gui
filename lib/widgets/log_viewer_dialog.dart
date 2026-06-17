import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/download_item.dart';

class LogViewerDialog extends StatelessWidget {
  final DownloadItem item;
  const LogViewerDialog({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final log = item.logBuffer.toString();

    return Dialog(
      child: SizedBox(
        width: 700,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Log — ${item.title.isNotEmpty ? item.title : item.url}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'Copy to clipboard',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: log)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    log.isEmpty ? '(no output yet)' : log,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFCCCCCC),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
