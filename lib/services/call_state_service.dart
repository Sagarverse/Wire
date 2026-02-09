import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class CallStateEvent {
  CallStateEvent({required this.state, required this.number, required this.timestamp});

  final String state;
  final String number;
  final DateTime timestamp;

  bool get isRinging => state == 'ringing';
}

class CallStateService {
  static const EventChannel _channel = EventChannel('wire/call_state');
  final _controller = StreamController<CallStateEvent>.broadcast();

  Stream<CallStateEvent> get events => _controller.stream;

  void start() {
    if (!Platform.isAndroid) {
      return;
    }
    _channel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final state = event['state']?.toString() ?? 'unknown';
        final number = event['number']?.toString() ?? '';
        final ts = int.tryParse(event['timestamp']?.toString() ?? '') ?? 0;
        if (ts > 0) {
          _controller.add(CallStateEvent(state: state, number: number, timestamp: DateTime.fromMillisecondsSinceEpoch(ts)));
        }
      }
    });
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
