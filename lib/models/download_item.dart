enum DownloadStatus { queued, downloading, converting, normalizing, done, failed }

class DownloadItem {
  final String id;
  final String url;
  String title;
  DownloadStatus status;
  double progress; // 0.0 – 1.0
  String? outputPath;
  String? errorMessage;
  int retryCount;
  StringBuffer logBuffer;

  DownloadItem({
    required this.id,
    required this.url,
    this.title = '',
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.outputPath,
    this.errorMessage,
    this.retryCount = 0,
  }) : logBuffer = StringBuffer();

  DownloadItem copyWith({
    String? title,
    DownloadStatus? status,
    double? progress,
    String? outputPath,
    String? errorMessage,
    int? retryCount,
  }) {
    final copy = DownloadItem(
      id: id,
      url: url,
      title: title ?? this.title,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      outputPath: outputPath ?? this.outputPath,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
    );
    copy.logBuffer = logBuffer;
    return copy;
  }

  bool get isTerminal =>
      status == DownloadStatus.done || status == DownloadStatus.failed;
}
