import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  final service = FlutterBackgroundService();
  service.invoke('action', {'id': notificationResponse.actionId});
}

@pragma('vm:entry-point')
class BackgroundService {
  static const notificationChannelId = 'my_foreground';
  static const notificationId = 888;

  // These keys are stored to share state between main app and background isolate
  static const String keyPeerHost = 'last_peer_host';
  static const String keySyncPaused = 'sync_paused';
  static const String keySilentClipboard = 'silent_clipboard';
  static const String keyDeviceId = 'device_id';

  static bool get _isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> init() async {
    if (!_isSupported) return;

    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'Wire Sync Active',
      description: 'Maintains background synchronization.',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Wire Sync',
        initialNotificationContent: 'Sync service active',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(),
    );

    debugPrint('Background service configured');
  }

  Future<void> start() async {
    if (!_isSupported) return;
    final service = FlutterBackgroundService();
    await service.startService();
  }

  static void savePeerHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyPeerHost, host);
    
    if (_isSupported) {
      // Tell the background service to reconnect
      final service = FlutterBackgroundService();
      service.invoke('reconnect', {'host': host});
    }
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    try {
      DartPluginRegistrant.ensureInitialized();
    } catch (_) {
      // Some plugins (e.g. flutter_background_service_android) cannot be
      // initialised inside the background isolate — silently skip them.
    }

    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('ic_bg_service_small')),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    void updateNotification(String content, {int? progress, int? total}) {
      if (service is AndroidServiceInstance) {
         final bool showProgress = progress != null && total != null && total > 0;
         flutterLocalNotificationsPlugin.show(
           notificationId,
           'Wire Sync',
           content,
           NotificationDetails(
             android: AndroidNotificationDetails(
               notificationChannelId,
               'Wire Sync status',
               icon: 'ic_bg_service_small',
               ongoing: true,
               autoCancel: false,
               showProgress: showProgress,
               maxProgress: showProgress ? 100 : 0,
               progress: showProgress ? ((progress / total) * 100).toInt() : 0,
               importance: Importance.low,
               actions: [
                 AndroidNotificationAction('sync_clipboard', 'Sync Clipboard', showsUserInterface: true),
                 AndroidNotificationAction('stop', 'Stop Service', showsUserInterface: false),
                 AndroidNotificationAction('ring_device', 'Ring Device', showsUserInterface: true),
               ]
             ),
           ),
         );
      }
    }

    service.on('updateProgress').listen((event) {
       final content = event?['content']?.toString() ?? 'Syncing...';
       final progress = event?['progress'] as int?;
       final total = event?['total'] as int?;
       updateNotification(content, progress: progress, total: total);
    });

    // Set initial notification with actions
    updateNotification('Sync service active');

    // Background Isolate Specific Services
    final platform = const MethodChannel('wire/platform');
    final wsService = _BackgroundWsService();
    final p2pService = _BackgroundP2PService();

    service.on('reconnect').listen((event) {
       final host = event?['host']?.toString();
       if (host != null) wsService.connect(host);
    });

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    service.on('action').listen((event) async {
       final id = event?['id']?.toString();
       if (id == 'sync_clipboard') {
          try {
            final text = await platform.invokeMethod<String>('getClipboardText');
            if (text != null && text.isNotEmpty) {
               wsService.send({'type': 'clipboard', 'text': text});
               updateNotification('Force synced clipboard');
            }
          } catch (_) {}
       } else if (id == 'ring_device') {
          wsService.send({'type': 'find_phone'});
          updateNotification('Ringing remote device...');
       } else if (id == 'stop') {
          service.stopSelf();
       }
    });

    // Initial connection attempt from storage
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(keyPeerHost);
    final myId = prefs.getString(keyDeviceId);
    
    if (host != null) wsService.connect(host);
    if (myId != null) p2pService.start(myId);

    // PERSISTENT CLIPBOARD MONITORING
    // On Android, we can poll the clipboard in background within this isolate.
    // Note: Since Android 10+, clipboard access is only for foreground apps.
    // However, if we're a foreground service, we might still have access or
    // work around it via Accessibility Services (which we already have for mouse input).

    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
           try {
             // Request text from native side (to bypass restriction where possible)
             final text = await platform.invokeMethod<String>('getClipboardText');
             if (text != null && text.isNotEmpty) {
               final last = prefs.getString('bg_last_text');
               if (text != last) {
                 await prefs.setString('bg_last_text', text);
                 wsService.send({'type': 'clipboard', 'text': text});
               }
             }
           } catch (e) {
             // Silence errors in background loop
           }
        }
      }

      // Keep connection alive or attempt reconnect
      if (!wsService.isConnected && host != null) {
        wsService.connect(host);
      }
    });

    // Handle WebSocket messages in background channel
    wsService.onMessage = (message) async {
       final type = message['type']?.toString();
       if (type == 'clipboard') {
          final text = message['text']?.toString();
          if (text != null) {
             await platform.invokeMethod('setClipboardText', {'text': text});
             await prefs.setString('bg_last_text', text);

             // Update notification
             updateNotification('Synced: ${text.length > 20 ? '${text.substring(0, 17)}...' : text}');
          }
       }
    };

    // Handle P2P messages in background
    p2pService.onMessage = (message) async {
       final type = message['type']?.toString();
       if (type == 'clipboard') {
          final text = message['text']?.toString();
          if (text != null) {
             await platform.invokeMethod('setClipboardText', {'text': text});
             await prefs.setString('bg_last_text', text);
             updateNotification('P2P Synced: ${text.length > 20 ? '${text.substring(0, 17)}...' : text}');
          }
       } else if (type == 'find_phone') {
          await platform.invokeMethod('ringPhone');
          updateNotification('P2P: Ringing this device...');
       }
    };
  }
}

