import 'dart:async';
import 'package:flutter/services.dart';

class ClipboardService {
  ClipboardService(
    this._channel, {
    this.pollInterval = const Duration(milliseconds: 1500),
  });

  final MethodChannel _channel;
  final EventChannel _eventChannel = const EventChannel(
    'wire/clipboard_events',
  );
  final Duration pollInterval;
  final _controller = StreamController<String>.broadcast();
  Timer? _timer;
  String? _lastLocalText;
  String? _lastRemoteText;
  DateTime? _lastRemoteAt;
  StreamSubscription? _eventSub;
  bool _started = false;

  Stream<String> get onClipboardChanged => _controller.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Try native event channel first (faster, less CPU)
    _eventSub ??= _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is String && event.isNotEmpty) {
          _onNewClipboardText(event);
        }
      },
      onError: (_) {
        // Native event channel not available, rely on polling
      },
    );

    // Polling as a reliable fallback (1.5s interval to reduce CPU load)
    _timer ??= Timer.periodic(pollInterval, (_) async {
      final text = await getClipboardText();
      if (text == null || text.isEmpty) return;
      _onNewClipboardText(text);
    });
  }

  void _onNewClipboardText(String text) {
    if (text == _lastLocalText || text == _lastRemoteText) return;
    // Avoid re-emitting text that was just set from remote
    if (_lastRemoteAt != null &&
        DateTime.now().difference(_lastRemoteAt!).inMilliseconds < 500) {
      return;
    }
    _lastLocalText = text;
    _controller.add(text);
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
    _eventSub?.cancel();
    _eventSub = null;
  }

  Future<String?> getClipboardText() async {
    try {
      final result = await _channel.invokeMethod<String>('getClipboardText');
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> setClipboardText(String text) async {
    _lastRemoteText = text;
    _lastLocalText = text; // Also mark as local to prevent re-detection
    _lastRemoteAt = DateTime.now();
    try {
      await _channel.invokeMethod('setClipboardText', {'text': text});
    } catch (_) {
      // ignore
    }
  }

  void markLocal(String text) {
    _lastLocalText = text;
  }

  bool shouldIgnoreIncoming(String text) {
    if (text.isEmpty) return true;
    if (text == _lastLocalText || text == _lastRemoteText) return true;
    if (_lastRemoteAt != null &&
        DateTime.now().difference(_lastRemoteAt!).inMilliseconds < 500) {
      return true;
    }
    return false;
  }

  void markRemote(String text) {
    _lastRemoteText = text;
  }

  /// Returns base64-encoded PNG if an image is on the clipboard, otherwise null.
  Future<String?> getClipboardImage() async {
    try {
      return await _channel.invokeMethod<String>('getClipboardImage');
    } catch (_) {
      return null;
    }
  }

  /// Writes a base64-encoded image to the clipboard.
  Future<void> setClipboardImage(String base64) async {
    try {
      await _channel.invokeMethod('setClipboardImage', {'base64': base64});
    } catch (_) {
      // ignore
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
