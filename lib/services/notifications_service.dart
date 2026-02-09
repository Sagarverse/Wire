import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationsService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, macOS: darwinSettings);
    await _plugin.initialize(settings);

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }
  }

  Future<void> showNotification({required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      'wire_notifications',
      'Wire Notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const macDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, macOS: macDetails);
    await _plugin.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details);
  }
}
