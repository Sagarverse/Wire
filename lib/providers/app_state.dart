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


import '../models/transfer_item.dart';
import 'file_transfer_provider.dart';
import 'package:uuid/uuid.dart';
import '../services/webrtc_p2p_service.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_sync_service.dart';
import 'package:path/path.dart' as p;
import '../services/notifications_service.dart';
import '../controllers/clipboard_controller.dart' show ClipboardController;
import 'package:desktop_multi_window/desktop_multi_window.dart';

class ReceivedFile {
  final String name;
  final String path;
  final int size;
  final DateTime timestamp;

  ReceivedFile({
    required this.name,
    required this.path,
    required this.size,
    required this.timestamp,
  });
}

enum ConnectionMode { local, p2p, auto }

class PairingRequest {
  final String deviceId;
  final String name;
  final String ip;
  final String os;
  final int filePort;

  PairingRequest({
    required this.deviceId,
    required this.name,
    required this.ip,
    required this.os,
    required this.filePort,
  });
}

class AppState extends ChangeNotifier {
  final DiscoveryService discoveryService;
  final PairingService pairingService;
  final AppIdentity identityService;
  final WebSocketService webSocketService;
  final NotificationSyncService notificationSyncService;
  final NotificationsService notificationsService;
  final FileTransferService fileTransferService;
  final WebRTCP2PService webrtcP2PService;


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
    required this.webrtcP2PService,
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
  bool _labsMountFinderEnabled = true;
  bool get labsMountFinderEnabled => _labsMountFinderEnabled;
  bool _p2pEnabled = false;
  bool get p2pEnabled => _p2pEnabled;

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

  // File Transfer
  FileReceiveProgress? _lastReceivedFile;
  FileReceiveProgress? get lastReceivedFile => _lastReceivedFile;

  // P2P File Transfer state
  IOSink? _p2pReceiveSink;
  String? _p2pReceivePath;
  String? _p2pReceiveName;
  int _p2pReceiveTotal = 0;
  int _p2pReceiveCurrent = 0;

  // Remote Status
  int? _remoteBattery;
  int? get remoteBattery => _remoteBattery;
  bool? _remoteIsCharging;
  bool? get remoteIsCharging => _remoteIsCharging;
  int? _pingMs;
  int? get pingMs => _pingMs;
  DateTime? _lastSyncAt;
  DateTime? get lastSyncAt => _lastSyncAt;

  // RPC for Remote Browsing over P2P
  final Map<String, Completer<Map<String, dynamic>>> _pendingRpc = {};

  ConnectionStatus _lastStatus = ConnectionStatus.idle;
  ConnectionStatus get lastStatus => _lastStatus;

  ConnectionMode _connectionMode = ConnectionMode.auto;
  ConnectionMode get connectionMode => _connectionMode;

  PairingRequest? _pendingPairing;
  PairingRequest? get pendingPairing => _pendingPairing;

  String get connectionType {
    if (webSocketService.statusValue == ConnectionStatus.connected) {
      return 'Local Wi-Fi';
    } else if (webrtcP2PService.isConnected) {
      return 'Internet';
    }
    return '';
  }

  String _userName = 'Guest';
  String get userName => _userName;

  String? _userAvatar;
  String? get userAvatar => _userAvatar;

  final List<ReceivedFile> _recentTransfers = [];
  List<ReceivedFile> get recentTransfers => List.unmodifiable(_recentTransfers);

  String? get errorMessage => webSocketService.errorMessage;

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future.microtask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  void sendMessage(Map<String, dynamic> msg) {
    if (webSocketService.statusValue == ConnectionStatus.connected) {
      webSocketService.send(msg);
    } else if (webrtcP2PService.isConnected) {
      webrtcP2PService.sendMessage(jsonEncode(msg));
    } else {
      debugPrint('No active connection to send message: ${msg['type']}');
    }
  }

