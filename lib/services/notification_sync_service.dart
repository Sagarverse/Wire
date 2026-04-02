import 'package:flutter/services.dart';

class NotificationSyncService {
  static const EventChannel _channel = EventChannel('wire/notifications');

  Stream<Map<String, dynamic>> get onNotificationReceived {
    return _channel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{};
    });
  }
}
