import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/transfer_item.dart';
import '../services/file_transfer_service.dart';

class FileTransferProvider extends ChangeNotifier {
  final FileTransferService _fileTransferService;
  final List<TransferItem> _transfers = [];
  StreamSubscription? _progressSub;
  StreamSubscription? _completeSub;

  FileTransferProvider({required FileTransferService fileTransferService})
      : _fileTransferService = fileTransferService {
    // Note: Server is already started by AppState.init() — no need to call startServer() here
    _progressSub = _fileTransferService.receiveProgress.listen(_handleReceiveProgress);
    _completeSub = _fileTransferService.receiveComplete.listen(_handleReceiveComplete);
  }

  List<TransferItem> get transfers => List.unmodifiable(_transfers);

  void _handleReceiveProgress(FileReceiveProgress progress) {
    final index = _transfers.indexWhere((t) => t.name == progress.name && t.status == 'receiving');
    if (index >= 0) {
      final item = _transfers[index];
      item.bytesTransferred = progress.received;
      item.progress = progress.received / progress.total;
      notifyListeners();
    } else {
      // New incoming transfer
      _transfers.insert(0, TransferItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: progress.name,
        total: progress.total,
        direction: 'receive',
        path: progress.path,
        status: 'receiving',
        bytesTransferred: progress.received,
        progress: progress.received / progress.total,
        startTime: DateTime.now(),
      ));
      notifyListeners();
    }
  }

  void _handleReceiveComplete(FileReceiveProgress progress) {
    final index = _transfers.indexWhere((t) => t.name == progress.name && (t.status == 'receiving' || t.status == 'pending'));
    if (index >= 0) {
      _transfers[index].status = 'complete';
      _transfers[index].progress = 1.0;
      _transfers[index].bytesTransferred = progress.total;
      notifyListeners();
    }
  }

  void addTransfer(TransferItem item) {
    _transfers.insert(0, item);
    notifyListeners();
  }

  void updateTransferProgress(String id, double progress, int bytes) {
    final index = _transfers.indexWhere((t) => t.id == id);
    if (index >= 0) {
      _transfers[index].progress = progress;
      _transfers[index].bytesTransferred = bytes;
      notifyListeners();
    }
  }

  void updateTransferStatus(String id, String status) {
    final index = _transfers.indexWhere((t) => t.id == id);
    if (index >= 0) {
      _transfers[index].status = status;
      notifyListeners();
    }
  }

  void clearHistory() {
    _transfers.removeWhere((t) => t.status == 'complete' || t.status == 'failed');
    notifyListeners();
  }

  void removeTransfer(String id) {
    _transfers.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _completeSub?.cancel();
    super.dispose();
  }
}
