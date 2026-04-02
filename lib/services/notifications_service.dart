import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum NotificationCategory { clipboard, file, system }

class NotificationsService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _focusModeActive = false;

  // Debounce: last shown time per category
  final Map<NotificationCategory, DateTime> _lastShown = {};
  static const _clipboardDebounce = Duration(seconds: 3);

  // Focus mode suppression — only system-level alerts get through
  void setFocusMode(bool active) {
    _focusModeActive = active;
  }

  Future<void> init({
    DidReceiveNotificationResponseCallback? onSelectNotification,
  }) async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      macOS: darwinSettings,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: onSelectNotification,
    );

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// Show a notification, with optional debounce and focus-mode respect.
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    NotificationCategory category = NotificationCategory.system,
  }) async {
    // Focus mode: suppress clipboard + file notifications
    if (_focusModeActive &&
        (category == NotificationCategory.clipboard ||
            category == NotificationCategory.file)) {
      return;
    }

    // Debounce clipboard notifications
    if (category == NotificationCategory.clipboard) {
      final last = _lastShown[category];
      if (last != null &&
          DateTime.now().difference(last) < _clipboardDebounce) {
        return;
      }
    }

    _lastShown[category] = DateTime.now();

    const androidDetails = AndroidNotificationDetails(
      'wire_notifications',
      'Wire Notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const macDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      macOS: macDetails,
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Show a clipboard sync notification (debounced).
  Future<void> showClipboardNotification(String text) async {
    await showNotification(
      title: 'Clipboard synced',
      body: text.length > 80 ? '${text.substring(0, 80)}…' : text,
      category: NotificationCategory.clipboard,
    );
  }

  /// Show a file received notification.
  Future<void> showFileNotification(String name) async {
    await showNotification(
      title: 'File received',
      body: name,
      category: NotificationCategory.file,
    );
  }
}
