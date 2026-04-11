import 'dart:async';
import 'package:flutter/material.dart';
import '../models/clipboard_item.dart';
import '../services/clipboard_service.dart';
import '../services/history_service.dart';
import '../services/websocket_service.dart';

class ClipboardController extends ChangeNotifier {
  final ClipboardService clipboardService;
  final HistoryService historyService;
  final Function(Map<String, dynamic>) onSendMessage;

  ClipboardController({
    required this.clipboardService,
    required this.historyService,
    required this.onSendMessage,
  });

  static const int _maxHistory = 30;

  final List<ClipboardItem> _history = [];
  List<ClipboardItem> get history => List.unmodifiable(_history);

  bool _isSyncPaused = false;
  bool get isSyncPaused => _isSyncPaused;

  StreamSubscription? _clipSub;

  Future<void> init() async {
    await historyService.init();
    final items = await historyService.getClipboardHistory();
    _history.addAll(items.take(_maxHistory));
    notifyListeners();

    // ** FIX: Actually start the clipboard monitoring service **
    await clipboardService.start();

    _clipSub?.cancel();
    _clipSub = clipboardService.onClipboardChanged.listen(
      _handleLocalClipboardChange,
    );
  }

  void _handleLocalClipboardChange(String text) {
    if (_isSyncPaused) return;
    if (text.trim().isEmpty) return;
    if (_history.isNotEmpty && _history.first.text == text) return;

    _addHistory(text, source: 'Local');
    onSendMessage({
      'type': 'clipboard',
      'text': text,
    });
  }

  void receiveRemoteClipboard(String text) async {
    if (_isSyncPaused) return;
    if (text.trim().isEmpty) return;
    if (!clipboardService.shouldIgnoreIncoming(text)) {
      await clipboardService.setClipboardText(text);
      _addHistory(text, source: 'Remote');
    }
  }

  void _addHistory(String text, {required String source}) {
    final item = ClipboardItem(
      text: text,
      timestamp: DateTime.now(),
      from: source,
    );
    // Remove duplicates of the same text
    _history.removeWhere((h) => h.text == text);
    _history.insert(0, item);
    // Cap history at max
    while (_history.length > _maxHistory) {
      _history.removeLast();
    }
    historyService.saveClipboard(item);
    notifyListeners();
  }

  void setSyncPaused(bool paused) {
    _isSyncPaused = paused;
    if (paused) {
      clipboardService.stop();
    } else {
      clipboardService.start();
    }
    notifyListeners();
  }

  void clearHistory() async {
    _history.clear();
    await historyService.clearClipboardHistory();
    notifyListeners();
  }

  @override
  void dispose() {
    _clipSub?.cancel();
    clipboardService.dispose();
    super.dispose();
  }
}
