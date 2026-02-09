import 'dart:async';
import 'package:flutter/services.dart';

class ClipboardService {
  ClipboardService(
    this._channel, {
    this.pollInterval = const Duration(milliseconds: 1200),
    this.minEmitInterval = const Duration(milliseconds: 1500),
  });

  final MethodChannel _channel;
  final EventChannel _eventChannel = const EventChannel('wire/clipboard_events');
  final Duration pollInterval;
  final Duration minEmitInterval;
  final _controller = StreamController<String>.broadcast();
  Timer? _timer;
  String? _lastLocalText;
  String? _lastRemoteText;
  DateTime? _lastRemoteAt;
  DateTime? _lastEmitAt;
  StreamSubscription? _eventSub;

  Stream<String> get onClipboardChanged => _controller.stream;

  Future<void> start() async {
    _eventSub ??= _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is String && event.isNotEmpty) {
        if (event == _lastLocalText || event == _lastRemoteText) {
          return;
        }
        if (_lastEmitAt != null && DateTime.now().difference(_lastEmitAt!) < minEmitInterval) {
          return;
        }
        _lastLocalText = event;
        _lastEmitAt = DateTime.now();
        _controller.add(event);
      }
    }, onError: (_) {
      // ignore
    });

    _timer ??= Timer.periodic(pollInterval, (_) async {
      final text = await getClipboardText();
      if (text == null || text.isEmpty) {
        return;
      }
      if (text == _lastLocalText || text == _lastRemoteText) {
        return;
      }
      if (_lastEmitAt != null && DateTime.now().difference(_lastEmitAt!) < minEmitInterval) {
        return;
      }
      _lastLocalText = text;
      _lastEmitAt = DateTime.now();
      _controller.add(text);
    });
  }

  void stop() {
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
    if (_lastRemoteAt != null && DateTime.now().difference(_lastRemoteAt!).inMilliseconds < 2500) {
      return true;
    }
    return false;
  }

  void markRemote(String text) {
    _lastRemoteText = text;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
