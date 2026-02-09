import 'dart:async';
import 'package:flutter/services.dart';

class ShareIntentService {
  static const EventChannel _channel = EventChannel('wire/shared_files');
  final _controller = StreamController<List<String>>.broadcast();

  Stream<List<String>> get sharedFiles => _controller.stream;

  void start() {
    _channel.receiveBroadcastStream().listen((event) {
      if (event is List) {
        final paths = event.whereType<String>().toList();
        if (paths.isNotEmpty) {
          _controller.add(paths);
        }
      }
    });
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
