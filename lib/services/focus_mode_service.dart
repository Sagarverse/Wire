import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class FocusModeService {
  static const _channel = MethodChannel('wire/platform');

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onFocusStateChanged => _controller.stream;

  bool _isFocusEnabled = false;
  bool get isFocusEnabled => _isFocusEnabled;

  Future<void> init() async {
    if (Platform.isAndroid) {
      // On Android we can listen for DND changes via a broadcast receiver (native side)
      // or check periodically if simpler. Let's assume native push for now.
    }
  }

  void updateState(bool enabled) {
    if (_isFocusEnabled != enabled) {
      _isFocusEnabled = enabled;
      _controller.add(enabled);
    }
  }

  Future<void> setFocusMode(bool enable) async {
    updateState(enable);
    try {
      await _channel.invokeMethod('setFocusMode', {'enabled': enable});
    } catch (e) {
      // ignore errors but maintain local state for UI responsiveness
    }
  }

  void dispose() {
    _controller.close();
  }
}
