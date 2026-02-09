import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class CallEvent {
  CallEvent({required this.number, required this.name, required this.type, required this.timestamp});

  final String number;
  final String name;
  final String type;
  final DateTime timestamp;
}

class CallSyncService {
  static const EventChannel _channel = EventChannel('wire/call_events');
  final _controller = StreamController<CallEvent>.broadcast();

  Stream<CallEvent> get callEvents => _controller.stream;

  void start() {
    if (!Platform.isAndroid) {
      return;
    }
    _channel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final number = event['number']?.toString() ?? '';
        final name = event['name']?.toString() ?? '';
        final type = event['type']?.toString() ?? 'unknown';
        final ts = int.tryParse(event['timestamp']?.toString() ?? '') ?? 0;
        if (ts > 0) {
          _controller.add(CallEvent(number: number, name: name, type: type, timestamp: DateTime.fromMillisecondsSinceEpoch(ts)));
        }
      }
    });
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
