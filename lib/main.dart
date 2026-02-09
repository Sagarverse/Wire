import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/app_identity.dart';
import 'services/call_sync_service.dart';
import 'services/call_state_service.dart';
import 'services/clipboard_service.dart';
import 'services/discovery_service.dart';
import 'services/file_transfer_service.dart';
import 'services/notifications_service.dart';
import 'services/network_info_service.dart';
import 'services/permissions_service.dart';
import 'services/bluetooth_service.dart';
import 'services/share_intent_service.dart';
import 'services/tray_service.dart';
import 'services/webrtc_service.dart';
import 'services/websocket_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WireApp());
}

class ClipboardItem {
  ClipboardItem({required this.text, required this.timestamp, required this.source});

  final String text;
  final DateTime timestamp;
  final String source;
}

class TransferItem {
  TransferItem({
    required this.id,
    required this.name,
    required this.total,
    required this.direction,
    required this.path,
    this.progress = 0,
    this.status = 'pending',
  });

  final String id;
  final String name;
  final int total;
  final String direction;
  final String path;
  double progress;
  String status;
}

class CallItem {
  CallItem({required this.name, required this.number, required this.type, required this.timestamp});

  final String name;
  final String number;
  final String type;
  final DateTime timestamp;
}


class IncomingCall {
  IncomingCall({required this.number, required this.timestamp});

  final String number;
  final DateTime timestamp;
}

