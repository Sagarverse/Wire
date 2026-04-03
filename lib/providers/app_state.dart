import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../services/background_service.dart' show BackgroundService;
import '../services/discovery_service.dart';
import '../services/pairing_service.dart';
import '../services/app_identity.dart';
import '../services/websocket_service.dart';
import '../services/file_transfer_service.dart';
import '../services/screen_mirror_service.dart';

import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_sync_service.dart';
import '../services/notifications_service.dart';
import '../controllers/clipboard_controller.dart' show ClipboardController;

class AppState extends ChangeNotifier {
  final DiscoveryService discoveryService;
  final PairingService pairingService;
  final AppIdentity identityService;
  final WebSocketService webSocketService;
  final NotificationSyncService notificationSyncService;
  final NotificationsService notificationsService;
  final FileTransferService fileTransferService;
  late final ScreenMirrorService mirrorService;
  final _mirrorRequestController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get mirrorRequestStream => _mirrorRequestController.stream;
  
  ClipboardController? _clipboardController;

  static const _platform = MethodChannel('wire/platform');

  // Reconnection
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 20;

  // Debounce for notifyListeners
  bool _notifyScheduled = false;

  // Throttle for accessibility warnings
  DateTime? _lastAccessibilityWarning;
  DateTime? _lastErrorLog;

  void _throttledAccessibilityWarning() {
    final now = DateTime.now();
    if (_lastAccessibilityWarning == null || now.difference(_lastAccessibilityWarning!) > const Duration(seconds: 30)) {
      _lastAccessibilityWarning = now;
      notificationsService.showNotification(
        title: 'Permission Required',
        body: 'Please enable Accessibility for Wire in System Settings.',
        category: NotificationCategory.system,
      );
    }
  }

  void _throttledErrorLog(String message) {
    final now = DateTime.now();
    if (_lastErrorLog == null || now.difference(_lastErrorLog!) > const Duration(seconds: 5)) {
      _lastErrorLog = now;
      debugPrint(message);
    }
  }

  AppState({
    required this.discoveryService,
    required this.pairingService,
    required this.identityService,
    required this.webSocketService,
    required this.notificationSyncService,
    required this.notificationsService,
    required this.fileTransferService,
  });

  bool _isFirstRun = true;
  bool get isFirstRun => _isFirstRun;

  void setFirstRun(bool value) {
    _isFirstRun = value;
    notifyListeners();
  }

  String _deviceId = '';
  String get deviceId => _deviceId;

  String _deviceName = '';
  String get deviceName => _deviceName;

  final List<DiscoveryPeerInfo> _discoveredPeers = [];
  List<DiscoveryPeerInfo> get discoveredPeers => List.unmodifiable(_discoveredPeers);

  // Settings
  bool _discoveryEnabled = true;
  bool get discoveryEnabled => _discoveryEnabled;
  bool _autoConnectEnabled = true;
  bool get autoConnectEnabled => _autoConnectEnabled;
  bool _notificationSyncEnabled = false;
  bool get notificationSyncEnabled => _notificationSyncEnabled;
  bool _silentClipboard = true;
  bool get silentClipboard => _silentClipboard;
  bool _labsMirrorFeaturesEnabled = true;
  bool get labsMirrorFeaturesEnabled => _labsMirrorFeaturesEnabled;
  bool _labsMountFinderEnabled = true;
  bool get labsMountFinderEnabled => _labsMountFinderEnabled;

  String? _downloadsPath;
  String? get downloadsPath => _downloadsPath;

  // Status
  bool _isSyncPaused = false;
  bool get isSyncPaused => _isSyncPaused;
  bool _localFocusMode = false;
  bool get localFocusMode => _localFocusMode;
  bool _isUsbMounted = false;
  bool get isUsbMounted => _isUsbMounted;
  bool _isPairingInProgress = false;
  int _batteryLevel = 100;
  int get batteryLevel => _batteryLevel;
  BatteryState _batteryState = BatteryState.unknown;
  BatteryState get batteryState => _batteryState;

  // Remote Status
  int? _remoteBattery;
  int? get remoteBattery => _remoteBattery;
  bool? _remoteIsCharging;
  bool? get remoteIsCharging => _remoteIsCharging;
  int? _pingMs;
  int? get pingMs => _pingMs;
  DateTime? _lastSyncAt;
  DateTime? get lastSyncAt => _lastSyncAt;

