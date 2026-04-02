class TransferItem {
  final String id;
  final String name;
  final int total;
  final String direction; // 'send' or 'receive'
  final String path;
  double progress;
  String status; // 'receiving', 'sending', 'complete', 'failed'
  int bytesTransferred;
  DateTime? startTime;

  TransferItem({
    required this.id,
    required this.name,
    required this.total,
    required this.direction,
    required this.path,
    this.progress = 0.0,
    this.status = 'pending',
    this.bytesTransferred = 0,
    this.startTime,
  });

  /// Transfer speed in MB/s (0 if no progress)
  double get speedMBps {
    if (startTime == null || bytesTransferred == 0) return 0;
    final elapsed = DateTime.now().difference(startTime!).inMilliseconds / 1000;
    if (elapsed <= 0) return 0;
    return (bytesTransferred / elapsed) / (1024 * 1024);
  }

  /// Estimated time remaining in seconds
  int? get etaSeconds {
    final speed = speedMBps;
    if (speed <= 0 || bytesTransferred >= total) return null;
    final remainingBytes = total - bytesTransferred;
    final seconds = (remainingBytes / (speed * 1024 * 1024)).toInt();
    return seconds > 0 ? seconds : null;
  }

  /// Human-readable transfer speed ("2.5 MB/s" or "--")
  String get speedLabel {
    final speed = speedMBps;
    if (speed < 0.1) return '--';
    return '${speed.toStringAsFixed(1)} MB/s';
  }

  /// Human-readable ETA ("45s", "2m", "1h" or "--")
  String get etaLabel {
    final eta = etaSeconds;
    if (eta == null) return '--';
    if (eta < 60) return '${eta}s';
    if (eta < 3600) return '${(eta / 60).ceil()}m';
    return '${(eta / 3600).ceil()}h';
  }
}