class WireApp extends StatelessWidget {
  const WireApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.light);
    final darkScheme = ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark);
    return MaterialApp(
      title: 'Wire Sync',
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
        scaffoldBackgroundColor: const Color(0xFFF7F7F9),
        navigationBarTheme: const NavigationBarThemeData(
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          labelType: NavigationRailLabelType.all,
          groupAlignment: -0.8,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        navigationBarTheme: const NavigationBarThemeData(
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          labelType: NavigationRailLabelType.all,
          groupAlignment: -0.8,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF171A20),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1C2027),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const WireHomePage(),
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
  final _notificationsService = NotificationsService();
  final _clipboardService = ClipboardService(_platformChannel);
  final _webSocketService = WebSocketService(port: _wsPort);
  final _fileTransferService = FileTransferService(port: _filePort);
  final _discoveryService = DiscoveryService();
  final _shareIntentService = ShareIntentService();
  final _callSyncService = CallSyncService();
  final _callStateService = CallStateService();
  final _bluetoothService = BluetoothService();
  final _trayService = TrayService();
  final _networkInfoService = NetworkInfoService();
  final _peerController = TextEditingController();
  final _dialController = TextEditingController();
  final _btIpController = TextEditingController();
  final _textController = TextEditingController();
  final _incomingTextController = TextEditingController();
  late final WebRtcService _webrtcService;

  String _deviceId = '';
  String _peerHost = '';
  List<String> _localIps = [];
  bool _discoveryEnabled = true;
  bool _autoConnectEnabled = true;
  int _currentIndex = 0;
  bool _connecting = false;
  final List<ClipboardItem> _clipboardHistory = [];
  final List<TransferItem> _transfers = [];
  final List<CallItem> _calls = [];
  final Map<String, String> _sentFilePaths = {};
  static const int _maxClipboardItems = 40;
  static const int _maxTransferItems = 40;
  static const Duration _minClipboardSendInterval = Duration(milliseconds: 1500);
  DateTime? _lastClipboardSentAt;
  String? _lastClipboardSentText;
  bool _clipboardStarted = false;
  bool _shareStarted = false;
  bool _callServicesStarted = false;
  bool _syncPaused = false;
  bool _liveTypingEnabled = false;
  Timer? _liveTypingTimer;
  String _lastLiveText = '';
  bool _accessibilityEnabled = false;
  bool _clipboardHistoryEnabled = true;
  bool _transferHistoryEnabled = true;
  bool _dragActive = false;
  StreamSubscription<String>? _clipboardSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  StreamSubscription<List<String>>? _shareSub;
  StreamSubscription<FileReceiveProgress>? _receiveProgressSub;
  StreamSubscription<FileReceiveProgress>? _receiveCompleteSub;
  StreamSubscription<CallEvent>? _callSub;
  StreamSubscription<CallStateEvent>? _callStateSub;
  StreamSubscription<List<BluetoothPeer>>? _bluetoothSub;
  IncomingCall? _incomingCall;
  bool _webrtcInCall = false;
  bool _webrtcIncoming = false;
  bool _webrtcMuted = false;
  String _webrtcStatus = 'idle';
  bool _bluetoothScanning = false;
  List<BluetoothPeer> _bluetoothPeers = [];
  String _pairedBluetoothId = '';
  String _pairedBluetoothName = '';
  String _pairedBluetoothIp = '';
  int _remoteFilePort = _filePort;

  @override
  void initState() {
    super.initState();
    _webrtcService = WebRtcService(
      onSignal: (type, payload) => _webSocketService.send({'type': type, ...payload, 'from': _deviceId}),
      onStateChanged: (state) {
        if (!mounted) return;
        setState(() => _webrtcStatus = state);
      },
    );
    _textController.addListener(_handleLiveTypingChange);
    _init();
  }

  Future<void> _init() async {
    await _permissionsService.requestAll();
    await _notificationsService.init();

    _deviceId = await _identity.getOrCreateDeviceId();
    final prefs = await SharedPreferences.getInstance();
    _peerHost = prefs.getString('peer_host') ?? '';
    _peerController.text = _peerHost;
    _pairedBluetoothId = prefs.getString('bt_peer_id') ?? '';
    _pairedBluetoothName = prefs.getString('bt_peer_name') ?? '';
    _pairedBluetoothIp = prefs.getString('bt_peer_ip') ?? '';
    _btIpController.text = _pairedBluetoothIp;
    _discoveryEnabled = prefs.getBool('discovery_enabled') ?? true;
    _autoConnectEnabled = prefs.getBool('auto_connect') ?? true;
    _clipboardHistoryEnabled = prefs.getBool('clipboard_history_enabled') ?? false;
    _transferHistoryEnabled = prefs.getBool('transfer_history_enabled') ?? false;

    await _webSocketService.startServer();
    await _fileTransferService.startServer();
    _wsSub = _webSocketService.messages.listen(_handleIncomingMessage);

    _receiveProgressSub = _fileTransferService.receiveProgress.listen(_handleReceiveProgress);
    _receiveCompleteSub = _fileTransferService.receiveComplete.listen(_handleReceiveComplete);

    _bluetoothSub = _bluetoothService.peers.listen((peers) {
      if (!mounted) return;
      setState(() => _bluetoothPeers = peers);
    });

    _localIps = await _networkInfoService.getLocalIPv4Addresses();

    await _startDiscovery();

    if (_autoConnectEnabled && _peerHost.isNotEmpty) {
      _connectToPeer(_peerHost);
    } else if (_autoConnectEnabled && _pairedBluetoothIp.isNotEmpty) {
      _connectToPeer(_pairedBluetoothIp);
    }
    if (Platform.isAndroid) {
      await _refreshAccessibilityStatus();
    }
    await _handlePageChange(_currentIndex, notify: false);
    await _initTray();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _handlePageChange(int index, {bool notify = true}) async {
    if (notify) {
      setState(() => _currentIndex = index);
    }
    if (index == 1 || index == 2) {
      await _ensureClipboardServiceStarted();
    }
    if (index == 3) {
      await _ensureShareServiceStarted();
    }
    if (index == 4) {
      await _ensureCallServicesStarted();
    }
    if (index == 2 && Platform.isAndroid) {
      await _refreshAccessibilityStatus();
    }
    if (_autoConnectEnabled) {
      await _ensureConnected();
    }
  }

  Future<bool> _ensureConnected() async {
    final connected = _webSocketService.isClientConnected || _webSocketService.hasServerClients;
    if (connected) return true;
    final target = _peerHost.isNotEmpty ? _peerHost : _pairedBluetoothIp;
    if (target.isEmpty) return false;
    await _connectToPeer(target);
    return _webSocketService.isClientConnected || _webSocketService.hasServerClients;
  }

  Future<void> _refreshAccessibilityStatus() async {
    try {
      final enabled = await _platformChannel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
      if (mounted) {
        setState(() => _accessibilityEnabled = enabled);
      } else {
        _accessibilityEnabled = enabled;
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _platformChannel.invokeMethod('openAccessibilitySettings');
    } catch (_) {
      // ignore
    }
  }

  Future<void> _sendInputInjection(String text) async {
    try {
      await _platformChannel.invokeMethod('inputText', {'text': text});
    } catch (_) {
      // ignore
    }
  }

  Future<void> _ensureClipboardServiceStarted() async {
    if (_clipboardStarted) return;
    _clipboardStarted = true;
    _clipboardSub = _clipboardService.onClipboardChanged.listen(_handleLocalClipboardChange);
    await _clipboardService.start();
  }

  Future<void> _ensureShareServiceStarted() async {
    if (_shareStarted) return;
    _shareStarted = true;
    _shareIntentService.start();
    _shareSub = _shareIntentService.sharedFiles.listen(_handleSharedFiles);
  }

  Future<void> _ensureCallServicesStarted() async {
    if (_callServicesStarted) return;
    _callServicesStarted = true;
    _callSyncService.start();
    _callSub = _callSyncService.callEvents.listen(_handleLocalCallEvent);
    _callStateService.start();
    _callStateSub = _callStateService.events.listen(_handleLocalCallState);
  }

  Future<void> _initTray() async {
    if (!Platform.isMacOS) return;
    final connected = _webSocketService.isClientConnected || _webSocketService.hasServerClients;
    await _trayService.init(
      title: 'Wire Sync',
      clipboardItems: _clipboardHistory.map((e) => e.text).toList(),
      transferItems: _transfers.map((e) => '${e.direction}: ${e.name}').toList(),
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

  Future<void> _refreshTray() async {
    if (!Platform.isMacOS) return;
    final connected = _webSocketService.isClientConnected || _webSocketService.hasServerClients;
    await _trayService.updateMenu(
      clipboardItems: _clipboardHistory.map((e) => e.text).toList(),
      transferItems: _transfers.map((e) => '${e.direction}: ${e.name}').toList(),
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
        if (_peerHost.isEmpty || _peerHost != info.address.address) {
          _peerHost = info.address.address;
          _peerController.text = _peerHost;
          _remoteFilePort = info.filePort;
          _connectToPeer(_peerHost, port: info.wsPort);
        }
      },
    );
  }

  Future<void> _connectToPeer(String host, {int? port}) async {
    if (host.isEmpty) return;
    if (mounted) {
      setState(() => _connecting = true);
    }
    try {
      await _webSocketService.connectToPeer(host, portOverride: port);
      final primaryIp = _localIps.isNotEmpty ? _localIps.first : '';
      _webSocketService.send({
        'type': 'hello',
        'host': primaryIp,
        'filePort': _filePort,
        'from': _deviceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      await _sendCurrentClipboard();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('peer_host', host);
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Path copied')));
  }

  Future<void> _revealFile(String path) async {
    if (!Platform.isMacOS) return;
    await _platformChannel.invokeMethod('revealInFinder', {'path': path});
  }

  void _handleLocalClipboardChange(String text) {
    if (_syncPaused) return;
    if (_lastClipboardSentText == text &&
        _lastClipboardSentAt != null &&
        DateTime.now().difference(_lastClipboardSentAt!) < _minClipboardSendInterval) {
      return;
    }
    _lastClipboardSentText = text;
    _lastClipboardSentAt = DateTime.now();
    _clipboardService.markLocal(text);
    _addClipboardHistory(text, source: 'Local');
    _webSocketService.send({
      'type': 'clipboard',
      'text': text,
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _sendCurrentClipboard() async {
    final text = await _clipboardService.getClipboardText();
    if (text == null || text.isEmpty) return;
    _clipboardService.markLocal(text);
    _handleLocalClipboardChange(text);
  }

  Future<void> _handleIncomingMessage(Map<String, dynamic> message) async {
    final type = message['type']?.toString() ?? '';
        if (_syncPaused && type != 'ping' && type != 'pong') {
          return;
        }
    final from = message['from']?.toString() ?? '';
    if (from == _deviceId) {
      return;
    }

    if (_peerHost.isEmpty) {
      final last = _webSocketService.lastClientAddress ?? '';
      if (last.isNotEmpty) {
        _peerHost = last;
        _peerController.text = last;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('peer_host', last);
      }
    }

    if (type == 'hello') {
      final host = message['host']?.toString() ?? '';
      final filePort = int.tryParse(message['filePort']?.toString() ?? '') ?? _filePort;
      if (host.isNotEmpty && host != _peerHost) {
        _peerHost = host;
        _peerController.text = host;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('peer_host', host);
      }
      _remoteFilePort = filePort;
      return;
    }

    if (type == 'clipboard') {
      final text = message['text']?.toString() ?? '';
      if (!_clipboardService.shouldIgnoreIncoming(text)) {
        await _clipboardService.setClipboardText(text);
        _addClipboardHistory(text, source: 'Remote');
        await _notificationsService.showNotification(title: 'Clipboard synced', body: text);
      }
      return;
    }

    if (type == 'call') {
      final number = message['number']?.toString() ?? '';
      final name = message['name']?.toString() ?? '';
      final callType = message['callType']?.toString() ?? 'unknown';
      final ts = int.tryParse(message['timestamp']?.toString() ?? '') ?? 0;
      if (ts > 0) {
        _addCallHistory(CallItem(name: name, number: number, type: callType, timestamp: DateTime.fromMillisecondsSinceEpoch(ts)));
        await _notificationsService.showNotification(title: 'Call on phone', body: '$callType • $name $number');
      }
      return;
    }

    if (type == 'call_state') {
      final state = message['state']?.toString() ?? 'unknown';
      final number = message['number']?.toString() ?? '';
      final ts = int.tryParse(message['timestamp']?.toString() ?? '') ?? 0;
      if (state == 'ringing' && ts > 0) {
        setState(() => _incomingCall = IncomingCall(number: number, timestamp: DateTime.fromMillisecondsSinceEpoch(ts)));
        await _notificationsService.showNotification(title: 'Incoming call', body: number.isEmpty ? 'Unknown number' : number);
      } else if (state == 'idle' || state == 'offhook') {
        if (_incomingCall != null) {
          setState(() => _incomingCall = null);
        }
      }
      return;
    }

    if (type == 'dial') {
      final number = message['number']?.toString() ?? '';
      if (Platform.isAndroid && number.isNotEmpty) {
        await _platformChannel.invokeMethod('startDial', {'number': number});
      }
      return;
    }

    if (type == 'webrtc_offer') {
      _webrtcService.storeOffer(message);
      setState(() {
        _webrtcIncoming = true;
        _webrtcInCall = false;
      });
      return;
    }

    if (type == 'webrtc_answer') {
      await _webrtcService.handleAnswer(message);
      setState(() {
        _webrtcInCall = true;
        _webrtcIncoming = false;
        _webrtcMuted = false;
      });
      return;
    }

    if (type == 'webrtc_ice') {
      await _webrtcService.handleIce(message);
      return;
    }

    if (type == 'webrtc_hangup') {
      await _webrtcService.hangup(notify: false);
      setState(() {
        _webrtcInCall = false;
        _webrtcIncoming = false;
        _webrtcMuted = false;
      });
      return;
    }

    if (type == 'answer_call') {
      if (Platform.isAndroid) {
        await _platformChannel.invokeMethod('answerCall');
      }
      return;
    }

    if (type == 'mute_call') {
      if (Platform.isAndroid) {
        await _platformChannel.invokeMethod('setPhoneMute', {'mute': message['mute'] == true});
      }
      return;
    }

    if (type == 'decline_call') {
      if (Platform.isAndroid) {
        await _platformChannel.invokeMethod('declineCall');
      }
      return;
    }

    if (type == 'file') {
      final name = message['name']?.toString() ?? '';
      if (name.isNotEmpty) {
        await _notificationsService.showNotification(title: 'File incoming', body: name);
      }
      return;
    }

    if (type == 'file_request') {
      final name = message['name']?.toString() ?? '';
      final path = _sentFilePaths[name];
      if (path != null && path.isNotEmpty) {
        await _sendFile(path);
      } else {
        await _notificationsService.showNotification(title: 'File not found', body: name);
      }
      return;
    }

    if (type == 'type_text' || type == 'type_text_live') {
      final text = message['text']?.toString() ?? '';
      if (type == 'type_text_live' && Platform.isAndroid) {
        if (!_accessibilityEnabled) {
          await _refreshAccessibilityStatus();
        }
        if (_accessibilityEnabled) {
          await _sendInputInjection(text);
          return;
        }
      }
      if (type == 'type_text_live' && Platform.isMacOS) {
        _incomingTextController.text = text;
        _incomingTextController.selection = TextSelection.fromPosition(
          TextPosition(offset: _incomingTextController.text.length),
        );
      }
      if (text.isNotEmpty) {
        await _clipboardService.setClipboardText(text);
        _addClipboardHistory(text, source: type == 'type_text_live' ? 'Live typing' : 'Text input');
        if (type != 'type_text_live') {
          await _notificationsService.showNotification(title: 'Text received', body: text);
        }
      } else if (type == 'type_text_live') {
        await _clipboardService.setClipboardText('');
      }
    }
  }

  void _handleSharedFiles(List<String> paths) {
    for (final path in paths) {
      _sendFile(path);
    }
  }

  Future<void> _sendFile(String path) async {
    if (_peerHost.isEmpty) {
      final fallback = _webSocketService.lastClientAddress ?? '';
      if (fallback.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No peer IP. Connect first.')));
        }
        return;
      }
      _peerHost = fallback;
      _peerController.text = fallback;
    }
    final total = await File(path).length();
    final name = p.basename(path);
    final id = '${DateTime.now().millisecondsSinceEpoch}-$name';
    final transfer = TransferItem(id: id, name: name, total: total, direction: 'send', path: path, status: 'sending');
    setState(() {
      if (!_transferHistoryEnabled) {
        _transfers.clear();
      }
      _transfers.insert(0, transfer);
      _trimTransfers();
    });
    _sentFilePaths[name] = path;
    _refreshTray();

    _webSocketService.send({
      'type': 'file',
      'name': name,
      'size': total,
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    try {
      await _fileTransferService.sendFile(
        filePath: path,
        host: _peerHost,
        port: _remoteFilePort,
        onProgress: (sent, total) {
          setState(() {
            transfer.progress = total == 0 ? 0 : sent / total;
            transfer.status = sent >= total ? 'done' : 'sending';
          });
          _refreshTray();
        },
      );
    } catch (error) {
      final fallbackPort = _remoteFilePort == _filePort ? _filePort + 1 : _filePort;
      if (_remoteFilePort != fallbackPort) {
        try {
          await _fileTransferService.sendFile(
            filePath: path,
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
      await _notificationsService.showNotification(title: 'File send failed', body: '$name\n$error\n$hint');
    }
  }

  void _handleReceiveProgress(FileReceiveProgress progress) {
    final existing = _transfers.where((item) => item.path == progress.path).toList();
    if (existing.isEmpty) {
      final item = TransferItem(
        id: progress.path,
        name: progress.name,
        total: progress.total,
        direction: 'receive',
        path: progress.path,
        status: 'receiving',
      );
      item.progress = progress.total == 0 ? 0 : progress.received / progress.total;
      setState(() {
        if (!_transferHistoryEnabled) {
          _transfers.clear();
        }
        _transfers.insert(0, item);
        _trimTransfers();
      });
      _refreshTray();
    } else {
      setState(() {
        final item = existing.first;
        item.progress = progress.total == 0 ? 0 : progress.received / progress.total;
        item.status = 'receiving';
      });
      _refreshTray();
    }
  }

  Future<void> _handleReceiveComplete(FileReceiveProgress progress) async {
    setState(() {
      final item = _transfers.firstWhere((element) => element.path == progress.path, orElse: () {
        final newItem = TransferItem(
          id: progress.path,
          name: progress.name,
          total: progress.total,
          direction: 'receive',
          path: progress.path,
        );
        if (!_transferHistoryEnabled) {
          _transfers.clear();
        }
        _transfers.insert(0, newItem);
        _trimTransfers();
        return newItem;
      });
      item.progress = 1;
      item.status = 'done';
    });
    _refreshTray();
    await _notificationsService.showNotification(title: 'File received', body: '${progress.name}\n${progress.path}');
  }

  void _handleLocalCallEvent(CallEvent event) {
    final callItem = CallItem(name: event.name, number: event.number, type: event.type, timestamp: event.timestamp);
    _addCallHistory(callItem);
    _webSocketService.send({
      'type': 'call',
      'callType': event.type,
      'name': event.name,
      'number': event.number,
      'from': _deviceId,
      'timestamp': event.timestamp.millisecondsSinceEpoch,
    });
  }

  void _handleLocalCallState(CallStateEvent event) {
    if (event.isRinging) {
      setState(() => _incomingCall = IncomingCall(number: event.number, timestamp: event.timestamp));
    } else if (event.state == 'idle' || event.state == 'offhook') {
      if (_incomingCall != null) {
        setState(() => _incomingCall = null);
      }
    }
    _webSocketService.send({
      'type': 'call_state',
      'state': event.state,
      'number': event.number,
      'from': _deviceId,
      'timestamp': event.timestamp.millisecondsSinceEpoch,
    });
  }

  Future<void> _sendAnswerCall() async {
    _webSocketService.send({
      'type': 'answer_call',
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await _notificationsService.showNotification(title: 'Answer request sent', body: 'Attempting to answer call on phone');
  }

  Future<void> _sendDeclineCall() async {
    _webSocketService.send({
      'type': 'decline_call',
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await _notificationsService.showNotification(title: 'Decline request sent', body: 'Best-effort on phone');
  }

  Future<void> _requestFileResend(String name) async {
    final target = _peerHost.isNotEmpty ? _peerHost : (_webSocketService.lastClientAddress ?? '');
    if (target.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No peer connected')));
      }
      return;
    }
    _webSocketService.send({
      'type': 'file_request',
      'name': name,
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _sendTextInput() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final target = _peerHost.isNotEmpty ? _peerHost : (_webSocketService.lastClientAddress ?? '');
    if (target.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No peer connected')));
      }
      return;
    }
    _webSocketService.send({
      'type': 'type_text',
      'text': text,
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    _textController.clear();
  }

  void _handleDroppedFiles(List<String> paths) {
    for (final path in paths) {
      if (path.isNotEmpty) {
        _sendFile(path);
      }
    }
  }

  void _handleLiveTypingChange() {
    if (!_liveTypingEnabled) return;
    final text = _textController.text;
    if (text == _lastLiveText) return;
    _liveTypingTimer?.cancel();
    _liveTypingTimer = Timer(const Duration(milliseconds: 120), () {
      final target = _peerHost.isNotEmpty ? _peerHost : (_webSocketService.lastClientAddress ?? '');
      if (target.isEmpty) return;
      _lastLiveText = text;
      _webSocketService.send({
        'type': 'type_text_live',
        'text': text,
        'from': _deviceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<void> _sendMuteCall(bool mute) async {
    _webSocketService.send({
      'type': 'mute_call',
      'mute': mute,
      'from': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _startVoipCall() async {
    await _webrtcService.startCall();
    setState(() {
      _webrtcInCall = true;
      _webrtcIncoming = false;
      _webrtcMuted = false;
    });
  }

  Future<void> _acceptVoipCall() async {
    await _webrtcService.acceptCall();
    setState(() {
      _webrtcInCall = true;
      _webrtcIncoming = false;
      _webrtcMuted = false;
    });
  }

  Future<void> _declineVoipCall() async {
    await _webrtcService.declineCall();
    setState(() {
      _webrtcIncoming = false;
    });
  }

  Future<void> _hangupVoipCall() async {
    await _webrtcService.hangup();
    setState(() {
      _webrtcInCall = false;
      _webrtcIncoming = false;
      _webrtcMuted = false;
    });
  }

  Future<void> _toggleVoipMute() async {
    final next = !_webrtcMuted;
    await _webrtcService.setMute(next);
    setState(() => _webrtcMuted = next);
  }

  void _clearClipboardHistory() {
    setState(() => _clipboardHistory.clear());
    _refreshTray();
  }

  void _clearTransfers() {
    setState(() => _transfers.clear());
    _refreshTray();
  }

  void _addClipboardHistory(String text, {required String source}) {
    setState(() {
      if (!_clipboardHistoryEnabled) {
        _clipboardHistory
          ..clear()
          ..add(ClipboardItem(text: text, timestamp: DateTime.now(), source: source));
      } else {
        _clipboardHistory.insert(0, ClipboardItem(text: text, timestamp: DateTime.now(), source: source));
        if (_clipboardHistory.length > _maxClipboardItems) {
          _clipboardHistory.removeLast();
        }
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

  void _addCallHistory(CallItem item) {
    setState(() {
      _calls.insert(0, item);
      if (_calls.length > 50) {
        _calls.removeLast();
      }
    });
  }

  @override
  void dispose() {
    _clipboardSub?.cancel();
    _wsSub?.cancel();
    _shareSub?.cancel();
    _receiveProgressSub?.cancel();
    _receiveCompleteSub?.cancel();
    _callSub?.cancel();
    _callStateSub?.cancel();
    _bluetoothSub?.cancel();
    _peerController.dispose();
    _dialController.dispose();
    _btIpController.dispose();
    _textController.removeListener(_handleLiveTypingChange);
    _textController.dispose();
    _incomingTextController.dispose();
    _clipboardService.dispose();
    _webSocketService.dispose();
    _fileTransferService.dispose();
    _discoveryService.stop();
    _shareIntentService.dispose();
    _callSyncService.dispose();
    _webrtcService.hangup(notify: false);
    _callStateService.dispose();
    _bluetoothService.dispose();
    super.dispose();
  }

  Future<void> _startBluetoothScan() async {
    setState(() => _bluetoothScanning = true);
    try {
      await _bluetoothService.startScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    if (!mounted) return;
    setState(() => _bluetoothScanning = false);
  }

  Future<void> _pairBluetooth(BluetoothPeer peer) async {
    final ok = await _bluetoothService.connect(peer.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bt_peer_id', peer.id);
    await prefs.setString('bt_peer_name', peer.name);
    if (!mounted) return;
    setState(() {
      _pairedBluetoothId = peer.id;
      _pairedBluetoothName = peer.name;
    });
    await _notificationsService.showNotification(
      title: ok ? 'Bluetooth paired' : 'Bluetooth pairing pending',
      body: peer.name,
    );
  }

  Future<void> _saveBluetoothPeerIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bt_peer_ip', ip);
    if (!mounted) return;
    setState(() {
      _pairedBluetoothIp = ip;
      _btIpController.text = ip;
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = _webSocketService.isClientConnected || _webSocketService.hasServerClients;
    final primaryIp = _localIps.isNotEmpty ? _localIps.first : '';
    final pages = <Widget>[
      _buildConnectionPage(connected: connected, primaryIp: primaryIp),
      _buildClipboardTab(),
      _buildKeyboardPage(),
      _buildTransfersTab(),
      _buildCallsTab(),
      _buildSettingsPage(),
    ];
    final navDestinations = const [
      NavigationDestination(icon: Icon(Icons.link), label: 'Connect'),
      NavigationDestination(icon: Icon(Icons.copy), label: 'Clipboard'),
      NavigationDestination(icon: Icon(Icons.keyboard), label: 'Keyboard'),
      NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Transfers'),
      NavigationDestination(icon: Icon(Icons.call), label: 'Calls'),
      NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Wire Sync'),
            const SizedBox(width: 10),
            _buildStatusDot(connected: connected, connecting: _connecting),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Connect',
            onPressed: _connecting ? null : () => _connectToPeer(_peerController.text.trim()),
            icon: _connecting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.link),
          ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragActive = true),
        onDragExited: (_) => setState(() => _dragActive = false),
        onDragDone: (details) {
          setState(() => _dragActive = false);
          final paths = details.files.map((f) => f.path).toList();
          _handleDroppedFiles(paths);
        },
        child: Stack(
          children: [
            Row(
              children: [
                if (Platform.isMacOS)
                  NavigationRail(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (value) => _handlePageChange(value),
                    labelType: NavigationRailLabelType.all,
                    destinations: navDestinations
                        .map(
                          (d) => NavigationRailDestination(icon: d.icon, label: Text(d.label)),
                        )
                        .toList(),
                  ),
                Expanded(child: pages[_currentIndex]),
              ],
            ),
            if (_dragActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(0.1),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                        ),
                        child: const Text('Drop files to send'),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Platform.isMacOS
          ? null
          : NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (value) => _handlePageChange(value),
              destinations: navDestinations,
            ),
    );
  }

  Widget _buildClipboardTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _sendCurrentClipboard,
                icon: const Icon(Icons.sync),
                label: const Text('Sync clipboard now'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _clipboardHistory.isEmpty ? null : _clearClipboardHistory,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear history'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile(
                  value: _clipboardHistoryEnabled,
                  onChanged: (value) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('clipboard_history_enabled', value);
                    setState(() => _clipboardHistoryEnabled = value);
                    if (!value) {
                      _clearClipboardHistory();
                    }
                  },
                  title: const Text('History'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Expanded(
                child: Text(
                  'Clipboard sync is automatic. Use this if it falls out of sync.',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _clipboardHistory.isEmpty
              ? const Center(child: Text('Clipboard history will appear here.'))
              : ListView.builder(
                  itemCount: _clipboardHistory.length,
                  itemBuilder: (context, index) {
                    final item = _clipboardHistory[index];
                    return ListTile(
                      title: Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${item.source} • ${item.timestamp}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () => _clipboardService.setClipboardText(item.text),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildKeyboardPage() {
    final connected = _webSocketService.isClientConnected || _webSocketService.hasServerClients;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Text Input Proxy', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Send text to your other device. It will be copied to the clipboard there for quick paste.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          value: _clipboardHistoryEnabled,
                          onChanged: (value) async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('clipboard_history_enabled', value);
                            setState(() => _clipboardHistoryEnabled = value);
                            if (!value) {
                              _clearClipboardHistory();
                            }
                          },
                          title: const Text('Full history'),
                          subtitle: const Text('Off = single recent item'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _clipboardHistory.isEmpty ? null : _clearClipboardHistory,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    value: _liveTypingEnabled,
                    onChanged: (value) {
                      setState(() => _liveTypingEnabled = value);
                      if (value) {
                        _handleLiveTypingChange();
                      }
                    },
                    title: const Text('Live typing'),
                    subtitle: const Text('Sync every keystroke to the other device.'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (Platform.isAndroid)
                    Row(
                      children: [
                        Icon(
                          _accessibilityEnabled ? Icons.check_circle : Icons.error_outline,
                          color: _accessibilityEnabled ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _accessibilityEnabled
                                ? 'Input injection enabled'
                                : 'Enable Accessibility to type into focused fields',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: _openAccessibilitySettings,
                          child: const Text('Enable'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  if (Platform.isMacOS)
                    TextField(
                      controller: _incomingTextController,
                      readOnly: true,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Incoming live text',
                      ),
                    ),
                  if (Platform.isMacOS) const SizedBox(height: 8),
                  TextField(
                    controller: _textController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Text to send',
                      hintText: 'Type here…',
                    ),
                    onSubmitted: (_) => _sendTextInput(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: connected ? _sendTextInput : null,
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => _textController.clear(),
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                      ),
                      const SizedBox(width: 12),
                      if (!connected)
                        const Expanded(
                          child: Text('Connect to a peer to enable sending.'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _clipboardHistory.isEmpty
                ? const Center(child: Text('Recent text will appear in clipboard history.'))
                : ListView.builder(
                    itemCount: _clipboardHistory.length,
                    itemBuilder: (context, index) {
                      final item = _clipboardHistory[index];
                      return ListTile(
                        leading: const Icon(Icons.text_snippet),
                        title: Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${item.source} • ${item.timestamp}'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionPage({required bool connected, required String primaryIp}) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Connection', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _peerController,
                        decoration: const InputDecoration(
                          labelText: 'Peer IP address',
                          hintText: '192.168.1.10',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _connecting ? null : () => _connectToPeer(_peerController.text.trim()),
                      child: _connecting
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Connect'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(connected ? Icons.check_circle : Icons.wifi_off, color: connected ? Colors.green : Colors.orange),
                    const SizedBox(width: 8),
                    Text(connected ? 'Connected' : 'Disconnected'),
                    const Spacer(),
                    Expanded(
                      child: Text(
                        'Device: $_deviceId',
                        style: Theme.of(context).textTheme.labelSmall,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (_localIps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('This device IP: ${_localIps.join(', ')}', style: Theme.of(context).textTheme.labelSmall),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Bluetooth pairing', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _bluetoothScanning ? null : _startBluetoothScan,
              icon: _bluetoothScanning
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bluetooth_searching),
              label: const Text('Scan Bluetooth'),
            ),
            const SizedBox(width: 12),
            if (_pairedBluetoothId.isNotEmpty)
              Expanded(
                child: Text('Paired: $_pairedBluetoothName', overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
        if (_bluetoothPeers.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _bluetoothPeers.length,
              itemBuilder: (context, index) {
                final peer = _bluetoothPeers[index];
                return SizedBox(
                  width: 200,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(peer.id, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _pairBluetooth(peer),
                              child: const Text('Pair'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (_pairedBluetoothId.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Bluetooth IP sync', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Peer IP for paired device'),
                  controller: _btIpController,
                  onSubmitted: (value) => _saveBluetoothPeerIp(value.trim()),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _pairedBluetoothIp.isEmpty
                    ? null
                    : () => _connectToPeer(_pairedBluetoothIp),
                child: const Text('Connect via Bluetooth'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pairing via Bluetooth lets you store the peer IP for quick connect.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ],
    );
  }

  Widget _buildSettingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Auto connect on launch'),
          value: _autoConnectEnabled,
          onChanged: (value) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('auto_connect', value);
            setState(() => _autoConnectEnabled = value);
          },
        ),
        SwitchListTile(
          title: const Text('Discovery over LAN'),
          value: _discoveryEnabled,
          onChanged: (value) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('discovery_enabled', value);
            setState(() => _discoveryEnabled = value);
            if (value) {
              await _startDiscovery();
            } else {
              await _discoveryService.stop();
            }
          },
        ),
        if (Platform.isAndroid)
          ListTile(
            title: const Text('Run in background'),
            subtitle: const Text('Disabled on Android due to device restrictions.'),
            trailing: const Text('Off'),
          ),
        if (Platform.isMacOS)
          ListTile(
            title: const Text('Hide app (keep running)'),
            subtitle: const Text('Keeps Wire running in the menu bar'),
            trailing: ElevatedButton(
              onPressed: () => _platformChannel.invokeMethod('hideApp'),
              child: const Text('Hide'),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VoIP calling (Wire)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text('1) Connect both devices on the same network.'),
                const Text('2) Open Calls page on both devices.'),
                const Text('3) Tap Start VoIP on one device and Accept on the other.'),
                const Text('4) Use Mute/Hang up to control audio.'),
                const SizedBox(height: 8),
                Text('Phone call control (Android only):', style: Theme.of(context).textTheme.bodySmall),
                const Text('• Call via phone sends a dial request to the Android device.'),
                const Text('• Answer/Mute/Decline work only on Android and require permissions.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransfersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _peerHost.isEmpty
                    ? null
                    : () async {
                        final result = await FilePicker.platform.pickFiles();
                        final path = result?.files.single.path;
                        if (path != null) {
                          _sendFile(path);
                        }
                      },
                icon: const Icon(Icons.upload_file),
                label: const Text('Pick & Send'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _transfers.isEmpty ? null : _clearTransfers,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear transfers'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: SwitchListTile(
                        value: _transferHistoryEnabled,
                        onChanged: (value) async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('transfer_history_enabled', value);
                          setState(() => _transferHistoryEnabled = value);
                          if (!value) {
                            _clearTransfers();
                          }
                        },
                        title: const Text('History'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (Platform.isAndroid)
                      TextButton.icon(
                        onPressed: () => _platformChannel.invokeMethod('openDownloadsFolder'),
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open Downloads'),
                      ),
                    Text('Local HTTP port $_filePort'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _transfers.isEmpty
              ? const Center(child: Text('No file transfers yet.'))
              : ListView.builder(
                  itemCount: _transfers.length,
                  itemBuilder: (context, index) {
                    final item = _transfers[index];
                    return ListTile(
                      leading: Icon(item.direction == 'send' ? Icons.upload : Icons.download),
                      title: Text(item.name),
                      subtitle: Text('${item.direction} • ${item.status}\n${item.path}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: _buildTransferActions(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTransferActions(TransferItem item) {
    if (item.status != 'done') {
      return SizedBox(
        width: 120,
        child: LinearProgressIndicator(value: item.progress),
      );
    }
    if (item.direction == 'receive') {
      return Wrap(
        spacing: 8,
        children: [
          IconButton(
            tooltip: 'Copy path',
            icon: const Icon(Icons.copy),
            onPressed: () => _copyPath(item.path),
          ),
          if (Platform.isMacOS)
            IconButton(
              tooltip: 'Show in Finder',
              icon: const Icon(Icons.folder_open),
              onPressed: () => _revealFile(item.path),
            ),
          IconButton(
            tooltip: 'Re-download',
            icon: const Icon(Icons.refresh),
            onPressed: () => _requestFileResend(item.name),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCallsTab() {
    if (!Platform.isAndroid) {
      final incoming = _incomingCall;
      final canVoip = _webSocketService.isClientConnected || _webSocketService.hasServerClients;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVoipCard(canVoip: canVoip),
            const SizedBox(height: 12),
            if (incoming != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.call, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Incoming call', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(incoming.number.isEmpty ? 'Unknown number' : incoming.number),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _peerHost.isEmpty ? null : _sendAnswerCall,
                        icon: const Icon(Icons.call),
                        label: const Text('Answer on phone'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _peerHost.isEmpty ? null : () => _sendMuteCall(true),
                        icon: const Icon(Icons.mic_off),
                        label: const Text('Mute phone'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _peerHost.isEmpty ? null : _sendDeclineCall,
                        icon: const Icon(Icons.call_end),
                        label: const Text('Decline phone'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text('Place a call via your phone'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dialController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+1 555 123 4567',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    final number = _dialController.text.trim();
                    if (number.isEmpty) return;
                    final ok = await _ensureConnected();
                    if (!ok) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('No peer connected')));
                      }
                      return;
                    }
                    _webSocketService.send({
                      'type': 'dial',
                      'number': number,
                      'from': _deviceId,
                      'timestamp': DateTime.now().millisecondsSinceEpoch,
                    });
                    _notificationsService.showNotification(title: 'Dial request sent', body: number);
                  },
                  child: const Text('Call via phone'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Call notifications will appear below when your phone receives calls.'),
            const SizedBox(height: 12),
            Expanded(
              child: _calls.isEmpty
                  ? const Center(child: Text('No call events yet.'))
                  : ListView.builder(
                      itemCount: _calls.length,
                      itemBuilder: (context, index) {
                        final item = _calls[index];
                        return ListTile(
                          leading: const Icon(Icons.call),
                          title: Text(item.name.isEmpty ? item.number : item.name),
                          subtitle: Text('${item.type} • ${item.timestamp}'),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    }
    if (_calls.isEmpty) {
      final canVoip = _webSocketService.isClientConnected || _webSocketService.hasServerClients;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildVoipCard(canVoip: canVoip),
            const SizedBox(height: 16),
            const Expanded(child: Center(child: Text('No call events yet.'))),
          ],
        ),
      );
    }
    final canVoip = _webSocketService.isClientConnected || _webSocketService.hasServerClients;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildVoipCard(canVoip: canVoip),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _calls.length,
            itemBuilder: (context, index) {
              final item = _calls[index];
              return ListTile(
                leading: const Icon(Icons.call),
                title: Text(item.name.isEmpty ? item.number : item.name),
                subtitle: Text('${item.type} • ${item.timestamp}'),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVoipCard({required bool canVoip}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Wire VoIP Call', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Status: ${_webrtcIncoming ? 'Incoming' : _webrtcInCall ? 'In call' : _webrtcStatus}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: (!canVoip || _webrtcInCall || _webrtcIncoming) ? null : _startVoipCall,
                  icon: const Icon(Icons.phone_in_talk),
                  label: const Text('Start VoIP'),
                ),
                ElevatedButton.icon(
                  onPressed: _webrtcIncoming ? _acceptVoipCall : null,
                  icon: const Icon(Icons.call),
                  label: const Text('Accept'),
                ),
                OutlinedButton.icon(
                  onPressed: _webrtcIncoming ? _declineVoipCall : null,
                  icon: const Icon(Icons.call_end),
                  label: const Text('Decline'),
                ),
                OutlinedButton.icon(
                  onPressed: _webrtcInCall ? _hangupVoipCall : null,
                  icon: const Icon(Icons.call_end),
                  label: const Text('Hang up'),
                ),
                OutlinedButton.icon(
                  onPressed: _webrtcInCall ? _toggleVoipMute : null,
                  icon: Icon(_webrtcMuted ? Icons.mic_off : Icons.mic),
                  label: Text(_webrtcMuted ? 'Unmute' : 'Mute'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDot({required bool connected, required bool connecting}) {
    final color = connecting
        ? Colors.orange
        : connected
            ? Colors.green
            : Colors.red;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.7),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