  ConnectionStatus _lastStatus = ConnectionStatus.idle;
  ConnectionStatus get lastStatus => _lastStatus;
  
  String? get errorMessage => webSocketService.errorMessage;

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future.microtask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  Future<void> init() async {
    _deviceId = await identityService.getOrCreateDeviceId();
    _deviceName = await identityService.getDeviceName() ?? 'Unknown Device';
    
    await pairingService.init();
    if (pairingService.devices.isNotEmpty) {
      _isFirstRun = false;
    }

    final prefs = await SharedPreferences.getInstance();
    _discoveryEnabled = prefs.getBool('discovery_enabled') ?? true;
    _autoConnectEnabled = prefs.getBool('auto_connect') ?? true;
    _notificationSyncEnabled = prefs.getBool('notification_sync_enabled') ?? false;
    _silentClipboard = prefs.getBool('silent_clipboard') ?? true;
    _labsMirrorFeaturesEnabled = prefs.getBool('labs_mirror_features_enabled') ?? true;
    _labsMountFinderEnabled = prefs.getBool('labs_mount_finder_enabled') ?? true;
    _isSyncPaused = prefs.getBool('sync_paused') ?? false;
    _downloadsPath = prefs.getString('downloads_path');

    mirrorService = ScreenMirrorService(
      deviceId: _deviceId,
      onSendSignal: (signal) => webSocketService.send(signal),
    );

    try {
      await webSocketService.startServer();
      await fileTransferService.startServer();
      
      if (_discoveryEnabled) {
        _startLocalDiscovery();
      }
    } catch (e) {
      debugPrint('Failed to start network services: $e');
    }
    
    notifyListeners();

    webSocketService.status.listen((status) {
      final prev = _lastStatus;
      _lastStatus = status;
      if (status == ConnectionStatus.connected) {
        _reconnectAttempts = 0;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _sendIdentity();
      } else if (status == ConnectionStatus.disconnected && prev == ConnectionStatus.connected) {
        _startAutoReconnect();
      }
      _scheduleNotify();
      _updateMacStatusBar();
    });

    webSocketService.messages.listen(_handleMessage);

    if (Platform.isAndroid) {
      notificationSyncService.onNotificationReceived.listen((notif) {
        if (_notificationSyncEnabled && pairingService.activeDevice != null) {
          webSocketService.send({
            'type': 'sync_notification',
            'title': notif['title'],
            'body': notif['body'],
            'packageName': notif['packageName'],
            'from': _deviceId,
          });
        }
      });
    }
    _setupMacFileServer();
    _setupAudioBridge();
    _setupStatusBarChannel();
    _updateMacStatusBar();
  }

  void setClipboardController(ClipboardController controller) {
    _clipboardController = controller;
  }

  void _setupAudioBridge() {
    if (Platform.isMacOS) {
      const audioChannel = EventChannel('wire/audio_stream');
      audioChannel.receiveBroadcastStream().listen((data) {
        if (data is Uint8List && pairingService.activeDevice != null) {
          webSocketService.send({
            'type': 'audio_chunk',
            'data': base64Encode(data),
            'from': _deviceId,
          });
        }
      }, onError: (e) => debugPrint('Audio bridge error: $e'));
    }
  }