// Minimal P2P signaling client for background isolate
class _BackgroundP2PService {
  MqttServerClient? _mqttClient;
  String? _myId;
  Function(Map<String, dynamic>)? onMessage;

  void start(String deviceId) async {
    if (_mqttClient != null) return;
    _myId = deviceId;

    final clientId = 'wire_bg_${const Uuid().v4()}';
    _mqttClient = MqttServerClient.withPort('broker.hivemq.com', clientId, 8884);
    _mqttClient!.useWebSocket = true;
    _mqttClient!.secure = true;
    _mqttClient!.setProtocolV311();
    _mqttClient!.keepAlivePeriod = 20;
    _mqttClient!.autoReconnect = true;

    _mqttClient!.onConnected = () {
      debugPrint('Background P2P: Connected');
      _mqttClient!.subscribe('wire/p2p/+_to_$_myId', MqttQos.atLeastOnce);
    };

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _mqttClient!.connectionMessage = connMess;

    try {
      await _mqttClient!.connect();
      _mqttClient!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        if (c == null) return;
        final recMess = c[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        try {
          final msg = jsonDecode(payload);
          // Only handle non-WebRTC signaling (data messages sent via signaling channel as fallback or for small syncs)
          if (msg['type'] != 'offer' && msg['type'] != 'answer' && msg['type'] != 'candidate') {
            onMessage?.call(msg);
          }
        } catch (_) {}
      });
    } catch (_) {}
  }
}

// Minimal WebSocket handler for background isolate
class _BackgroundWsService {
  WebSocket? _socket;
  bool _connecting = false;
  Function(Map<String, dynamic>)? onMessage;

  bool get isConnected => _socket?.readyState == WebSocket.open;

  void connect(String host) async {
    if (_connecting || isConnected) return;
    _connecting = true;
    try {
      _socket = await WebSocket.connect('ws://$host:5757').timeout(const Duration(seconds: 5));
      _socket?.listen(
        (data) {
          try {
            final Map<String, dynamic> msg = Map<String, dynamic>.from(jsonDecode(data));
            onMessage?.call(msg);
          } catch (_) {}
        },
        onDone: () => _socket = null,
        onError: (_) => _socket = null,
      );
    } catch (_) {
    } finally {
      _connecting = false;
    }
  }


  void send(Map<String, dynamic> msg) {
    if (isConnected) {
      _socket?.add(jsonEncode(msg));
    }
  }
}
