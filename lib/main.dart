import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:battery_plus/battery_plus.dart';
import 'services/app_identity.dart';
import 'services/background_service.dart';
import 'services/clipboard_service.dart';
import 'services/discovery_service.dart';
import 'services/file_transfer_service.dart';
import 'services/pairing_service.dart';
import 'ui/pages/device_pairing_page.dart';
import 'services/notifications_service.dart';
import 'services/network_info_service.dart';
import 'services/permissions_service.dart';
import 'services/share_intent_service.dart';
import 'services/notification_sync_service.dart';
import 'services/tray_service.dart';
import 'services/websocket_service.dart';
import 'services/handoff_service.dart';
import 'services/focus_mode_service.dart';
import 'services/floating_dock_service.dart';
import 'services/performance_service.dart';
import 'config/optimization_config.dart';
import 'widgets/liquid_background.dart';
import 'models/transfer_item.dart';
import 'models/clipboard_item.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/files_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/remote_file_manager_page.dart';
import 'ui/widgets/glass_card.dart';
import 'services/history_service.dart';
import 'services/screen_mirror_service.dart';
import 'ui/pages/screen_mirror_page.dart';
import 'ui/pages/trackpad_page.dart';
import 'ui/pages/camera_viewer_page.dart';
import 'ui/pages/sms_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/pomodoro_timer.dart';
import 'ui/widgets/wire_snackbar.dart';
import 'ui/widgets/speed_dial_fab.dart';
import 'ui/widgets/liquid_glass_dock.dart';

class _OpenQuickActionsIntent extends Intent {
  const _OpenQuickActionsIntent();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppTheme.initThemeMode();
  runApp(const WireApp());
}

class WireApp extends StatefulWidget {
  const WireApp({super.key});

  @override
  State<WireApp> createState() => _WireAppState();
}

class _WireAppState extends State<WireApp> {
  @override
  void dispose() {
    AppTheme.themeModeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Wire Sync',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: const WireHomePage(),
        );
      },
    );
  }
}

class WireHomePage extends StatefulWidget {
  const WireHomePage({super.key});

  @override
  State<WireHomePage> createState() => _WireHomePageState();
}

class _WireHomePageState extends State<WireHomePage> {
  static const _platformChannel = MethodChannel('wire/platform');
  static const _wsPort = 5757;
  static const _filePort = 5758;

  final _identity = AppIdentity();
  final _permissionsService = PermissionsService();
  final NotificationsService _notificationsService = NotificationsService();
  final HistoryService _historyService = HistoryService();
  final _clipboardService = ClipboardService(_platformChannel);
  final _webSocketService = WebSocketService(port: _wsPort);
  final _fileTransferService = FileTransferService(port: _filePort);
  final _discoveryService = DiscoveryService();
  final _shareIntentService = ShareIntentService();
  final _notificationSyncService = NotificationSyncService();
  final _trayService = TrayService();
  final _networkInfoService = NetworkInfoService();
  late final ScreenMirrorService _screenMirrorService;
  final _peerController = TextEditingController();
  final _textController = TextEditingController();
  final _incomingTextController = TextEditingController();
  final _handoffService = HandoffService();
  final _focusModeService = FocusModeService();
  final _floatingDockService = FloatingDockService();
  final _performanceService = PerformanceService();
  bool _localFocusMode = false;
  final List<Map<String, String>> _studyLinks = [];

  String _deviceId = '';
  final PairingService _pairingService = PairingService();
  final List<DiscoveryPeerInfo> _discoveredPeers = [];
  String get _peerHost => _pairingService.activeDevice?.lastIp ?? '';
  List<String> _localIps = [];
  bool _discoveryEnabled = true;
  bool _autoConnectEnabled = true;
  int _currentIndex = 0;
  final List<ClipboardItem> _clipboardHistory = [];
  final List<Map<String, dynamic>> _notificationHistory = [];
  final List<TransferItem> _transfers = [];
  static const int _maxClipboardItems = 40;
  static const int _maxTransferItems = 40;

  final Map<String, String> _sentFilePaths = {};
  bool _syncPaused = false;
  bool _silentClipboard =
      true; // like Apple Universal Clipboard: silent by default
  bool _clipboardHistoryEnabled = true;
  bool _notificationSyncEnabled = false;
  bool _transferHistoryEnabled = true;
  bool _labsMirrorFeaturesEnabled = true;
  bool _labsStudentHubEnabled = true;
  bool _labsMountFinderEnabled = true;
  bool _dragActive = false;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  StreamSubscription<List<String>>? _shareSub;
  StreamSubscription<FileReceiveProgress>? _receiveProgressSub;
  StreamSubscription<String>? _clipboardSub;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  final _backgroundService = BackgroundService();
  final _battery = Battery();
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.unknown;
  int _remoteFilePort = _filePort;
  bool _clipboardStarted = false;
  bool _shareStarted = false;
  String _lastClipboardSentText = '';
  // Remote device status
  int? _remoteBattery;
  bool? _remoteIsCharging;
  int? _pingMs;
  DateTime? _pingSentAt;
  bool _isSyncing = false;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();