  Future<void> _setupMacFileServer() async {
    try {
      if (Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          fileTransferService.setAllowedRoots([home]);
        }
      } else if (Platform.isAndroid) {
        fileTransferService.setAllowedRoots(['/storage/emulated/0', '/sdcard']);
      }
    } catch (e) {
      debugPrint('Error setting up file server: $e');
    }
  }

  // ── macOS Status Bar Integration ───────────────────────────────────────────

  void _setupStatusBarChannel() {
    if (!Platform.isMacOS) return;
    const statusBarChannel = MethodChannel('wire/statusbar');
    statusBarChannel.setMethodCallHandler((call) async {
      if (call.method == 'findPhone') {
        findPhone();
      }
    });
  }

  void _updateMacStatusBar() {
    if (!Platform.isMacOS) return;
    final connected = _lastStatus == ConnectionStatus.connected &&
        pairingService.activeDevice != null;
    final peerName = pairingService.activeDevice?.name;
    _platform.invokeMethod('updateStatusBar', {
      'connected': connected,
      'peerName': peerName,
    }).catchError((_) {});
  }

  void _updateMacMountStatus() {
    if (!Platform.isMacOS) return;
    _platform.invokeMethod('updateMountStatus', {
      'mounted': _isUsbMounted,
    }).catchError((_) {});
  }

  void _sendIdentity() {
    webSocketService.send({
      'type': 'identity',
      'deviceId': _deviceId,
      'deviceName': _deviceName,
      'os': Platform.isAndroid ? 'android' : (Platform.isMacOS ? 'macos' : 'unknown'),
      'battery': _batteryLevel,
      'isCharging': _batteryState == BatteryState.charging,
      'filePort': fileTransferService.actualPort,
    });
  }

  void _handleMessage(Map<String, dynamic> message) async {
    final type = message['type']?.toString();
    try {
      if (type == 'identity') {
        _handleIdentity(message);
      } else if (type == 'status_update' || type == 'status') {
        final battery = message['battery'] is int
            ? message['battery'] as int
            : int.tryParse(message['battery']?.toString() ?? '');
        final isCharging = message['isCharging'] == true;
        setRemoteStatus(battery, isCharging);
      } else if (type == 'sync_notification') {
        final title = message['title']?.toString() ?? 'Notification';
        final body = message['body']?.toString() ?? '';
        notificationsService.showNotification(
          title: title,
          body: body,
          category: NotificationCategory.system,
        );
      } else if (type == 'mouse_event' && Platform.isMacOS) {
        await _platform.invokeMethod('dispatchMouseEvent', {
          'dx': message['dx'],
          'dy': message['dy'],
          'action': message['action'],
        });
      } else if (type == 'keyboard_event' && Platform.isMacOS) {
        await _platform.invokeMethod('inputKeyEvent', {
          'keyCode': message['keyCode'],
          'action': message['action'],
        });
      } else if (type == 'inputText' && Platform.isMacOS) {
        await _platform.invokeMethod('inputText', {
          'text': message['text'],
        });
      } else if (type == 'screen_offer' || type == 'camera_offer') {
        _onRemoteMirrorRequest(message, isCamera: type == 'camera_offer');
      } else if (type == 'screen_answer' || type == 'camera_answer') {
        mirrorService.receiveAnswer(message['sdp']?.toString() ?? '');
      } else if (type == 'screen_ice' || type == 'camera_ice') {
        mirrorService.addIceCandidate(message);
      } else if (type == 'screen_stop') {
        mirrorService.stop();
      } else if (type == 'clipboard') {
        if (!_isSyncPaused) {
          final text = message['text']?.toString();
          if (text != null && _clipboardController != null) {
            _clipboardController!.receiveRemoteClipboard(text);
          }
        }
      } else if (type == 'find_phone') {
        // Both platforms now support native ringing
        await _platform.invokeMethod('ringPhone');
        
        // Still show notification as fallback/visual cue
        if (!Platform.isAndroid) {
          notificationsService.showNotification(
            title: 'Find Device',
            body: 'Someone is looking for this device!',
            category: NotificationCategory.system,
          );
        }
      } else if (type != null && type.startsWith('media_')) {
         if (Platform.isAndroid) {
           final action = type.replaceFirst('media_', '');
           final method = switch (action) {
             'play_pause' => 'mediaPlayPause',
             'next' => 'mediaNext',
             'previous' => 'mediaPrevious',
             'volume_up' => 'volumeUp',
             'volume_down' => 'volumeDown',
             'volume_mute' => 'volumeMute',
             _ => null,
           };
           if (method != null) await _platform.invokeMethod(method);
         }
      } else if (type == 'handoff') {
         final url = message['url']?.toString();
         if (url != null && url.isNotEmpty) {
           if (Platform.isMacOS) {
             await Process.run('open', [url]);
           }
           // Android handoff is handled in main.dart _handleHandoff
         }
      }
    } on PlatformException catch (e) {
      if (e.code == 'ACCESSIBILITY_REQUIRED' && Platform.isMacOS) {
        _throttledAccessibilityWarning();
      }
      // Only log once per 5 seconds to avoid flooding console
      _throttledErrorLog('Platform error ($type): ${e.message}');
    } catch (e) {
      debugPrint('Error handling message ($type): $e');
    }
  }

  void _handleIdentity(Map<String, dynamic> message) {
    final id = message['deviceId']?.toString();
    final name = message['deviceName']?.toString();
    final os = message['os']?.toString() ?? 'unknown';
    final filePort = (message['filePort'] as num?)?.toInt() ?? 5758;
    
    if (id != null && name != null) {
      final existing = pairingService.devices.any((d) => d.deviceId == id);
      if (existing) {
        final dev = pairingService.devices.firstWhere((d) => d.deviceId == id);
        pairingService.addOrUpdateDevice(dev.copyWith(
          lastIp: webSocketService.lastClientAddress ?? '', 
          lastSeenAt: DateTime.now().millisecondsSinceEpoch,
          osType: os,
          batteryLevel: message['battery'] as int?,
          isCharging: message['isCharging'] as bool?,
          filePort: filePort,
        ));
      }

      if (pairingService.isTrusted(id) || _isPairingInProgress) {
        final activeId = pairingService.activeDevice?.deviceId;
        if (activeId != id) {
          if (_isPairingInProgress) {
            pairingService.addOrUpdateDevice(PairedDevice(
              deviceId: id,
              name: name,
              lastIp: webSocketService.lastClientAddress ?? '',
              isTrusted: true,
              osType: os,
              lastSeenAt: DateTime.now().millisecondsSinceEpoch,
              filePort: filePort,
            ));
            _isPairingInProgress = false;
          }
          
          pairingService.setActiveDevice(id);
          _sendIdentity(); 
          _scheduleNotify();
          _updateMacStatusBar();
        }
      }
    }
  }

  Future<void> _onRemoteMirrorRequest(Map<String, dynamic> message, {bool isCamera = false}) async {
    try {
      final renderer = await mirrorService.receiveOffer(message['sdp']?.toString() ?? '', isCamera: isCamera);
      _mirrorRequestController.add({
        'isCamera': isCamera,
        'renderer': renderer,
      });
    } catch (e) {
      debugPrint('Error receiving mirror offer: $e');
    }
  }

  void _startAutoReconnect() {
    if (_reconnectTimer != null) return;
    final active = pairingService.activeDevice;
    if (active == null || active.lastIp.isEmpty) return;
    
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) return;

    final delay = Duration(seconds: (2 * _reconnectAttempts).clamp(2, 30));
    
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      try {
        await webSocketService.connectToPeer(active.lastIp);
        _sendIdentity();
      } catch (e) {
        _startAutoReconnect();
      }
    });
  }

  Future<void> toggleSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    
    switch (key) {
      case 'discovery_enabled': 
        _discoveryEnabled = value; 
        if (value) {
          _startLocalDiscovery();
        } else {
          discoveryService.stop();
        }
        break;
      case 'auto_connect': _autoConnectEnabled = value; break;
      case 'notification_sync_enabled': _notificationSyncEnabled = value; break;
      case 'silent_clipboard': _silentClipboard = value; break;
      case 'labs_mirror_features_enabled': _labsMirrorFeaturesEnabled = value; break;
      case 'labs_mount_finder_enabled': _labsMountFinderEnabled = value; break;
      case 'sync_paused': 
        _isSyncPaused = value;
        _clipboardController?.setSyncPaused(value);
        break;
    }
    notifyListeners();
  }

  Future<void> updateDownloadsPath(String path) async {
    _downloadsPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('downloads_path', path);
    notifyListeners();
  }

  void setBatteryStatus(int level, BatteryState state) {
    if (_batteryLevel == level && _batteryState == state) return;
    _batteryLevel = level;
    _batteryState = state;
    _scheduleNotify();
  }

  void setRemoteStatus(int? battery, bool? isCharging) {
    if (_remoteBattery == battery && _remoteIsCharging == isCharging) return;
    _remoteBattery = battery;
    _remoteIsCharging = isCharging;
    
    final active = pairingService.activeDevice;
    if (active != null) {
      pairingService.addOrUpdateDevice(active.copyWith(
        batteryLevel: battery,
        isCharging: isCharging,
        lastSeenAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    _scheduleNotify();
  }

  void updateLastSync() {
    _lastSyncAt = DateTime.now();
    _scheduleNotify();
  }

  void setFocusMode(bool enabled) {
    _localFocusMode = enabled;
    notifyListeners();
  }

  Future<void> _startLocalDiscovery() async {
    await discoveryService.start(
      deviceId: _deviceId,
      deviceName: _deviceName,
      wsPort: webSocketService.actualPort,
      filePort: fileTransferService.actualPort,
      onPeerFound: (info) {
        addDiscoveryPeer(info);
        
        // Update paired device info if it exists
        final existingDev = pairingService.devices.firstWhere(
          (d) => d.deviceId == info.deviceId,
          orElse: () => PairedDevice(
            deviceId: '', name: '', lastIp: '', isTrusted: false, osType: '', lastSeenAt: 0,
          ),
        );
        if (existingDev.deviceId.isNotEmpty) {
          pairingService.addOrUpdateDevice(existingDev.copyWith(
            lastIp: info.address.address,
            filePort: info.filePort,
            lastSeenAt: DateTime.now().millisecondsSinceEpoch,
          ));
        }

        if (_autoConnectEnabled && pairingService.isTrusted(info.deviceId)) {
          webSocketService.connectToPeer(info.address.address, portOverride: info.wsPort);
        }
      },
    );
  }

  void addDiscoveryPeer(DiscoveryPeerInfo peer) {
    if (!_discoveredPeers.any((p) => p.deviceId == peer.deviceId)) {
      _discoveredPeers.add(peer);
      _scheduleNotify();
    }
  }

  Future<List<String>> getLocalIps() async {
    final interfaces = await NetworkInterface.list();
    return interfaces
        .expand((i) => i.addresses)
        .where((a) => a.type == InternetAddressType.IPv4 && !a.isLoopback)
        .map((a) => a.address)
        .toList();
  }

  void findPhone() {
    webSocketService.send({'type': 'find_phone'});
  }

  Future<void> connectToPeer(String host, {String? targetName, String? targetId}) async {
    if (host.isEmpty) return;
    _isPairingInProgress = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    await webSocketService.connectToPeer(host);
    _sendIdentity();
    BackgroundService.savePeerHost(host);
    
    Future.delayed(const Duration(seconds: 30), () {
      _isPairingInProgress = false;
    });
    
    if (targetId != null && pairingService.isTrusted(targetId)) {
      pairingService.setActiveDevice(targetId);
      notifyListeners();
    }
  }

  Future<void> reconnect() async {
    final active = pairingService.activeDevice;
    if (active != null && active.lastIp.isNotEmpty) {
      _reconnectAttempts = 0;
      await webSocketService.connectToPeer(active.lastIp);
      _sendIdentity();
    }
  }

  void handoffUrl(String url) {
    webSocketService.send({
      'type': 'handoff',
      'url': url,
    });
  }

  Future<void> mountAsUsb() async {
    _isUsbMounted = true;
    notifyListeners();
    _updateMacMountStatus();
    try {
      final success = await _platform.invokeMethod<bool>('mountPhoneInFinder');
      if (success != true) {
        _isUsbMounted = false;
        notifyListeners();
        _updateMacMountStatus();
      }
    } catch (e) {
      _isUsbMounted = false;
      notifyListeners();
      _updateMacMountStatus();
    }
  }

  Future<void> unmountAsUsb() async {
    _isUsbMounted = false;
    notifyListeners();
    _updateMacMountStatus();
    try {
      final success = await _platform.invokeMethod<bool>('unmountPhoneInFinder');
      if (success != true) {
        _isUsbMounted = true;
        notifyListeners();
        _updateMacMountStatus();
      }
    } catch (e) {
      _isUsbMounted = true;
      notifyListeners();
      _updateMacMountStatus();
    }
  }

  Future<void> openFileLocation(String filePath) async {
    try {
      if (Platform.isMacOS) {
        // Use the existing revealInFinder method on macOS
        await _platform.invokeMethod('revealInFinder', {'path': filePath});
      } else if (Platform.isAndroid) {
        // On Android, open the downloads folder
        await _platform.invokeMethod('openDownloadsFolder');
      }
    } catch (e) {
      debugPrint('Error opening file location: $e');
    }
  }

  Future<void> pushFile(String filePath) async {
    final active = pairingService.activeDevice;
    if (active == null) throw Exception('No active device');

    try {
      await fileTransferService.sendFile(
        filePath: filePath,
        host: active.lastIp,
        port: 5758,
        onProgress: (sent, total) {
          _scheduleNotify();
        },
      );
      notificationsService.showNotification(
        title: 'File Sent',
        body: 'Successfully sent ${filePath.split(Platform.pathSeparator).last}',
      );
    } catch (e) {
      notificationsService.showNotification(
        title: 'Send Failed',
        body: 'Error: $e',
      );
      rethrow;
    }
  }
}
