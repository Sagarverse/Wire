import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'websocket_service.dart';
import 'clipboard_service.dart';

class BackgroundService {
  static const String notificationChannelId = 'wire_background';
  static const int notificationId = 888;

  Future<void> init() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'Wire Sync Background',
      description: 'Maintains connectivity for instant sync',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Wire Sync',
        initialNotificationContent: 'Running in background',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  Future<void> start() async {
    final service = FlutterBackgroundService();
    if (!(await service.isRunning())) {
      await service.startService();
    }
  }

  Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Pull preferences
  final prefs = await SharedPreferences.getInstance();
  final peerHost = prefs.getString('peer_host') ?? '';
  final clipboardEnabled = prefs.getBool('clipboard_history_enabled') ?? true;

  if (peerHost.isEmpty) {
    return; // Can't sync without a peer
  }

  // Initialize independent services for background isolate
  final platformChannel = const MethodChannel('wire/platform');
  final webSocketService = WebSocketService(port: 5757);
  final clipboardService = ClipboardService(platformChannel);

  // Connect to peer right away
  try {
    await webSocketService.connectToPeer(peerHost);
    webSocketService.send({
      'type': 'hello',
      'host': 'BackgroundSync', // dummy host
      'filePort': 5758,
      'from': 'background_isolate',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  } catch (_) {}

  // Keep alive timer
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: 'Wire Sync Active',
          content: 'Ecosystem synchronized',
        );
      }
    }

    if (!webSocketService.isClientConnected) {
      try {
        await webSocketService.connectToPeer(peerHost);
      } catch (_) {}
    }
  });

  if (clipboardEnabled) {
    await clipboardService.start();
    String lastClipboard = '';

    // Background Isolate uses SharedPreferences to receive clipboard data from SyncActivity
    // since native EventChannels aren't registered by default in the background engine.
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!webSocketService.isClientConnected) return;
      try {
        await prefs.reload();
        final bgText = prefs.getString('background_clipboard') ?? '';
        if (bgText.isNotEmpty &&
            bgText != lastClipboard &&
            !clipboardService.shouldIgnoreIncoming(bgText)) {
          lastClipboard = bgText;
          clipboardService.markLocal(bgText);
          webSocketService.send({
            'type': 'clipboard',
            'text': bgText,
            'from': 'background_isolate',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          await prefs.remove('background_clipboard');
        }

        // Secondary attempt using standard Flutter Clipboard
        final clipData = await Clipboard.getData(Clipboard.kTextPlain);
        final text = clipData?.text ?? '';
        if (text.isNotEmpty &&
            text != lastClipboard &&
            !clipboardService.shouldIgnoreIncoming(text)) {
          lastClipboard = text;
          clipboardService.markLocal(text);
          webSocketService.send({
            'type': 'clipboard',
            'text': text,
            'from': 'background_isolate',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
      } catch (_) {}
    });

    // Also listen to incoming things so we can update the clipboard in background
    webSocketService.messages.listen((msg) async {
      final type = msg['type']?.toString() ?? '';
      if (type == 'clipboard') {
        final text = msg['text']?.toString() ?? '';
        if (!clipboardService.shouldIgnoreIncoming(text)) {
          await clipboardService.setClipboardText(text);
          lastClipboard = text;
        }
      }
    });
  }
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return true;
}