    _screenMirrorService = ScreenMirrorService(
      deviceId: '', // Will be updated after _init() populates _deviceId
      onSendSignal: (msg) => _webSocketService.send(msg),
    );
    _handoffService.onHandoffReceived.listen(_handleHandoff);
    _floatingDockService.addListener(_onFloatingDockEvent);
    _focusModeService.onFocusStateChanged.listen((enabled) {
      setState(() => _localFocusMode = enabled);
      _notificationsService.setFocusMode(
        enabled,
      ); // suppress notifs in focus mode
      _webSocketService.send({
        'type': 'focus_mode',
        'enabled': enabled,
        'from': _deviceId,
      });
    });
    _textController.addListener(_handleLiveTypingChange);
    _init();
  }

  void _handleHandoff(String url) async {
    await _notificationsService.showNotification(
      title: 'Handoff received',
      body: 'Opening $url',
    );
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isAndroid) {
      await _platformChannel.invokeMethod('openUrl', {'url': url});
    }
  }

  void _sendHandoff(String url) {
    if (url.isEmpty) return;
    _webSocketService.send(
      _handoffService.createHandoffMessage(url, _deviceId),
    );
  }

  Future<void> _mountPhoneInFinder() async {
    try {
      final success = await _platformChannel.invokeMethod<bool>('mountPhoneInFinder');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success == true
                ? 'Phone mounted in Finder at ~/WirePhone'
                : 'Unable to mount phone. Check USB and ADB connection.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mount failed: $e')),
      );
    }
  }

  Future<void> _init() async {
    await _permissionsService.requestAll();
    await _notificationsService.init(onSelectNotification: _onNotificationTap);
    await _focusModeService.init();
    await _focusModeService.init();
    if (Platform.isAndroid) {
      await _backgroundService.init();
      await _backgroundService.start();

      // Initialize Floating Dock service
      await _floatingDockService.initialize();

      _notificationSub = _notificationSyncService.onNotificationReceived.listen(
        (notif) {
          if (_notificationSyncEnabled &&
              _peerHost.isNotEmpty &&
              _webSocketService.isClientConnected) {
            _webSocketService.send({
              'type': 'sync_notification',
              'title': notif['title'],
              'body': notif['body'],
              'packageName': notif['packageName'],
              'from': _deviceId,
            });
          }
        },
      );
    }

    _battery.onBatteryStateChanged.listen((state) {
      if (mounted) setState(() => _batteryState = state);
      _sendBatteryStatus();
    });
    _battery.batteryLevel.then((level) {
      if (mounted) setState(() => _batteryLevel = level);
      _sendBatteryStatus();
    });
    
    // Battery level check every 5 minutes
    _performanceService.createPeriodicTimer(
      const Duration(minutes: OptimizationConfig.batteryCheckIntervalMinutes),
      (_) async {
        final level = await _battery.batteryLevel;
        if (mounted) setState(() => _batteryLevel = level);
        _sendBatteryStatus();
      },
    );
    
    // Auto-reconnect: retry connection every 10s when disconnected
    _performanceService.createPeriodicTimer(
      const Duration(seconds: OptimizationConfig.reconnectIntervalSeconds),
      (_) {
        if (!mounted) return;
        if (!_webSocketService.isClientConnected &&
            _peerHost.isNotEmpty &&
            _autoConnectEnabled) {
          _connectToPeer(_peerHost);
        }
      },
    );

    _deviceId = await _identity.getOrCreateDeviceId();
    await _pairingService.init();
    final prefs = await SharedPreferences.getInstance();
    _peerController.text = _peerHost;
    _discoveryEnabled = prefs.getBool('discovery_enabled') ?? true;
    _autoConnectEnabled = prefs.getBool('auto_connect') ?? true;
    _clipboardHistoryEnabled =
        prefs.getBool('clipboard_history_enabled') ?? true;
    _notificationSyncEnabled =
        prefs.getBool('notification_sync_enabled') ?? false;
    _transferHistoryEnabled = prefs.getBool('transfer_history_enabled') ?? true;
    _silentClipboard = prefs.getBool('silent_clipboard') ?? true;
    _labsMirrorFeaturesEnabled =
      prefs.getBool('labs_mirror_features_enabled') ?? true;
    _labsStudentHubEnabled = prefs.getBool('labs_student_hub_enabled') ?? true;
    _labsMountFinderEnabled = prefs.getBool('labs_mount_finder_enabled') ?? true;

    try {
      debugPrint('Starting WebSocket server on port $_wsPort...');
      await _webSocketService.startServer();
      debugPrint('WebSocket server started.');
    } catch (e) {
      debugPrint('WebSocket server failed to start: $e');
    }
    try {
      debugPrint('Starting File transfer server on port $_filePort...');
      await _fileTransferService.startServer();
      debugPrint('File transfer server started.');
    } catch (e) {
      debugPrint('File transfer server failed to start: $e');
    }
    _wsSub = _webSocketService.messages.listen(_handleIncomingMessage);

    _receiveProgressSub = _fileTransferService.receiveProgress.listen(
      _handleReceiveProgress,
    );
    _fileTransferService.receiveComplete.listen(_handleReceiveComplete);

    _localIps = await _networkInfoService.getLocalIPv4Addresses();

    await _historyService.init();
    final clipboardHistory = await _historyService.getClipboardHistory();
    final transferHistory = await _historyService.getTransferHistory();
    setState(() {
      _clipboardHistory.addAll(clipboardHistory);
      _transfers.addAll(transferHistory);
    });

    await _ensureClipboardServiceStarted();
    await _startDiscovery();

    if (_autoConnectEnabled && _peerHost.isNotEmpty) {
      _connectToPeer(_peerHost);
    }
    _sendBatteryStatus();
    await _handlePageChange(_currentIndex, notify: false);
    await _initTray();
    if (mounted) setState(() {});
  }

  Future<void> _handlePageChange(int index, {bool notify = true}) async {
    if (notify) {
      setState(() => _currentIndex = index);
    }
    if (index == 1) {
      await _ensureShareServiceStarted();
    }
  }

  Future<void> _ensureClipboardServiceStarted() async {
    if (_clipboardStarted) return;
    _clipboardStarted = true;
    _clipboardSub = _clipboardService.onClipboardChanged.listen(
      _handleLocalClipboardChange,
    );
    await _clipboardService.start();
  }

  Future<void> _ensureShareServiceStarted() async {
    if (_shareStarted) return;
    _shareStarted = true;
    _shareIntentService.start();
    _shareSub = _shareIntentService.sharedFiles.listen(_handleSharedFiles);
  }

  Future<void> _initTray() async {
    if (!Platform.isMacOS) return;
    final connected =
        _webSocketService.isClientConnected ||
        _webSocketService.hasServerClients;
    await _trayService.init(
      title: 'Wire Sync',
      clipboardItems: _clipboardHistory.map((e) => e.text).toList(),
      transferItems: _transfers
          .map((e) => '${e.direction}: ${e.name}')
          .toList(),
      paused: _syncPaused,
      discoveryEnabled: _discoveryEnabled,
      connected: connected,
      onShow: () => _platformChannel.invokeMethod('activateApp'),
      onTogglePause: _toggleSyncPaused,
      onToggleDiscovery: _toggleDiscoveryFromTray,
      onDisconnect: _disconnectPeer,
      onQuit: () => exit(0),
    );
  }

  void _sendBatteryStatus() {
    _webSocketService.send({
      'type': 'status',
      'battery': _batteryLevel,
      'isCharging': _batteryState == BatteryState.charging,
    });
  }

  Future<void> _refreshTray() async {
    if (!Platform.isMacOS) return;
    final connected =
        _webSocketService.isClientConnected ||
        _webSocketService.hasServerClients;
    await _trayService.updateMenu(
      clipboardItems: _clipboardHistory.map((e) => e.text).toList(),
      transferItems: _transfers
          .map((e) => '${e.direction}: ${e.name}')
          .toList(),
      paused: _syncPaused,
      discoveryEnabled: _discoveryEnabled,
      connected: connected,
      onShow: () => _platformChannel.invokeMethod('activateApp'),
      onTogglePause: _toggleSyncPaused,
      onToggleDiscovery: _toggleDiscoveryFromTray,
      onDisconnect: _disconnectPeer,
      onQuit: () => exit(0),
    );
  }

  Future<void> _toggleSyncPaused() async {
    _syncPaused = !_syncPaused;
    if (_syncPaused) {
      _clipboardService.stop();
      await _discoveryService.stop();
    } else {
      if (_clipboardStarted) {
        await _clipboardService.start();
      }
      if (_discoveryEnabled) {
        await _startDiscovery();
      }
    }
    await _refreshTray();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleDiscoveryFromTray() async {
    final prefs = await SharedPreferences.getInstance();
    _discoveryEnabled = !_discoveryEnabled;
    await prefs.setBool('discovery_enabled', _discoveryEnabled);
    if (_discoveryEnabled && !_syncPaused) {
      await _startDiscovery();
    } else {
      await _discoveryService.stop();
    }
    await _refreshTray();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _disconnectPeer() async {
    await _webSocketService.disconnectClient();
    await _refreshTray();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startDiscovery() async {
    if (!_discoveryEnabled) return;
    await _discoveryService.start(
      deviceId: _deviceId,
      wsPort: _wsPort,
      filePort: _filePort,
      onPeerFound: (info) {
        setState(() {
          final idx = _discoveredPeers.indexWhere((p) => p.deviceId == info.deviceId);
          if (idx >= 0) {
            _discoveredPeers[idx] = info;
          } else {
            _discoveredPeers.add(info);
          }
        });
        final active = _pairingService.activeDevice;
        if (active != null && active.deviceId == info.deviceId && !_webSocketService.isClientConnected) {
          _remoteFilePort = info.filePort;
          _connectToPeer(info.address.address, port: info.wsPort);
        }
      },
    );
  }

  Future<void> _connectToPeer(String host, {int? port}) async {
    if (host.isEmpty) return;
    await _webSocketService.connectToPeer(host, portOverride: port);
    final primaryIp = _localIps.isNotEmpty ? _localIps.first : '';
    _webSocketService.send({
      'type': 'hello',
      'host': primaryIp,
      'filePort': _filePort,
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'deviceName': Platform.localHostname,
      'os': Platform.operatingSystem,
    });
    _lastSyncAt = DateTime.now();
    await _sendCurrentClipboard();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('peer_host', host);
  }

  void _handleLocalClipboardChange(String text) {
    if (_syncPaused) return;
    if (_lastClipboardSentText == text) {
      return;
    }
    _lastClipboardSentText = text;
    _clipboardService.markLocal(text);
    _addClipboardHistory(text, source: 'Local');
    _webSocketService.send({
      'type': 'clipboard',
      'text': text,
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    _lastSyncAt = DateTime.now();
    // Also try to send image if one is on the clipboard
    _trySendClipboardImage();
  }

  Future<void> _trySendClipboardImage() async {
    try {
      final b64 = await _clipboardService.getClipboardImage();
      if (b64 != null && b64.isNotEmpty) {
        _webSocketService.send({
          'type': 'clipboard_image',
          'base64': b64,
          'from': _deviceId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        _lastSyncAt = DateTime.now();
      }
    } catch (_) {
      // Image clipboard not supported on this platform
    }
  }

  Future<void> _sendCurrentClipboard() async {
    final text = await _clipboardService.getClipboardText();
    if (text == null || text.isEmpty) return;
    _clipboardService.markLocal(text);
    _handleLocalClipboardChange(text);
  }

  String _connectionHealthLabel(bool connected) {
    if (!connected) return 'Offline';
    final ping = _pingMs;
    if (ping == null) return 'Connected';
    if (ping <= 80) return 'Excellent';
    if (ping <= 180) return 'Good';
    if (ping <= 320) return 'Fair';
    return 'Poor';
  }

  String _lastSyncLabel() {
    final t = _lastSyncAt;
    if (t == null) return 'Never';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Future<void> _sendClipboardFileFromClipboard() async {
    final raw = await _clipboardService.getClipboardText();
    if (raw == null || raw.trim().isEmpty) {
      if (mounted) {
        WireSnackbar.showWarning(context, message: 'Clipboard has no file path to send');
      }
      return;
    }

    final trimmed = raw.trim();
    String? resolvedPath;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == 'file') {
      resolvedPath = uri.toFilePath();
    } else if (trimmed.startsWith('/')) {
      resolvedPath = trimmed;
    }

    if (resolvedPath == null || resolvedPath.isEmpty) {
      if (mounted) {
        WireSnackbar.showWarning(context, message: 'Copy a local file path first, then tap Paste File');
      }
      return;
    }

    final file = File(resolvedPath);
    if (!await file.exists()) {
      if (mounted) {
        WireSnackbar.showError(context, message: 'File not found in clipboard path');
      }
      return;
    }

    await _sendFile(resolvedPath);
    if (!mounted) return;
    WireSnackbar.showSuccess(
      context,
      message: 'Sending ${p.basename(resolvedPath)}',
    );
  }

  Future<void> _handleIncomingMessage(Map<String, dynamic> message) async {
    final type = message['type']?.toString() ?? '';
    if (type == 'ping') {
      // WebSocketService handles pong; also measure latency here
      if (_pingSentAt != null) {
        final ms = DateTime.now().difference(_pingSentAt!).inMilliseconds;
        if (mounted) setState(() => _pingMs = ms);
        _pingSentAt = null;
      }
      return;
    }

    if (type == 'pong') {
      if (_pingSentAt != null) {
        final ms = DateTime.now().difference(_pingSentAt!).inMilliseconds;
        if (mounted) setState(() => _pingMs = ms);
        _pingSentAt = null;
      }
      return;
    }

    if (type == 'sync_notification') {
      final title = message['title']?.toString() ?? 'Notification';
      final body = message['body']?.toString() ?? '';
      await _notificationsService.showNotification(title: title, body: body);
      return;
    }

    if (type == 'status') {
      final battery = int.tryParse(message['battery']?.toString() ?? '');
      final charging = message['isCharging'] == true;

      // Battery alerts
      if (battery != null && _remoteBattery != null) {
        if (battery == 100 && charging && _remoteBattery! < 100) {
          _notificationsService.showNotification(
            title: 'Remote Device Fully Charged',
            body: 'Your connected device is at 100%.',
          );
        } else if (battery <= 15 && !charging && _remoteBattery! > 15) {
          _notificationsService.showNotification(
            title: 'Remote Device Battery Low',
            body: 'Your connected device is at $battery%.',
          );
        }
      }

      if (mounted) {
        setState(() {
          _remoteBattery = battery;
          _remoteIsCharging = charging;
        });
      }
      return;
    }

    if (type == 'find_phone') {
      if (Platform.isAndroid) {
        _platformChannel.invokeMethod('ringPhone');
      }
      return;
    }

    if (type == 'stop_phone_ring') {
      if (Platform.isAndroid) {
        _platformChannel.invokeMethod('stopRinging');
      }
      return;
    }

    if (type == 'keyboard_event') {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final keyCode = message['keyCode'];
        final action = message['action']?.toString() ?? 'press';
        if (keyCode is int) {
          _platformChannel.invokeMethod('inputKeyEvent', {
            'keyCode': keyCode,
            'action': action,
          });
        }
      }
      return;
    }

    if (type.startsWith('media_')) {
      if (Platform.isAndroid || Platform.isMacOS) {
        switch (type) {
          case 'media_play_pause':
            _platformChannel.invokeMethod('mediaPlayPause');
            break;
          case 'media_next':
            _platformChannel.invokeMethod('mediaNext');
            break;
          case 'media_prev':
            _platformChannel.invokeMethod('mediaPrevious');
            break;
          case 'media_vol_up':
            _platformChannel.invokeMethod('volumeUp');
            break;
          case 'media_vol_down':
            _platformChannel.invokeMethod('volumeDown');
            break;
          case 'media_vol_mute':
            _platformChannel.invokeMethod('volumeMute');
            break;
        }
      }
      return;
    }

    if (type == 'sms_fetch_request') {
      if (Platform.isAndroid) {
        try {
          final List<dynamic> smsData = await _platformChannel.invokeMethod(
            'getRecentSms',
          );
          _webSocketService.send({
            'type': 'sms_list',
            'data': smsData,
            'from': _deviceId,
          });
        } catch (e) {
          debugPrint('Error fetching SMS: $e');
          _webSocketService.send({
            'type': 'sms_error',
            'message': 'Failed to fetch SMS: $e',
            'from': _deviceId,
          });
        }
      }
      return;
    }

    if (type == 'sms_send_request') {
      if (Platform.isAndroid) {
        final number = message['number']?.toString() ?? '';
        final text = message['message']?.toString() ?? '';
        try {
          await _platformChannel.invokeMethod('sendSms', {
            'number': number,
            'message': text,
          });
          // After sending, wait a sec and refetch to update the list
          Future.delayed(const Duration(seconds: 2), () async {
            final List<dynamic> smsData = await _platformChannel.invokeMethod(
              'getRecentSms',
            );
            _webSocketService.send({
              'type': 'sms_list',
              'data': smsData,
              'from': _deviceId,
            });
          });
        } catch (e) {
          debugPrint('Error sending SMS: $e');
        }
      }
      return;
    }

    if (type == 'mouse_event') {
      if (Platform.isMacOS) {
        final dx = (message['dx'] as num?)?.toDouble() ?? 0.0;
        final dy = (message['dy'] as num?)?.toDouble() ?? 0.0;
        final action = message['action']?.toString() ?? 'move';
        _platformChannel.invokeMethod('dispatchMouseEvent', {
          'dx': dx,
          'dy': dy,
          'action': action,
        });
      }
      return;
    }
    // ── WebRTC screen mirror signaling (not affected by sync pause) ──────────
    if (type == 'screen_request') {
      // The remote device wants to view our screen.
      // We should start sending our screen to them.
      try {
        if (Platform.isAndroid) {
          await _platformChannel.invokeMethod('activateApp');
          // Give Android a moment to bring the app to the foreground
          await Future.delayed(const Duration(milliseconds: 500));
        }
        await _screenMirrorService.startSending();
      } catch (e) {
        debugPrint('Failed to start sending screen: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to mirror screen: $e')),
          );
        }
      }
      return;
    }

    if (type == 'screen_offer') {
      final sdp = message['sdp']?.toString() ?? '';
      if (sdp.isNotEmpty) {
        final renderer = await _screenMirrorService.receiveOffer(sdp);
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ScreenMirrorPage(
                mirrorService: _screenMirrorService,
                initialRenderer: renderer,
                onSendFile: (path) => _sendFile(path),
                onStop: () {},
              ),
            ),
          );
        }
      }
      return;
    }

    if (type == 'screen_answer') {
      await _screenMirrorService.receiveAnswer(
        message['sdp']?.toString() ?? '',
      );
      return;
    }

    if (type == 'screen_ice') {
      await _screenMirrorService.addIceCandidate(message);
      return;
    }

    if (type == 'screen_touch') {
      if (Platform.isAndroid) {
        final nx = (message['nx'] as num?)?.toDouble() ?? 0.0;
        final ny = (message['ny'] as num?)?.toDouble() ?? 0.0;
        final action = message['action']?.toString() ?? 'down';
        await _platformChannel.invokeMethod('dispatchTouch', {
          'nx': nx,
          'ny': ny,
          'action': action,
        });
      }
      return;
    }

    if (type == 'screen_stop' || type == 'camera_stop') {
      await _screenMirrorService.stop();
      return;
    }

    // ── WebRTC Camera Remote signaling ──────────
    if (type == 'camera_request') {
      try {
        await _screenMirrorService.startSendingCamera();
      } catch (e) {
        debugPrint('Failed to start sending camera: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to mirror camera: $e')),
          );
        }
      }
      return;
    }

    if (type == 'camera_offer') {
      final sdp = message['sdp']?.toString() ?? '';
      if (sdp.isNotEmpty) {
        await _screenMirrorService.receiveOffer(sdp, isCamera: true);
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CameraViewerPage(
                mirrorService: _screenMirrorService,
                onFlipCamera: () {
                  _webSocketService.send({
                    'type': 'camera_flip',
                    'from': _deviceId,
                  });
                },
              ),
            ),
          );
        }
      }
      return;
    }

    if (type == 'camera_answer') {
      await _screenMirrorService.receiveAnswer(
        message['sdp']?.toString() ?? '',
      );
      return;
    }

    if (type == 'camera_ice') {
      await _screenMirrorService.addIceCandidate(message);
      return;
    }

    if (type == 'camera_flip') {
      if (Platform.isAndroid) {
        await _screenMirrorService.switchCamera();
      }
      return;
    }

    // Respect sync paused for all non-control messages
    if (_syncPaused) return;
    final from = message['from']?.toString() ?? '';
    if (from == _deviceId) {
      return;
    }

    if (type == 'hello') {
      final host = message['host']?.toString() ?? '';
      final filePort =
          int.tryParse(message['filePort']?.toString() ?? '') ?? _filePort;
      final from = message['from']?.toString() ?? '';
      final name = message['deviceName']?.toString() ?? 'Unknown Device';
      final os = message['os']?.toString() ?? 'unknown';

      if (from.isNotEmpty && host.isNotEmpty) {
        final wasEmpty = _pairingService.activeDevice == null;
        await _pairingService.addOrUpdateDevice(PairedDevice(
          deviceId: from,
          name: name,
          lastIp: host,
          isTrusted: _pairingService.activeDevice?.deviceId == from || _pairingService.isTrusted(from),
          osType: os,
          lastSeenAt: DateTime.now().millisecondsSinceEpoch,
        ));
        
        if (wasEmpty && _pairingService.isTrusted(from)) {
            await _pairingService.setActiveDevice(from);
            _peerController.text = host;
        }
      }
      _remoteFilePort = filePort;
      return;
    }

    if (type == 'handoff') {
      final url = message['url']?.toString() ?? '';
      _handoffService.handleIncomingHandoff(message);
      _addStudyLink(url, 'Remote Handoff');
      return;
    }

    if (type == 'focus_mode') {
      final enabled = message['enabled'] == true;
      _notificationsService.showNotification(
        title: 'Focus Mode ${enabled ? 'ON' : 'OFF'}',
        body: 'Remote device ${enabled ? 'is studying' : 'is available'}',
      );
      return;
    }

    if (type == 'clipboard') {
      final text = message['text']?.toString() ?? '';
      if (!_clipboardService.shouldIgnoreIncoming(text)) {
        await _clipboardService.setClipboardText(text);
        _addClipboardHistory(text, source: 'Remote');
        _addNotificationHistory(title: 'Clipboard synced', body: text);
        // Silent by default; only notify if user opted in
        if (!_silentClipboard) {
          await _notificationsService.showClipboardNotification(text);
        }
        setState(() => _isSyncing = true);
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setState(() => _isSyncing = false);
        });
      }
      return;
    }

    if (type == 'clipboard_image') {
      final b64 = message['base64']?.toString() ?? '';
      if (b64.isNotEmpty) {
        await _clipboardService.setClipboardImage(b64);
        _addNotificationHistory(
          title: 'Image synced',
          body: 'Image copied to clipboard',
        );
        await _notificationsService.showNotification(
          title: 'Image synced',
          body: 'Image copied to clipboard',
          category: NotificationCategory.clipboard,
        );
        if (mounted) {
          setState(() => _isSyncing = true);
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) setState(() => _isSyncing = false);
          });
        }
      }
      return;
    }

    if (type == 'file') {
      final name = message['name']?.toString() ?? '';
      if (name.isNotEmpty) {
        await _notificationsService.showFileNotification(name);
      }
      return;
    }

    if (type == 'file_request') {
      final name = message['name']?.toString() ?? '';
      final path = _sentFilePaths[name];
      if (path != null && path.isNotEmpty) {
        await _sendFile(path);
      } else {
        await _notificationsService.showNotification(
          title: 'File not found',
          body: name,
        );
      }
      return;
    }

    if (type == 'type_text_live' || type == 'input') {
      final text = message['text']?.toString() ?? '';
      if (text.isNotEmpty) {
        try {
          final success = await _platformChannel.invokeMethod<bool>('inputText', {
            'text': text,
          });
          if (success != true && Platform.isAndroid) {
            await _notificationsService.showNotification(
              title: 'Keyboard mirror needs Accessibility',
              body: 'Enable Wire Input Service in Accessibility settings.',
            );
          }
        } catch (_) {
          // Platform may not support direct input
        }
      }
      return;
    }

    if (type == 'type_text') {
      final text = message['text']?.toString() ?? '';
      if (text.isEmpty) return;
      await _clipboardService.setClipboardText(text);
      _addClipboardHistory(text, source: 'Text input');
      await _notificationsService.showNotification(
        title: 'Text received',
        body: text,
      );
      return;
    }
  }

  void _handleSharedFiles(List<String> paths) {
    for (final path in paths) {
      if (path.isNotEmpty) {
        _sendFile(path);
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path != null) {
      _sendFile(path);
    }
  }

  Future<void> _sendFile(String filePath) async {
    if (_peerHost.isEmpty) {
      final fallback = _webSocketService.lastClientAddress ?? '';
      if (fallback.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No peer IP. Connect first.')),
          );
        }
        return;
      }
    }
    final targetHost = _peerHost.isNotEmpty ? _peerHost : (_webSocketService.lastClientAddress ?? '');
    final total = await File(filePath).length();
    final name = p.basename(filePath);
    final id = '${DateTime.now().millisecondsSinceEpoch}-$name';
    final transfer = TransferItem(
      id: id,
      name: name,
      total: total,
      direction: 'send',
      path: filePath,
      status: 'sending',
      startTime: DateTime.now(),
    );
    setState(() {
      if (!_transferHistoryEnabled) {
        _transfers.clear();
      }
      _transfers.insert(0, transfer);
      _trimTransfers();
    });
    if (_transferHistoryEnabled) {
      _historyService.saveTransfer(transfer);
    }
    _sentFilePaths[name] = filePath;
    _refreshTray();

    _webSocketService.send({
      'type': 'file',
      'name': name,
      'size': total,
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    _lastSyncAt = DateTime.now();

    _webSocketService.setAggressiveHeartbeat(
      true,
    ); // Enable aggressive heartbeat
    try {
      await _fileTransferService.sendFile(
        filePath: filePath,
        host: targetHost,
        port: _remoteFilePort,
        onProgress: (sent, total) {
          setState(() {
            transfer.progress = total == 0 ? 0 : sent / total;
            transfer.status = sent >= total ? 'done' : 'sending';
            transfer.bytesTransferred = sent;
          });
          _refreshTray();
        },
      );
    } catch (error) {
      final fallbackPort = _remoteFilePort == _filePort
          ? _filePort + 1
          : _filePort;
      if (_remoteFilePort != fallbackPort) {
        try {
          await _fileTransferService.sendFile(
            filePath: filePath,
            host: _peerHost,
            port: _filePort,
            onProgress: (sent, total) {
              setState(() {
                transfer.progress = total == 0 ? 0 : sent / total;
                transfer.status = sent >= total ? 'done' : 'sending';
              });
              _refreshTray();
            },
          );
          return;
        } catch (_) {
          // fall through to failure
        }
      }
      setState(() {
        transfer.status = 'failed';
      });
      final hint = _remoteFilePort != _filePort
          ? 'Remote file port: $_remoteFilePort'
          : 'Check same Wi‑Fi, VPN, and that the app is open on the phone.';
      await _notificationsService.showNotification(
        title: 'File send failed',
        body: '$name\n$error\n$hint',
      );
    } finally {
      _webSocketService.setAggressiveHeartbeat(
        false,
      ); // Disable aggressive heartbeat
    }
  }

  void _handleReceiveProgress(FileReceiveProgress progress) {
    final existing = _transfers
        .where((item) => item.path == progress.path)
        .toList();
    if (existing.isEmpty) {
      final item = TransferItem(
        id: progress.path,
        name: progress.name,
        total: progress.total,
        direction: 'receive',
        path: progress.path,
        status: 'receiving',
        startTime: DateTime.now(),
      );
      item.progress = progress.total == 0
          ? 0
          : progress.received / progress.total;
      item.bytesTransferred = progress.received;
      setState(() {
        if (!_transferHistoryEnabled) {
          _transfers.clear();
        }
        _transfers.insert(0, item);
        _trimTransfers();
      });
      debugPrint('UI: Initialized receive for ${item.name} at ${item.path}');
      _webSocketService.setAggressiveHeartbeat(true);
      _refreshTray();
    } else {
      setState(() {
        final item = existing.first;
        item.progress = progress.total == 0
            ? 0
            : progress.received / progress.total;
        item.status = 'receiving';
        item.bytesTransferred = progress.received;
      });
      debugPrint(
        'UI: Progress for ${progress.name}: ${(progress.received / progress.total * 100).toInt()}%',
      );
      _webSocketService.setAggressiveHeartbeat(true);
      _refreshTray();
    }
  }

  Future<void> _handleReceiveComplete(FileReceiveProgress progress) async {
    setState(() {
      final item = _transfers.firstWhere(
        (element) => element.path == progress.path,
        orElse: () {
          final newItem = TransferItem(
            id: progress.path,
            name: progress.name,
            total: progress.total,
            direction: 'receive',
            path: progress.path,
            status: 'complete',
          );
          _transfers.insert(0, newItem);
          _trimTransfers();
          return newItem;
        },
      );
      item.status = 'complete';
      item.progress = 1.0;
      if (_transferHistoryEnabled) {
        _historyService.saveTransfer(item);
      }
    });
    debugPrint('UI: Receive complete for ${progress.name}');
    _webSocketService.setAggressiveHeartbeat(false);
    _refreshTray();
    _lastSyncAt = DateTime.now();
    await _notificationsService.showNotification(
      title: 'File received',
      body: '${progress.name} saved to Downloads',
      payload: 'file:${progress.path}',
    );
  }

  void _handleDroppedFiles(List<String> paths) {
    for (final path in paths) {
      if (path.isNotEmpty) {
        _sendFile(path);
      }
    }
  }

  String _lastMirroredText = '';

  void _handleLiveTypingChange() {
    final text = _textController.text;
    if (text == _lastMirroredText) return;
    _lastMirroredText = text;
    _webSocketService.send({
      'type': 'type_text_live',
      'text': text,
      'mode': 'full',
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      if (payload.startsWith('file:')) {
        final path = payload.replaceFirst('file:', '');
        if (Platform.isMacOS) {
          _platformChannel.invokeMethod('revealInFinder', {'path': path});
        } else if (Platform.isAndroid) {
          _platformChannel.invokeMethod('openDownloadsFolder');
        }
      }
    }
  }

  void _addClipboardHistory(String text, {required String source}) {
    if (_clipboardHistory.isNotEmpty && _clipboardHistory.first.text == text) {
      return;
    }
    setState(() {
      if (!_clipboardHistoryEnabled) {
        _clipboardHistory.clear();
      }
      final clipboardItem = ClipboardItem(
        text: text,
        timestamp: DateTime.now(),
        from: source,
      );
      _clipboardHistory.insert(0, clipboardItem);
      if (_clipboardHistoryEnabled) {
        _historyService.saveClipboard(clipboardItem);
      }

      // Auto-detect study links
      if (text.startsWith('http') || text.contains('www.')) {
        final uri = Uri.tryParse(text);
        if (uri != null) {
          final host = uri.host.toLowerCase();
          if (host.contains('scholar') ||
              host.contains('wikipedia') ||
              host.contains('arxiv') ||
              host.contains('researchgate') ||
              host.contains('github')) {
            _addStudyLink(text, 'Auto-detected Research');
          }
        }
      }
      if (_clipboardHistory.length > _maxClipboardItems) {
        _clipboardHistory.removeLast();
      }
    });
    _refreshTray();
  }

  void _trimTransfers() {
    if (!_transferHistoryEnabled && _transfers.length > 1) {
      _transfers.removeRange(1, _transfers.length);
      return;
    }
    if (_transfers.length <= _maxTransferItems) return;
    _transfers.removeRange(_maxTransferItems, _transfers.length);
  }

  Future<void> _clearClipboardHistory() async {
    await _historyService.clearClipboardHistory();
    if (!mounted) return;
    setState(() => _clipboardHistory.clear());
    WireSnackbar.showSuccess(
      context,
      message: 'Clipboard history cleared successfully',
    );
  }

  Future<void> _clearTransferHistory() async {
    await _historyService.clearTransferHistory();
    if (!mounted) return;
    setState(() => _transfers.clear());
    WireSnackbar.showSuccess(
      context,
      message: 'Transfer history cleared successfully',
    );
  }

  void _clearNotificationHistory() {
    setState(() => _notificationHistory.clear());
    WireSnackbar.showSuccess(
      context,
      message: 'Notification history cleared successfully',
    );
  }

  Future<void> _refreshDashboardData() async {
    final level = await _battery.batteryLevel;
    final ips = await _networkInfoService.getLocalIPv4Addresses();
    if (!mounted) return;
    setState(() {
      _batteryLevel = level;
      _localIps = ips;
    });
    _sendBatteryStatus();
    await _refreshTray();
    if (!mounted) return;
    WireSnackbar.showInfo(context, message: 'Dashboard refreshed');
  }

  Future<void> _refreshFileData() async {
    final transferHistory = await _historyService.getTransferHistory();
    if (!mounted) return;
    setState(() {
      _transfers
        ..clear()
        ..addAll(transferHistory);
    });
    await _refreshTray();
    if (!mounted) return;
    WireSnackbar.showInfo(context, message: 'Files refreshed');
  }

  Future<void> _retryTransfer(TransferItem item) async {
    if (item.direction == 'send' && item.path.isNotEmpty) {
      await _sendFile(item.path);
      return;
    }
    WireSnackbar.showWarning(
      context,
      message: 'Retry is only available for sent files',
    );
  }

  void _removeTransfer(TransferItem item) {
    setState(() {
      _transfers.removeWhere((e) => e.id == item.id);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed ${item.name}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              setState(() {
                _transfers.insert(0, item);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Undo successful')),
              );
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _showQuickActionsPalette() {
    final searchController = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final connected =
            _webSocketService.isClientConnected || _webSocketService.hasServerClients;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final actions = [
              (
                icon: Icons.grid_view_rounded,
                label: 'Go to Dashboard',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handlePageChange(0);
                }
              ),
              (
                icon: Icons.folder_copy_rounded,
                label: 'Go to Files',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handlePageChange(1);
                }
              ),
              (
                icon: Icons.tune_rounded,
                label: 'Go to Settings',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handlePageChange(2);
                }
              ),
              (
                icon: Icons.sync_rounded,
                label: 'Send current clipboard',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _sendCurrentClipboard();
                }
              ),
              (
                icon: Icons.file_upload_rounded,
                label: 'Paste file from clipboard',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _sendClipboardFileFromClipboard();
                }
              ),
              (
                icon: _localFocusMode ? Icons.bolt_rounded : Icons.bolt_outlined,
                label: _localFocusMode ? 'Disable focus mode' : 'Enable focus mode',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _focusModeService.setFocusMode(!_localFocusMode);
                }
              ),
              if (connected)
                (
                  icon: Icons.ring_volume_rounded,
                  label: 'Find my phone',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _webSocketService.send({'type': 'find_phone', 'from': _deviceId});
                    WireSnackbar.showInfo(context, message: 'Ringing device...');
                  }
                ),
              (
                icon: Icons.upload_file_rounded,
                label: 'Send file',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndSendFile();
                }
              ),
            ];

            final query = searchController.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? actions
                : actions
                    .where((item) => item.label.toLowerCase().contains(query))
                    .toList();

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: GlassCard(
                  accent: scheme.primary,
                  borderRadius: 24,
                  elevated: true,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: searchController,
                        onChanged: (_) => setModalState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search quick commands...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return _quickActionTile(
                              icon: item.icon,
                              label: item.label,
                              onTap: item.onTap,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _quickActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        accent: scheme.secondary,
        borderRadius: 16,
        padding: EdgeInsets.zero,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: scheme.primary),
          title: Text(
            label,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  void _addStudyLink(String url, String source) {
    setState(() {
      _studyLinks.insert(0, {
        'url': url,
        'source': source,
        'time': DateTime.now().toString(),
      });
      if (_studyLinks.length > 10) _studyLinks.removeLast();
    });
  }

  void _addNotificationHistory({required String title, required String body}) {
    setState(() {
      _notificationHistory.insert(0, {
        'title': title,
        'body': body,
        'timestamp': DateTime.now(),
      });
      if (_notificationHistory.length > 20) _notificationHistory.removeLast();
    });
  }

  void _onFloatingDockEvent(FloatingDockEvent event) {
    if (!mounted || event.type != 'action_tapped') return;
    final action = event.data['action']?.toString();
    if (action == null) return;

    switch (action) {
      case 'keyboard':
        setState(() => _currentIndex = 0);
        _showKeyboardProxyDialog();
        break;
      case 'camera':
        _webSocketService.send({
          'type': 'camera_request',
          'from': _deviceId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        break;
      case 'clipboard':
        _sendCurrentClipboard();
        break;
      case 'files':
        setState(() => _currentIndex = 1);
        break;
      case 'settings':
        setState(() => _currentIndex = 2);
        break;
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _shareSub?.cancel();
    _receiveProgressSub?.cancel();
    _clipboardSub?.cancel();
    _notificationSub?.cancel();
    _peerController.dispose();
    _textController.dispose();
    _incomingTextController.dispose();
    _clipboardService.dispose();
    _webSocketService.dispose();
    _fileTransferService.dispose();
    _discoveryService.stop();
    _shareIntentService.dispose();
    _floatingDockService.dispose();
    _performanceService.cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        _webSocketService.isClientConnected ||
        _webSocketService.hasServerClients;
    final primaryIp = _localIps.isNotEmpty ? _localIps.first : '';
    final pages = [
      _buildCurrentPage(context, connected, primaryIp, 0),
      _buildCurrentPage(context, connected, primaryIp, 1),
      _buildCurrentPage(context, connected, primaryIp, 2),
    ];
    final dockItems = const [
      LiquidGlassDockItem(
        icon: Icons.grid_view_rounded,
        selectedIcon: Icons.space_dashboard_rounded,
        label: 'Dashboard',
      ),
      LiquidGlassDockItem(
        icon: Icons.folder_copy_outlined,
        selectedIcon: Icons.folder_copy_rounded,
        label: 'Files',
      ),
      LiquidGlassDockItem(
        icon: Icons.tune_outlined,
        selectedIcon: Icons.tune_rounded,
        label: 'Settings',
      ),
    ];

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, meta: true): _OpenQuickActionsIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true): _OpenQuickActionsIntent(),
      },
      child: Actions(
        actions: {
          _OpenQuickActionsIntent: CallbackAction<_OpenQuickActionsIntent>(
            onInvoke: (intent) {
              _showQuickActionsPalette();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
      extendBody: true,
      body: LiquidBackground(
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragActive = true),
          onDragExited: (_) => setState(() => _dragActive = false),
          onDragDone: (details) {
            setState(() => _dragActive = false);
            final paths = details.files.map((f) => f.path).toList();
            _handleDroppedFiles(paths);
          },
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: Platform.isMacOS ? 96 : 0,
                  bottom: Platform.isMacOS ? 0 : 92,
                ),
                child: IndexedStack(
                  index: _currentIndex,
                  children: pages,
                ),
              ),
              if (Platform.isMacOS)
                Positioned(
                  left: 16,
                  top: 110,
                  bottom: 24,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SafeArea(
                      child: LiquidGlassDock(
                        direction: Axis.vertical,
                        items: dockItems,
                        selectedIndex: _currentIndex,
                        onSelect: _handlePageChange,
                      ),
                    ),
                  ),
                ),
              if (_dragActive) _buildDragOverlay(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Platform.isMacOS
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: LiquidGlassDock(
                items: dockItems,
                selectedIndex: _currentIndex,
                onSelect: _handlePageChange,
              ),
            ),
      floatingActionButton: _currentIndex == 0 && Platform.isMacOS
          ? SpeedDialFAB(
              icon: Icons.bolt_rounded,
              openIcon: Icons.close_rounded,
              tooltip: 'Quick Actions',
              actions: [
                SpeedDialAction(
                  icon: Icons.search_rounded,
                  label: 'Quick Commands',
                  onTap: _showQuickActionsPalette,
                ),
                SpeedDialAction(
                  icon: Icons.sync,
                  label: 'Sync Clipboard',
                  onTap: _sendCurrentClipboard,
                ),
                SpeedDialAction(
                  icon: Icons.file_upload_rounded,
                  label: 'Paste File',
                  onTap: _sendClipboardFileFromClipboard,
                ),
                SpeedDialAction(
                  icon: Icons.refresh,
                  label: 'Reconnect',
                  onTap: () {
                    if (_peerHost.isNotEmpty) {
                      _connectToPeer(_peerHost);
                    }
                  },
                ),
                if (_webSocketService.isClientConnected ||
                    _webSocketService.hasServerClients)
                  SpeedDialAction(
                    icon: Icons.phone_android,
                    label: 'Ring Phone',
                    onTap: () {
                      _webSocketService.send({
                        'type': 'ring_phone',
                        'from': _deviceId,
                        'timestamp': DateTime.now().millisecondsSinceEpoch,
                      });
                    },
                  ),
                SpeedDialAction(
                  icon: _localFocusMode ? Icons.bolt_rounded : Icons.bolt_outlined,
                  label: _localFocusMode ? 'Exit Focus' : 'Focus Mode',
                  onTap: () => _focusModeService.setFocusMode(!_localFocusMode),
                ),
              ],
            )
          : null,
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPage(
    BuildContext context,
    bool connected,
    String primaryIp,
    int pageIndex,
  ) {
    if (pageIndex == 0) {
      return HomePage(
        deviceName: Platform.isMacOS ? 'My Mac' : 'My Phone',
        batteryLevel: _batteryLevel,
        isCharging: _batteryState == BatteryState.charging,
        peerName: primaryIp,
        isPeerConnected: connected,
        remoteBattery: _remoteBattery,
        remoteIsCharging: _remoteIsCharging,
        pingMs: _pingMs,
        isSyncing: _isSyncing,
        connectionHealthLabel: _connectionHealthLabel(connected),
        lastSyncLabel: _lastSyncLabel(),
        onReconnect: () {
          if (_peerHost.isNotEmpty) {
            _connectToPeer(_peerHost);
          }
        },
        labsMirrorEnabled: _labsMirrorFeaturesEnabled,
        labsStudentHubEnabled: _labsStudentHubEnabled,
        clipboardHistory: _clipboardHistory,
        focusMode: _localFocusMode,
        onToggleFocus: () => _focusModeService.setFocusMode(!_localFocusMode),
        onMirrorScreen: _labsMirrorFeaturesEnabled ? () {
          _webSocketService.send({
            'type': 'screen_request',
            'from': _deviceId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        } : null,
        onTrackpad: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TrackpadPage(
                webSocketService: _webSocketService,
                deviceId: _deviceId,
              ),
            ),
          );
        },
        onRemoteCamera: _labsMirrorFeaturesEnabled ? () {
          _webSocketService.send({
            'type': 'camera_request',
            'from': _deviceId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        } : null,
        onSms: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SmsPage(
                webSocketService: _webSocketService,
                deviceId: _deviceId,
              ),
            ),
          );
        },
        onMountPhoneInFinder:
          Platform.isMacOS && _labsMountFinderEnabled ? _mountPhoneInFinder : null,
        onFindPhone: () {
          _webSocketService.send({
            'type': 'find_phone',
            'from': _deviceId,
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ringing device...')),
          );
        },
        onMediaAction: (action) {
          _webSocketService.send({'type': action, 'from': _deviceId});
        },
        onMirrorKeyboard: _labsMirrorFeaturesEnabled
            ? () => _showKeyboardProxyDialog()
            : () => WireSnackbar.showInfo(
            context,
            message: 'Enable Mirror Features in Labs settings',
          ),
        onHandoffUrl: () => _showHandoffDialog(),
        onStudentHub: _labsStudentHubEnabled
            ? () => _showStudyHub()
            : () => WireSnackbar.showInfo(
            context,
            message: 'Enable Student Hub in Labs settings',
          ),
        onClipboardCopy: (text) {
          Clipboard.setData(ClipboardData(text: text));
          WireSnackbar.showSuccess(context, message: 'Copied to clipboard');
        },
        onConnectToPeer: (host) => _connectToPeer(host),
        onSendCurrentClipboard: _sendCurrentClipboard,
        onSendClipboardFile: _sendClipboardFileFromClipboard,
        onDevicesTapped: _openDevicePairingPage,
        onClearClipboardItem: (item) {
          setState(() {
            _clipboardHistory.removeWhere((clip) => clip.timestamp == item.timestamp);
          });
          WireSnackbar.showSuccess(context, message: 'Clipboard item cleared');
        },
        onClearClipboardAll: _clearClipboardHistory,
        onRefresh: _refreshDashboardData,
      );
    }

    if (pageIndex == 1) {
      return FilesPage(
        transfers: _transfers,
        onClearHistory: _clearTransferHistory,
        onRetryTransfer: _retryTransfer,
        onRemoveTransfer: _removeTransfer,
        onFileTap: (item) async {
          if (item.status == 'complete') {
            if (Platform.isMacOS) {
              _platformChannel.invokeMethod('revealInFinder', {'path': item.path});
            } else {
              _platformChannel.invokeMethod('openDownloadsFolder');
            }
          }
        },
        onSendFile: _pickAndSendFile,
        onOpenDownloadsFolder: () => _platformChannel.invokeMethod('openDownloadsFolder'),
        onOpenRemoteFiles: _peerHost.isNotEmpty
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RemoteFileManagerPage(
                      peerHost: _peerHost,
                      filePort: _remoteFilePort,
                      fileTransferService: _fileTransferService,
                      onSendFile: _sendFile,
                    ),
                  ),
                )
            : null,
              onRefresh: _refreshFileData,
      );
    }

    return SettingsPage(
      autoConnect: _autoConnectEnabled,
      discoveryEnabled: _discoveryEnabled,
      clipboardSync: _clipboardHistoryEnabled,
      notificationSync: _notificationSyncEnabled,
      transferHistory: _transferHistoryEnabled,
      silentClipboard: _silentClipboard,
      labsMirrorFeatures: _labsMirrorFeaturesEnabled,
      labsStudentHub: _labsStudentHubEnabled,
      labsMountFinder: _labsMountFinderEnabled,
      deviceId: _deviceId,
      themeMode: AppTheme.currentThemeMode,
      onThemeModeChanged: (mode) async {
        await AppTheme.setThemeMode(mode);
      },
      onClearClipboardHistory: _clearClipboardHistory,
      onClearTransferHistory: _clearTransferHistory,
      onClearNotificationHistory: _clearNotificationHistory,
      onHideApp: Platform.isMacOS ? () => _platformChannel.invokeMethod('hideApp') : null,
      onToggleAutoConnect: (val) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('auto_connect', val);
        setState(() => _autoConnectEnabled = val);
      },
      onToggleDiscovery: (val) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('discovery_enabled', val);
        setState(() => _discoveryEnabled = val);
        if (val) {
          await _startDiscovery();
        } else {
          await _discoveryService.stop();
        }
      },
      onToggleClipboardSync: (val) => setState(() => _clipboardHistoryEnabled = val),
      onToggleNotificationSync: _toggleNotificationSync,
      onToggleTransferHistory: (val) => setState(() => _transferHistoryEnabled = val),
      onToggleSilentClipboard: (val) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('silent_clipboard', val);
        setState(() => _silentClipboard = val);
      },
      onToggleLabsMirrorFeatures: (val) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('labs_mirror_features_enabled', val);
        setState(() => _labsMirrorFeaturesEnabled = val);
      },
      onToggleLabsStudentHub: (val) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('labs_student_hub_enabled', val);
        setState(() => _labsStudentHubEnabled = val);
      },
      onToggleLabsMountFinder: (val) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('labs_mount_finder_enabled', val);
        setState(() => _labsMountFinderEnabled = val);
      },
    );
  }

  Widget _buildDragOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.indigo.withValues(alpha: 0.3),
          child: Center(
            child: GlassCard(
              blur: 20,
              opacity: 0.8,
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.file_upload, size: 80, color: Colors.white),
                  const SizedBox(height: 20),
                  const Text(
                    'Drop to Send to Ecosystem',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openDevicePairingPage() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DevicePairingPage(
        pairingService: _pairingService,
        discoveredPeers: _discoveredPeers,
        localDeviceId: _deviceId,
        onMakeActive: (d) async {
          await _pairingService.setActiveDevice(d.deviceId);
          _peerController.text = d.lastIp;
          _connectToPeer(d.lastIp);
        },
        onConnectToPeer: (peer) => _connectToPeer(peer.address.address, port: peer.wsPort),
      ),
    ));
  }

  void _showStudyHub() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.62,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: Colors.indigo.shade900.withValues(alpha: 0.8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: LiquidBackground(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Student Workspace',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const PomodoroTimer(),
                      const SizedBox(height: 16),
                      const Text(
                        'Quick Notes',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: EdgeInsets.zero,
                        child: TextField(
                          maxLines: 3,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Jot down a quick thought or task...',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Study Links & Citations',
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      if (_studyLinks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Text(
                              'No links yet',
                              style: TextStyle(color: Colors.white38),
                            ),
                          ),
                        )
                      else
                        ..._studyLinks.map((link) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassCard(
                              padding: const EdgeInsets.all(12),
                              child: ListTile(
                                title: Text(
                                  link['url']!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  link['source']!,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.open_in_new,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () => _handleHandoff(link['url']!),
                                ),
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 16),
                      const Text(
                        'Workspace Quick Actions',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildHubAction(
                              'Share PDF',
                              Icons.picture_as_pdf,
                              () => _handlePageChange(1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildHubAction(
                              'New Cite',
                              Icons.bookmark_add,
                              () => _showHandoffDialog(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHubAction(String label, IconData icon, VoidCallback onTap) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Colors.white),
        title: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showKeyboardProxyDialog() {
    _textController.clear();
    _lastMirroredText = '';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool accessibilityGranted = !Platform.isMacOS;
          bool checkingAccess = Platform.isMacOS;

          Future<void> checkAccess() async {
            if (!Platform.isMacOS) return;
            try {
              final granted = await _platformChannel.invokeMethod<bool>(
                'getAccessibilityStatus',
              );
              setDialogState(() {
                accessibilityGranted = granted ?? false;
                checkingAccess = false;
              });
            } catch (_) {
              setDialogState(() => checkingAccess = false);
            }
          }

          // Trigger check immediately on first build
          if (checkingAccess) {
            checkAccess();
          }

          return AlertDialog(
            backgroundColor: Colors.indigo.shade900.withValues(alpha: 0.95),
            title: const Row(
              children: [
                Icon(Icons.keyboard, color: Colors.white70, size: 20),
                SizedBox(width: 8),
                Text(
                  'Keyboard Mirroring',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Accessibility banner (macOS only)
                if (Platform.isMacOS &&
                    !checkingAccess &&
                    !accessibilityGranted)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lock, color: Colors.orange, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Accessibility Required',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'To inject keystrokes on macOS, Wire needs Accessibility access in System Settings → Privacy & Security.',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                            ),
                            onPressed: () async {
                              await _platformChannel.invokeMethod(
                                'requestAccessibility',
                              );
                              await checkAccess();
                            },
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text(
                              'Grant Access',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (Platform.isMacOS && checkingAccess)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white38,
                    ),
                  ),
                TextField(
                  controller: _textController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Type here to mirror keystrokes...',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                  autofocus: true,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  enabled: !Platform.isMacOS || accessibilityGranted,
                ),
                const SizedBox(height: 12),
                Text(
                  Platform.isMacOS && !accessibilityGranted
                      ? 'Grant Accessibility access above to enable keystroke injection.'
                      : 'Every keystroke will be mirrored to the connected device in real time.',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _textController.clear();
                  _lastMirroredText = '';
                  Navigator.pop(context);
                },
                child: const Text(
                  'Close',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showHandoffDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.indigo.shade900.withValues(alpha: 0.9),
        title: const Text('Handoff URL', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'https://example.com',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _sendHandoff(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Handoff'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleNotificationSync(bool val) async {
    if (val && Platform.isAndroid) {
      final granted = await _platformChannel.invokeMethod(
        'isNotificationAccessGranted',
      );
      if (granted == false) {
        await _platformChannel.invokeMethod('requestNotificationAccess');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please grant Notification Access to Wire first.'),
            ),
          );
        }
        return; // User has to turn it on manually after granting
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_sync_enabled', val);
    if (mounted) {
      setState(() => _notificationSyncEnabled = val);
    }
  }
}
