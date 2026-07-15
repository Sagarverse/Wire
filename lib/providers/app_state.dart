import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ConnectionState;
import 'package:path_provider/path_provider.dart';
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
import 'package:window_manager/window_manager.dart';

import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_sync_service.dart';
import 'package:path/path.dart' as p;
import '../services/notifications_service.dart';
import '../controllers/clipboard_controller.dart' show ClipboardController;
import '../services/history_service.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

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
enum ConnectionStatus { connected, syncing, connecting, disconnected, error, idle }

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
  final HistoryService historyService;


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
    required this.historyService,
  }) {
    _startPeerPruner();
  }

  bool _isFirstRun = true;
  bool get isFirstRun => _isFirstRun;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

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

  bool isTrusted(String id) => pairingService.isTrusted(id);

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

  List<String> _localIps = [];
  bool _isLocalAddress(String host) {
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
    return _localIps.contains(host);
  }

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

  bool _modeMismatch = false;
  bool get modeMismatch => _modeMismatch;

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

  ConnectionStatus get connectionStatus {
    final isPeerConnected = pairingService.activeDevice != null;
    final isP2PConnected = webrtcP2PService.isConnected;
    
    // A device is only truly "Connected" if the signaling bridge or P2P tunnel is UP
    final isBridgeUp = webSocketService.statusValue == ConnectionStatus.connected || isP2PConnected;
    
    if (!isPeerConnected || !isBridgeUp) {
      // If we are currently trying to connect, show connecting
      if (webSocketService.statusValue == ConnectionStatus.connecting || 
          webSocketService.statusValue == ConnectionStatus.syncing) {
        return ConnectionStatus.connecting;
      }
      return ConnectionStatus.disconnected;
    }
    
    // Determining if we are actively moving data
    final isActive = isSyncing || webrtcP2PService.isTransferring;
    
    if (isActive) return ConnectionStatus.syncing;
    return ConnectionStatus.connected;
  }

  // RPC for Remote Browsing over P2P
  final Map<String, Completer<Map<String, dynamic>>> _pendingRpc = {};

  ConnectionStatus _localStatus = ConnectionStatus.disconnected;
  ConnectionStatus _p2pStatus = ConnectionStatus.idle;
  
  ConnectionStatus get lastStatus {
    if (_connectionMode == ConnectionMode.local) return _localStatus;
    if (_connectionMode == ConnectionMode.p2p) return _p2pStatus;
    
    // Auto mode: show connected if either is connected
    if (_localStatus == ConnectionStatus.connected || _p2pStatus == ConnectionStatus.connected) {
      return ConnectionStatus.connected;
    }
    if (_localStatus == ConnectionStatus.connecting || _p2pStatus == ConnectionStatus.connecting) {
      return ConnectionStatus.connecting;
    }
    if (_localStatus == ConnectionStatus.error || _p2pStatus == ConnectionStatus.error) {
       return ConnectionStatus.error;
    }
    return ConnectionStatus.disconnected;
  }

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

  bool get isSyncing => fileTransferService.isTransferring || webrtcP2PService.isTransferring;

  bool _launchAtStartupEnabled = false;
  bool get launchAtStartupEnabled => _launchAtStartupEnabled;

  bool _biometricLockEnabled = false;
  bool get biometricLockEnabled => _biometricLockEnabled;
  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  final LocalAuthentication _auth = LocalAuthentication();

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

  void _startPeerPruner() {
    Timer.periodic(const Duration(seconds: 5), (timer) {
      final now = DateTime.now();
      final beforeCount = _discoveredPeers.length;
      _discoveredPeers.removeWhere((p) => 
        now.difference(p.lastSeen).inSeconds > 15
      );
      if (_discoveredPeers.length != beforeCount) {
        _scheduleNotify();
      }
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
    debugPrint('AppState: My Device ID: $_deviceId');
    debugPrint('AppState: My Device Name: $_deviceName');
    
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
    _launchAtStartupEnabled = prefs.getBool('launch_at_startup') ?? false;
    _connectionMode = ConnectionMode.values[(prefs.getInt('connection_mode') ?? 2).clamp(0, 2)];
    _userName = prefs.getString('user_name') ?? 'Guest';
    _downloadsPath = prefs.getString('downloads_path');
    _biometricLockEnabled = prefs.getBool('biometric_lock_enabled') ?? false;

    // Pre-calculate local IPs for self-connection filtering
    await _updateLocalIps();

    // Load recent transfers from history
    try {
      final history = await historyService.getTransferHistory();
      _recentTransfers.clear();
      _recentTransfers.addAll(history.take(5).map((t) => ReceivedFile(
        name: t.name,
        path: t.path,
        size: t.total,
        timestamp: t.startTime ?? DateTime.now(),
      )));
    } catch (e) {
      debugPrint('AppState: Failed to load history: $e');
    }

    // Start network services based on strict isolation mode
    final List<Future> initializers = [];
    if (_connectionMode == ConnectionMode.local || _connectionMode == ConnectionMode.auto) {
      initializers.add(webSocketService.startServer());
      initializers.add(fileTransferService.startServer());
    }
    if (_connectionMode == ConnectionMode.p2p || _connectionMode == ConnectionMode.auto) {
      initializers.add(webrtcP2PService.initialize());
    }

    Future.wait(initializers).then((_) {
      if (_connectionMode == ConnectionMode.p2p || _connectionMode == ConnectionMode.auto) {
        webrtcP2PService.startListening(_deviceId).catchError((e) {
          debugPrint('WebRTC Signaling Error: $e');
        });
      }
    }).catchError((e) {
      debugPrint('Service Initialization Error: $e');
    });

    // Single unified listener for file receive completion
    fileTransferService.receiveComplete.listen((progress) async {
      // Update recent transfers
      _recentTransfers.insert(0, ReceivedFile(
        name: progress.name,
        path: progress.path,
        size: progress.total,
        timestamp: DateTime.now(),
      ));
      if (_recentTransfers.length > 5) _recentTransfers.removeLast();
      
      // Track last received file for popup UI
      _lastReceivedFile = progress;
      
      // Persist to history
      await historyService.saveTransfer(TransferItem(
        id: progress.path,
        name: progress.name,
        total: progress.total,
        direction: 'receive',
        path: progress.path,
        status: 'complete',
        progress: 1.0,
        bytesTransferred: progress.total,
        startTime: DateTime.now(),
      ));

      updateLastSync();
      
      // On macOS, spawn a dedicated native window for the received file
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
        try {
          final window = await WindowController.create(WindowConfiguration(
            arguments: jsonEncode({
              'type': 'received_file',
              'name': progress.name,
              'path': progress.path,
              'size': progress.total,
              'sender': pairingService.activeDevice?.name ?? 'Nearby Device',
            }),
          ));
          window.show();
        } catch (e) {
          debugPrint('Failed to spawn received file window: $e');
        }
      }
      
      // Show system notification
      await notificationsService.showNotification(
        title: 'File received',
        body: '${progress.name} saved to Downloads',
        payload: 'file:${progress.path}',
      );

      _scheduleNotify();
    });

    fileTransferService.receiveProgress.listen((progress) {
       final service = FlutterBackgroundService();
       service.invoke('updateProgress', {
         'content': 'Receiving ${progress.name}...',
         'progress': progress.received,
         'total': progress.total,
       });
    });

    if (_discoveryEnabled) {
      _startLocalDiscovery();
    }

    notifyListeners();

    webSocketService.status.listen((status) {
      final prev = _localStatus;
      _localStatus = status;
      _scheduleNotify();
      _updateMacStatusBar();
      
      // Trigger auto-reconnect when WebSocket disconnects unexpectedly
      if (status == ConnectionStatus.disconnected && 
          prev == ConnectionStatus.connected &&
          _autoConnectEnabled &&
          pairingService.activeDevice != null) {
        _startAutoReconnect();
      }
    });

    webrtcP2PService.onConnectionStateChange = (state) {
      final prev = _p2pStatus;
      _p2pStatus = switch (state) {
        ConnectionState.active || ConnectionState.done => ConnectionStatus.connected,
        ConnectionState.waiting => ConnectionStatus.connecting,
        _ => ConnectionStatus.disconnected,
      };
      
      if (_p2pStatus == ConnectionStatus.connected && prev != ConnectionStatus.connected) {
         _sendIdentity();
      }
      
      _scheduleNotify();
      _updateMacStatusBar();
    };

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

    // NOTE: receiveComplete listener is unified above — no duplicate here

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
    
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> initiateConnection(DiscoveryPeerInfo peer) async {
    try {
      _localStatus = ConnectionStatus.connecting;
      _p2pStatus = ConnectionStatus.connecting;
      _scheduleNotify();
      
      if (_connectionMode == ConnectionMode.p2p) {
        // Force P2P handshake
        await webrtcP2PService.initiateConnection(_deviceId, peer.deviceId).timeout(const Duration(seconds: 10));
      } else {
        // Try local WebSocket first
        await webSocketService.connectToPeer(peer.address).timeout(const Duration(seconds: 8));
      }
    } catch (e) {
      debugPrint('AppState: Connection failure: $e');
      _localStatus = ConnectionStatus.error;
      _p2pStatus = ConnectionStatus.error;
      _scheduleNotify();
      // Don't rethrow - we want to handle it gracefully in the UI
    }
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
    // Legacy status bar update replaced by comprehensive TrayService
    // Still kept for any native plugins that might depend on it
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    final connected = lastStatus == ConnectionStatus.connected &&
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

  Map<String, dynamic> getTrayState() {
    return {
      'mode': _connectionMode.name,
      'paused': _isSyncPaused,
      'discovery': _discoveryEnabled,
      'clipboardEnabled': !_isSyncPaused,
      'focusMode': _localFocusMode,
      'connected': lastStatus == ConnectionStatus.connected && pairingService.activeDevice != null,
      'trusted': pairingService.activeDevice?.isTrusted ?? false,
      'isSyncing': fileTransferService.isTransferring || webrtcP2PService.isTransferring,
      'peerName': pairingService.activeDevice?.name,
      'battery': pairingService.activeDevice?.batteryLevel ?? _remoteBattery,
      'batteryCharging': pairingService.activeDevice?.isCharging ?? _remoteIsCharging,
      'nearbyPeers': _discoveredPeers.map((p) => {
        'deviceId': p.deviceId,
        'deviceName': p.deviceName,
        'mode': p.mode,
        'address': p.address,
        'wsPort': p.wsPort,
        'filePort': p.filePort,
        'isTrusted': pairingService.isTrusted(p.deviceId),
      }).toList(),
      'clipboardHistory': _clipboardController?.history.map((e) => e.text).toList() ?? [],
      'recentTransfers': _recentTransfers.map((t) => {
        'name': t.name,
        'path': t.path,
      }).toList(),
    };
  }

  void handleTrayAction(String method, dynamic args) {
    switch (method) {
      case 'set_mode':
        setConnectionMode(ConnectionMode.values.firstWhere((e) => e.name == args));
        break;
      case 'toggle_discovery':
        toggleSetting('discovery_enabled', args as bool);
        break;
      case 'toggle_clipboard':
        toggleSetting('sync_paused', !(args as bool));
        break;
      case 'toggle_focus':
        setFocusMode(args as bool);
        break;
      case 'toggle_pause':
        toggleSetting('sync_paused', args as bool);
        break;
      case 'pair_device':
        if (args is Map) {
           // Direct pairing from tray
           final peer = DiscoveryPeerInfo(
             address: args['address'],
             deviceId: args['deviceId'],
             deviceName: args['deviceName'],
             wsPort: args['wsPort'],
             filePort: args['filePort'],
             mode: args['mode'],
             lastSeen: DateTime.now(),
           );
           initiateConnection(peer);
        }
        break;
      case 'find_phone':
        findPhone();
        break;
      case 'copy_to_clipboard':
        Clipboard.setData(ClipboardData(text: args.toString()));
        notificationsService.showNotification(title: 'Copied', body: 'Clipboard item copied locally');
        break;
      case 'clear_clipboard':
        _clipboardController?.clearHistory();
        break;
      case 'open_file':
        if (args is String) {
          if (Platform.isMacOS) {
            Process.run('open', [args]);
          }
        }
        break;
      case 'show_window':
        windowManager.show();
        break;
      case 'manual_pairing':
        windowManager.show();
        // The pairing logic is handled in the UI when the window shows,
        // but we could set an internal flag here if we wanted to auto-open the dialog.
        break;
      case 'open_downloads':
        if (_downloadsPath != null) {
          openFileLocation(_downloadsPath!);
        } else {
          // Fallback to default downloads directory if not set
          getDownloadsDirectory().then((dir) {
            if (dir != null) openFileLocation(dir.path);
          });
        }
        break;
      case 'trust':
        if (args is String) trustDevice(args);
        break;
      case 'untrust':
        if (args is String) untrustDevice(args);
        break;
      case 'quit':
        exit(0);
    }
  }

  Future<void> trustDevice(String id) async {
    await pairingService.setTrusted(id, true);
    _scheduleNotify();
  }

  Future<void> untrustDevice(String id) async {
    await pairingService.setTrusted(id, false);
    _scheduleNotify();
  }

  void _updateMacMountStatus() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    _platform.invokeMethod('updateMountStatus', {
      'mounted': _isUsbMounted,
    }).catchError((_) {});
  }

  void _sendIdentity() {
    final Map<String, dynamic> payload = {
      'type': 'identity',
      'deviceId': _deviceId,
      'deviceName': _deviceName,
      'os': (kIsWeb ? false : defaultTargetPlatform == TargetPlatform.android) ? 'android' : ((kIsWeb ? false : defaultTargetPlatform == TargetPlatform.macOS) ? 'macos' : 'unknown'),
      'battery': _batteryLevel,
      'isCharging': _batteryState == BatteryState.charging,
      'filePort': fileTransferService.actualPort,
      'mode': _connectionMode.name,
    };

    // Include signaling key for trusted peers
    final active = pairingService.activeDevice;
    if (active != null) {
      if (active.signalingKey != null) {
        payload['sigKey'] = active.signalingKey;
      } else {
        // Generate a new one if not exists
        final newKey = const Uuid().v4();
        payload['sigKey'] = newKey;
      }
    }
    sendMessage(payload);
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
        if (_notificationSyncEnabled) {
          final title = message['title']?.toString() ?? 'Notification';
          final body = message['body']?.toString() ?? '';
          notificationsService.showNotification(
            title: title,
            body: body,
            category: NotificationCategory.system,
          );
        }
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
          final name = message['name']?.toString() ?? 'Incoming File';
          final size = (message['size'] as num?)?.toInt() ?? 0;
          await _prepareP2PReceive(name, size);
      } else if (type == 'p2p_transfer_end') {
          await _finalizeP2PReceive();
      } else if (type == 'unpair') {
          debugPrint('AppState: Peer unpairing. Terminating session.');
          await disconnect();
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
          signalingKey: message['sigKey']?.toString(),
        ));
        
        final remoteMode = message['mode']?.toString() ?? 'auto';
        if (!_isModeCompatible(remoteMode)) {
           debugPrint('AppState: Mode mismatch with $id (Local: ${_connectionMode.name}, Remote: $remoteMode). Disconnecting.');
           _modeMismatch = true;
           if (webSocketService.statusValue == ConnectionStatus.connected) webSocketService.disconnect();
           if (webrtcP2PService.isConnected) webrtcP2PService.disconnect();
           _scheduleNotify();
           return;
        }
        _modeMismatch = false;

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
    
    // Check if we need to immediately switch based on mode
    reconnect();
    
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
    
    debugPrint('AppState: Mode changed to ${mode.name}.');

    if (mode == ConnectionMode.p2p) {
      // P2P only: shut down local services, use only WebRTC
      await webSocketService.stopServer();
      webSocketService.disconnect(); 
      await fileTransferService.stopServer();
      await webrtcP2PService.initialize(); 
      if (_deviceId.isNotEmpty) {
        await webrtcP2PService.startListening(_deviceId);
      }
    } else if (mode == ConnectionMode.local) {
      // Local only: shut down P2P, use only WebSocket
      webrtcP2PService.disconnect();
      if (!webSocketService.isServerRunning) await webSocketService.startServer();
      if (!fileTransferService.isServerRunning) await fileTransferService.startServer();
    } else {
      // Auto mode: ensure BOTH local and P2P are available
      if (!webSocketService.isServerRunning) await webSocketService.startServer();
      if (!fileTransferService.isServerRunning) await fileTransferService.startServer();
      await webrtcP2PService.initialize();
      if (_deviceId.isNotEmpty) {
        await webrtcP2PService.startListening(_deviceId);
      }
    }
    
    // Refresh discovery broadcast with the new mode
    if (_discoveryEnabled) {
      _startLocalDiscovery();
    }
    
    reconnect(); // Trigger immediate switch
    notifyListeners();
  }

  bool _isModeCompatible(String remoteModeStr) {
    // If either is Auto, they are compatible
    if (_connectionMode == ConnectionMode.auto || remoteModeStr == 'auto') return true;
    
    // Otherwise, they MUST match exactly for strict isolation
    return _connectionMode.name == remoteModeStr;
  }

  Future<void> refreshDiscovery() async {
    discoveryService.stop();
    _discoveredPeers.clear();
    notifyListeners();
    await _startLocalDiscovery();
  }

  Future<void> removeSavedDevice(String deviceId) async {
    final isActive = pairingService.activeDevice?.deviceId == deviceId;
    if (isActive) {
      debugPrint('AppState: Active device removed, forcing synchronized unpair');
      sendMessage({'type': 'unpair', 'from': _deviceId});
      await disconnect();
    }
    await pairingService.removeDevice(deviceId);
    notifyListeners();
  }

  Future<void> clearAllPairings() async {
    debugPrint('AppState: Clearing all pairings');
    sendMessage({'type': 'unpair', 'from': _deviceId});
    await disconnect();
    for (final device in List.from(pairingService.devices)) {
      await pairingService.removeDevice(device.deviceId);
    }
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
      currentMode: _connectionMode.name,
      onPeerFound: (info) {
        if (info.deviceId == _deviceId) return;
        
        // Filter out incompatible peers from discovery list
        if (!_isModeCompatible(info.mode)) return;

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
          if (!_isLocalAddress(info.address) && _connectionMode != ConnectionMode.p2p) {
            connectToPeer(info.address, targetId: info.deviceId, targetName: info.deviceName);
          }
        }
      },
    );
  }

  void addDiscoveryPeer(DiscoveryPeerInfo peer) {
    final index = _discoveredPeers.indexWhere((p) => p.deviceId == peer.deviceId);
    if (index != -1) {
      _discoveredPeers[index] = peer;
    } else {
      _discoveredPeers.add(peer);
    }
    _scheduleNotify();
  }

  Future<void> _updateLocalIps() async {
    try {
      _localIps = await getLocalIps();
      debugPrint('AppState: Discovered Local IPs: $_localIps');
    } catch (_) {
      _localIps = [];
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


  Future<void> connectToPeer(dynamic hostOrHosts, {String? targetName, String? targetId}) async {
    if (!_isInitialized) return;
    if (targetId == _deviceId && _deviceId.isNotEmpty) {
      debugPrint('AppState: Ignoring self-connection request for deviceId: $_deviceId');
      return;
    }
    
    final List<String> hosts = (hostOrHosts is List) 
        ? hostOrHosts.map((e) => e.toString()).toList() 
        : [hostOrHosts.toString()];
    
    if (hosts.isEmpty || hosts.every((h) => h.isEmpty)) return;
    
    _isPairingInProgress = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    notifyListeners(); // Show connecting state

    bool success = false;
    String? successfulHost;

    for (final host in hosts) {
      if (host.isEmpty || _isLocalAddress(host)) {
        if (host.isNotEmpty) debugPrint('AppState: Skipping self-connection attempt to local address: $host');
        continue;
      }
      try {
        debugPrint('AppState: Attempting connection to $host...');
        await webSocketService.connectToPeer(host).timeout(const Duration(seconds: 4));
        success = true;
        successfulHost = host;
        break;
      } catch (e) {
        debugPrint('AppState: Connection to $host failed: $e');
      }
    }
    
    if (success && successfulHost != null) {
      _sendIdentity();
      BackgroundService.savePeerHost(successfulHost);
      
      if (targetId != null) {
        final existing = pairingService.devices.any((d) => d.deviceId == targetId);
        if (existing) {
          await pairingService.setActiveDevice(targetId);
        }
      }
    } else {
      debugPrint('AppState: All connection attempts failed.');
      // Ensure we don't stay in "connecting" state
      await webSocketService.disconnectClient();
    }

    _isPairingInProgress = false;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await webSocketService.disconnect();
    await pairingService.setActiveDevice(null);
    _localStatus = ConnectionStatus.disconnected;
    _p2pStatus = ConnectionStatus.disconnected;
    notifyListeners();
  }

  Future<void> reconnect() async {
    if (!_isInitialized) return;
    final active = pairingService.activeDevice;
    if (active == null || (active.deviceId == _deviceId && _deviceId.isNotEmpty)) return;

    // Only attempt automatic reconnection for trusted devices
    if (!pairingService.isTrusted(active.deviceId)) {
      debugPrint('AppState: Auto-reconnect skipped for untrusted device: ${active.name}');
      _scheduleNotify();
      return;
    }

    if (webSocketService.statusValue == ConnectionStatus.connected) return;
    if (webSocketService.statusValue == ConnectionStatus.connecting && _reconnectAttempts > 0) return;

    _reconnectAttempts++;
    if (_reconnectAttempts > 8) {
      debugPrint('AppState: Max reconnection attempts reached. Stopping auto-reconnect.');
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      await webSocketService.disconnectClient();
      notifyListeners();
      return;
    }

    debugPrint('AppState: Reconnecting to ${active.name} (ID: ${active.deviceId}, IP: ${active.lastIp}) (Attempt $_reconnectAttempts)...');
    
    bool connectionSuccess = false;
    
    // 1. Try Local Link if available
    if (active.lastIp.isNotEmpty && !_isLocalAddress(active.lastIp)) {
      try {
        await webSocketService.connectToPeer(active.lastIp).timeout(const Duration(seconds: 4));
        connectionSuccess = true;
      } catch (e) {
        debugPrint('AppState: Local reconnect attempt failed: $e');
      }
    }

    // 2. Fallback to P2P if enabled and local failed
    if (!connectionSuccess && _p2pEnabled) {
      debugPrint('AppState: Local failed, trying P2P/Internet fallback...');
      await webrtcP2PService.initiateConnection(_deviceId, active.deviceId);
      // P2P is async/event-driven, we don't await success here.
      // But we prevent the reconnect loop from firing too fast.
    }

    if (connectionSuccess) {
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _sendIdentity();
    } else {
      if (_reconnectTimer == null && _autoConnectEnabled) {
        // Backoff: wait longer between attempts as they fail
        final delay = Duration(seconds: (10 + (_reconnectAttempts * 5)).clamp(10, 60));
        _reconnectTimer = Timer(delay, () {
          _reconnectTimer = null;
          reconnect();
        });
      }
      
      // If we failed after several tries, clear the "connecting" state so the UI isn't stuck
      if (_reconnectAttempts >= 3 && !webrtcP2PService.isConnecting) {
        await webSocketService.disconnectClient();
      }
    }
    
    notifyListeners();
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

  Future<void> deleteReceivedFile(String filePath, {String? transferId}) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('AppState: File deleted from disk: $filePath');
      }

      if (transferId != null) {
        await historyService.removeTransfer(transferId);
      } else {
        // Fallback: search for entry by path
        final history = await historyService.getTransferHistory();
        final entry = history.firstWhere((t) => t.path == filePath, orElse: () => TransferItem(id: '', name: '', total: 0, direction: '', path: '', status: '', progress: 0));
        if (entry.id.isNotEmpty) {
          await historyService.removeTransfer(entry.id);
        }
      }

      _recentTransfers.removeWhere((t) => t.path == filePath);
      _scheduleNotify();
      notificationsService.showNotification(title: 'File Deleted', body: 'The file has been permanently removed.');
    } catch (e) {
      debugPrint('Error deleting file: $e');
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

  Future<void> pushFiles(List<String> filePaths, {FileTransferProvider? provider}) async {
    final active = pairingService.activeDevice;
    if (active == null) throw Exception('No active device');

    if (webSocketService.statusValue == ConnectionStatus.connected) {
      // Local path: HTTP upload
      try {
        await fileTransferService.sendEntities(
          paths: filePaths,
          host: active.lastIp,
          port: active.filePort,
          onProgress: (sent, total, currentFile) {
            final service = FlutterBackgroundService();
            service.invoke('updateProgress', {
              'content': 'Sending files...',
              'progress': sent,
              'total': total,
            });
            _scheduleNotify();
          },
        );
        
        final service = FlutterBackgroundService();
        service.invoke('updateProgress', {
          'content': 'Transfer Complete',
          'progress': 100,
          'total': 100,
        });

        notificationsService.showNotification(
          title: 'Transfer Complete',
          body: 'Successfully sent ${filePaths.length} items',
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
      for (final path in filePaths) {
         await sendFileP2P(path, provider);
      }
    } else {
      throw Exception('Device is offline');
    }
  }

  // Alias for backward compatibility
  Future<void> pushFile(String filePath, {FileTransferProvider? provider}) => 
    pushFiles([filePath], provider: provider);
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
    
    final service = FlutterBackgroundService();
    service.invoke('updateProgress', {
      'content': 'Sending $name via Internet...',
      'progress': 0,
      'total': size,
    });
    
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
      
      service.invoke('updateProgress', {
         'content': 'Sending $name...',
         'progress': sent,
         'total': size,
      });

      // In a real high-throughput scenario, we'd wait for an ACK or throttle
      // But WebRTC data channel handles some flow control
      await Future.delayed(const Duration(milliseconds: 5));
    }
    
    sendMessage({'type': 'p2p_transfer_end'});
    provider?.updateTransferStatus(transferId, 'complete');
    
    service.invoke('updateProgress', {
       'content': 'Transfer Complete',
       'progress': 100,
       'total': 100,
    });
    _scheduleNotify();
  }

  Future<void> toggleLaunchAtStartup(bool value) async {
    _launchAtStartupEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('launch_at_startup', value);
    
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      if (value) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    }
    notifyListeners();
  }

  Future<void> setBiometricLock(bool value) async {
    _biometricLockEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_lock_enabled', value);
    notifyListeners();
  }

  Future<bool> authenticate() async {
    if (!_biometricLockEnabled) {
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }

    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (!canAuthenticate) {
        _isAuthenticated = true; // Fallback if not supported
        notifyListeners();
        return true;
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Please authenticate to access Wire Sync',
      );

      _isAuthenticated = didAuthenticate;
      notifyListeners();
      return _isAuthenticated;
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return false;
    }
  }

  Future<void> clearHistory() async {
    try {
      await historyService.clearTransferHistory();
      _recentTransfers.clear();
      _lastReceivedFile = null;
      notifyListeners();
    } catch (e) {
      debugPrint('AppState: Error clearing history: $e');
    }
  }

  void logout() {
    _isAuthenticated = false;
    notifyListeners();
  }
}