  Future<void> init() async {
    final initResults = await Future.wait([
      identityService.getOrCreateDeviceId(),
      identityService.getDeviceName(),
      pairingService.init(),
      SharedPreferences.getInstance(),
    ]);

    _deviceId = initResults[0] as String;
    _deviceName = (initResults[1] as String?) ?? 'Unknown Device';
    
    if (pairingService.devices.isNotEmpty) {
      _isFirstRun = false;
    }

    final prefs = initResults[3] as SharedPreferences;
    _discoveryEnabled = prefs.getBool('discovery_enabled') ?? true;
    _autoConnectEnabled = prefs.getBool('auto_connect') ?? true;
    _notificationSyncEnabled = prefs.getBool('notification_sync_enabled') ?? false;
    _silentClipboard = prefs.getBool('silent_clipboard') ?? true;
    _labsMountFinderEnabled = prefs.getBool('labs_mount_finder_enabled') ?? true;
    _isSyncPaused = prefs.getBool('sync_paused') ?? false;
    _p2pEnabled = prefs.getBool('p2p_enabled') ?? false;
    _connectionMode = ConnectionMode.values[(prefs.getInt('connection_mode') ?? 2).clamp(0, 2)];
    _userName = prefs.getString('user_name') ?? 'Guest';
    _userAvatar = prefs.getString('user_avatar');
    _downloadsPath = prefs.getString('downloads_path');

    // Start network services in parallel
    Future.wait([
      webSocketService.startServer(),
      fileTransferService.startServer(),
      webrtcP2PService.initialize(),
    ]).then((_) {
      // Start listening in the background to avoid blocking the main init flow
      webrtcP2PService.startListening(_deviceId).catchError((e) {
        debugPrint('WebRTC Signaling Error: $e');
      });
    }).catchError((e) {
      debugPrint('Service Initialization Error: $e');
    });

    fileTransferService.receiveComplete.listen((progress) {
      _recentTransfers.insert(0, ReceivedFile(
        name: progress.name,
        path: progress.path,
        size: progress.total,
        timestamp: DateTime.now(),
      ));
      if (_recentTransfers.length > 5) _recentTransfers.removeLast();
      _scheduleNotify();
    });

    if (_discoveryEnabled) {
      _startLocalDiscovery();
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
      } else if ((status == ConnectionStatus.disconnected || status == ConnectionStatus.error) && prev == ConnectionStatus.connected) {
        _startAutoReconnect();
      }
      _scheduleNotify();
      _updateMacStatusBar();
    });

    webSocketService.messages.listen(_handleMessage);
    webrtcP2PService.onMessageReceived = (text) {
      try {
        final msg = jsonDecode(text);
        _handleMessage(msg);
      } catch (e) {
        debugPrint('WebRTC message parsing error: $e');
      }
    };

    webrtcP2PService.onBinaryReceived.listen((chunk) async {
       if (_p2pReceiveSink != null) {
         _p2pReceiveCurrent += chunk.length;
         _p2pReceiveSink!.add(chunk);
         
         final progress = FileReceiveProgress(
           name: _p2pReceiveName ?? 'Incoming File',
           received: _p2pReceiveCurrent,
           total: _p2pReceiveTotal,
           path: _p2pReceivePath ?? '',
         );
         
         _lastReceivedFile = progress;
         _scheduleNotify();
       }
    });

    fileTransferService.receiveComplete.listen((progress) async {
      _lastReceivedFile = progress;
      _scheduleNotify();
      
      // On macOS, spawn a dedicated native window for the received file
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
        try {
          final window = await WindowController.create(WindowConfiguration(
            arguments: jsonEncode({
              'name': progress.name,
              'path': progress.path,
              'size': progress.total,
            }),
          ));
          window.show();
        } catch (e) {
          debugPrint('Failed to spawn received file window: $e');
        }
      }

      // Show local notification
      notificationsService.showNotification(
        title: 'File Received',
        body: '${progress.name} has been saved.',
      );
    });

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
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
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          fileTransferService.setAllowedRoots([home]);
        }
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        fileTransferService.setAllowedRoots(['/storage/emulated/0', '/sdcard']);
      }
    } catch (e) {
      debugPrint('Error setting up file server: $e');
    }
  }

  // ── macOS Status Bar Integration ───────────────────────────────────────────

  void _setupStatusBarChannel() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    const statusBarChannel = MethodChannel('wire/statusbar');
    statusBarChannel.setMethodCallHandler((call) async {
      if (call.method == 'findPhone') {
        findPhone();
      }
    });
  }

  void _updateMacStatusBar() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    final connected = _lastStatus == ConnectionStatus.connected &&
        pairingService.activeDevice != null;
    final peerName = pairingService.activeDevice?.name;
    final battery = connected ? (pairingService.activeDevice?.batteryLevel ?? _remoteBattery) : null;

    _platform.invokeMethod('updateStatusBar', {
      'connected': connected,
      'peerName': peerName,
      'battery': battery,
      'pingMs': _pingMs,
    }).catchError((_) {});
  }

  void _updateMacMountStatus() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    _platform.invokeMethod('updateMountStatus', {
      'mounted': _isUsbMounted,
    }).catchError((_) {});
  }

  void _sendIdentity() {
    sendMessage({
      'type': 'identity',
      'deviceId': _deviceId,
      'deviceName': _deviceName,
      'os': (kIsWeb ? false : defaultTargetPlatform == TargetPlatform.android) ? 'android' : ((kIsWeb ? false : defaultTargetPlatform == TargetPlatform.macOS) ? 'macos' : 'unknown'),
      'battery': _batteryLevel,
      'isCharging': _batteryState == BatteryState.charging,
      'filePort': fileTransferService.actualPort,
    });
  }

  void findPhone() {
    sendMessage({
      'type': 'find_phone',
      'from': _deviceId,
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
      } else if (type == 'clipboard') {
        if (!_isSyncPaused) {
          final text = message['text']?.toString();
          if (text != null && _clipboardController != null) {
            _clipboardController!.receiveRemoteClipboard(text);
          }
        }
      } else if (type == 'find_phone') {
        // Only ring if the message is NOT from this device (avoid echo)
        if (message['from'] != _deviceId) {
          // Both platforms now support native ringing
          await _platform.invokeMethod('ringPhone');
        }

        // Still show notification as fallback/visual cue
        if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
          notificationsService.showNotification(
            title: 'Find Device',
            body: 'Someone is looking for this device!',
            category: NotificationCategory.system,
          );
        }
      } else if (type != null && type.startsWith('media_')) {
         if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
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
           if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
             await Process.run('open', [url]);
           }
           // Android handoff is handled in main.dart _handleHandoff
         }
       } else if (type == 'rpc_request') {
          final method = message['method'];
          final id = message['id'];
          final params = message['params'] as Map<String, dynamic>?;
          _handleRpcRequest(id, method, params);
       } else if (type == 'rpc_response') {
          final id = message['id']?.toString();
          if (id != null && _pendingRpc.containsKey(id)) {
            _pendingRpc[id]!.complete(message['result'] as Map<String, dynamic>? ?? {});
            _pendingRpc.remove(id);
          }
       } else if (type == 'p2p_transfer_start') {
           // Provide an empty block or handle it
       }
    } on PlatformException catch (e) {
      if (e.code == 'ACCESSIBILITY_REQUIRED' && !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
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
      // 1. BLOCK SELF-CONNECTION
      if (id == _deviceId) {
        debugPrint('AppState: Blocking self-connection attempt from $id');
        return;
      }

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
        
        if (_isPairingInProgress && !dev.isTrusted) {
           pairingService.setTrusted(id, true);
        }
      } else {
        // Unknown device connected - trigger interactive pairing request
        if (!_isPairingInProgress) {
          _pendingPairing = PairingRequest(
            deviceId: id,
            name: name,
            ip: webSocketService.lastClientAddress ?? '0.0.0.0',
            os: os,
            filePort: filePort,
          );
          notifyListeners();
          return;
        }

        // If manual pairing mode is ON, we auto-trust (Legacy/QR flow)
        pairingService.addOrUpdateDevice(PairedDevice(
          deviceId: id,
          name: name,
          lastIp: webSocketService.lastClientAddress ?? '',
          isTrusted: true, 
          osType: os,
          lastSeenAt: DateTime.now().millisecondsSinceEpoch,
          filePort: filePort,
        ));
      }

      final activeId = pairingService.activeDevice?.deviceId;
      if (activeId != id) {
        pairingService.setTrusted(id, true);
        pairingService.setActiveDevice(id);
        _sendIdentity();
        _scheduleNotify();
        _updateMacStatusBar();
      }
      
      _isPairingInProgress = false;
    }
  }

  void allowPairing() {
    if (_pendingPairing == null) return;
    final req = _pendingPairing!;
    pairingService.addOrUpdateDevice(PairedDevice(
      deviceId: req.deviceId,
      name: req.name,
      lastIp: req.ip,
      isTrusted: true,
      osType: req.os,
      lastSeenAt: DateTime.now().millisecondsSinceEpoch,
      filePort: req.filePort,
    ));
    pairingService.setActiveDevice(req.deviceId);
    _pendingPairing = null;
    _sendIdentity();
    notifyListeners();
  }

  void denyPairing() {
    _pendingPairing = null;
    notifyListeners();
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

  Future<void> setConnectionMode(ConnectionMode mode) async {
    _connectionMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('connection_mode', mode.index);
    reconnect(); // Trigger immediate switch
    notifyListeners();
  }

  Future<void> refreshDiscovery() async {
    discoveryService.stop();
    _discoveredPeers.clear();
    notifyListeners();
    await _startLocalDiscovery();
  }

  Future<void> removeSavedDevice(String deviceId) async {
    await pairingService.removeDevice(deviceId);
    notifyListeners();
  }

  Future<void> updateProfile({String? name, String? avatar}) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) {
      _userName = name;
      await prefs.setString('user_name', name);
    }
    if (avatar != null) {
      _userAvatar = avatar;
      await prefs.setString('user_avatar', avatar);
    }
    notifyListeners();
  }

  Future<void> renameLocalDevice(String newName) async {
    await identityService.setDeviceName(newName);
    _deviceName = newName;
    _sendIdentity(); // Inform active peer
    notifyListeners();
  }

  void setBatteryStatus(int level, BatteryState state) {
    if (_batteryLevel == level && _batteryState == state) return;
    _batteryLevel = level;
    _batteryState = state;
    _scheduleNotify();
    _updateMacStatusBar();
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
        if (info.deviceId == _deviceId) {
          // Ignore self
          return;
        }
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
            lastIp: info.address,
            filePort: info.filePort,
            lastSeenAt: DateTime.now().millisecondsSinceEpoch,
          ));
        }

        if (_autoConnectEnabled && pairingService.isTrusted(info.deviceId)) {
          // Additional safety: never auto-connect to loopback
          if (info.address != '127.0.0.1') {
            webSocketService.connectToPeer(info.address, portOverride: info.wsPort);
          }
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
    if (active == null || active.deviceId == _deviceId) return;

    if (_connectionMode == ConnectionMode.p2p) {
      await webrtcP2PService.initiateConnection(_deviceId, active.deviceId);
      return;
    }

    if (_connectionMode == ConnectionMode.local) {
      if (active.lastIp.isEmpty) return;
      _reconnectAttempts = 0;
      try {
        await webSocketService.connectToPeer(active.lastIp);
        _sendIdentity();
      } catch (_) {
        _startAutoReconnect();
      }
      return;
    }

    // ConnectionMode.auto logic
    if (active.lastIp.isNotEmpty) {
      try {
        debugPrint('AppState: Attempting local auto-reconnect to ${active.lastIp}');
        await webSocketService.connectToPeer(active.lastIp).timeout(const Duration(seconds: 3));
        _sendIdentity();
        return;
      } catch (e) {
        debugPrint('AppState: Local auto-reconnect failed, falling back to P2P/Internet');
      }
    }
    
    // Fallback to P2P
    await webrtcP2PService.initiateConnection(_deviceId, active.deviceId);
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
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
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

  Future<void> requestP2PDownload(String path) async {
    sendMessage({
      'type': 'rpc_request',
      'id': const Uuid().v4(),
      'method': 'download',
      'params': {'path': path},
    });
  }

  Future<void> pushFile(String filePath, {FileTransferProvider? provider}) async {
    final active = pairingService.activeDevice;
    if (active == null) throw Exception('No active device');

    if (webSocketService.statusValue == ConnectionStatus.connected) {
      // Local path: HTTP upload
      try {
        await fileTransferService.sendEntity(
          entityPath: filePath,
          host: active.lastIp,
          port: active.filePort,
          onProgress: (sent, total, currentFile) {
            if (provider != null) {
               // Update provider if available (though sendEntity doesn't use transferId directly here)
            }
            _scheduleNotify();
          },
        );
        notificationsService.showNotification(
          title: 'Transfer Complete',
          body: 'Successfully sent ${p.basename(filePath)}',
        );
      } catch (e) {
        notificationsService.showNotification(
          title: 'Transfer Failed',
          body: 'Error: $e',
        );
        rethrow;
      }
    } else if (webrtcP2PService.isConnected) {
      // Internet path: WebRTC Tunnel
      if (provider == null) {
        throw Exception('FileTransferProvider required for P2P progress tracking');
      }
      await sendFileP2P(filePath, provider);
    } else {
      throw Exception('Device is offline');
    }
  }
  Future<void> _prepareP2PReceive(String name, int size) async {
    _p2pReceiveName = name;
    _p2pReceiveTotal = size;
    _p2pReceiveCurrent = 0;
    
    // Use the logic from FileTransferService to get a safe path
    final dir = await fileTransferService.getReceiveDirectory();
    _p2pReceivePath = p.join(dir.path, name);
    final file = File(_p2pReceivePath!);
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    
    _p2pReceiveSink = file.openWrite();
    _scheduleNotify();
  }

  Future<void> _finalizeP2PReceive() async {
    if (_p2pReceiveSink != null) {
      await _p2pReceiveSink!.flush();
      await _p2pReceiveSink!.close();
      _p2pReceiveSink = null;
      
      final progress = FileReceiveProgress(
        name: _p2pReceiveName!,
        received: _p2pReceiveTotal,
        total: _p2pReceiveTotal,
        path: _p2pReceivePath!,
      );
      
      // Fire the same event as the local server would
      // This triggers the macOS popup and other logic
      fileTransferService.emitReceiveComplete(progress);
      
      _p2pReceiveName = null;
      _p2pReceivePath = null;
      _scheduleNotify();
    }
  }


  Future<Map<String, dynamic>> browseRemote(String? path) async {
    final active = pairingService.activeDevice;
    if (active == null) throw Exception('No active device');

    if (webSocketService.statusValue == ConnectionStatus.connected) {
      // Local path
      return fileTransferService.browseRemote(
        host: active.lastIp,
        port: active.filePort,
        path: path,
      );
    } else if (webrtcP2PService.isConnected) {
      // P2P path
      final rpcId = const Uuid().v4();
      final completer = Completer<Map<String, dynamic>>();
      _pendingRpc[rpcId] = completer;

      sendMessage({
        'type': 'rpc_request',
        'id': rpcId,
        'method': 'browse',
        'params': {'path': path},
      });

      return completer.future.timeout(const Duration(seconds: 15), onTimeout: () {
        _pendingRpc.remove(rpcId);
        throw TimeoutException('Remote browse request timed out');
      });
    } else {
      throw Exception('Device is offline');
    }
  }

  void _handleRpcRequest(String? id, String? method, Map<String, dynamic>? params) async {
    if (id == null) return;
    try {
      if (method == 'browse') {
        final path = params?['path']?.toString();
        final result = await fileTransferService.browseRemote(
          host: 'localhost',
          port: fileTransferService.actualPort,
          path: path,
        );
        sendMessage({
          'type': 'rpc_response',
          'id': id,
          'result': result,
        });
      } else if (method == 'download') {
        final path = params?['path']?.toString();
        if (path != null) {
          // We need a reference to FileTransferProvider to track this outgoing send
          // For now, we search for it or pass it.
          // In a real app, I'd have a global registry. For now, I'll use a hack or just send.
          // Let's assume the user is okay with background sending.
          sendFileP2P(path, null); 
        }
      }
    } catch (e) {
      debugPrint('RPC error ($method): $e');
    }
  }

  Future<void> sendFileP2P(String path, FileTransferProvider? provider) async {
    final file = File(path);
    if (!await file.exists()) return;
    
    final name = p.basename(path);
    final size = await file.length();
    final transferId = DateTime.now().millisecondsSinceEpoch.toString();

    provider?.addTransfer(TransferItem(
      id: transferId,
      name: name,
      total: size,
      direction: 'send',
      path: path,
      status: 'sending',
      bytesTransferred: 0,
      progress: 0.0,
      startTime: DateTime.now(),
    ));
    
    sendMessage({
      'type': 'p2p_transfer_start',
      'name': name,
      'size': size,
    });
    
    // Small delay to allow receiver to prepare
    await Future.delayed(const Duration(milliseconds: 200));
    
    final stream = file.openRead();
    var sent = 0;
    await for (final chunk in stream) {
      webrtcP2PService.sendBinary(Uint8List.fromList(chunk));
      sent += chunk.length;
      provider?.updateTransferProgress(transferId, sent / size, sent);
      
      // In a real high-throughput scenario, we'd wait for an ACK or throttle
      // But WebRTC data channel handles some flow control
      await Future.delayed(const Duration(milliseconds: 5));
    }
    
    sendMessage({'type': 'p2p_transfer_end'});
    provider?.updateTransferStatus(transferId, 'complete');
    _scheduleNotify();
  }
}
