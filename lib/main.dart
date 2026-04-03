import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'models/transfer_item.dart';
import 'services/app_identity.dart';
import 'services/background_service.dart';
import 'services/clipboard_service.dart';
import 'services/discovery_service.dart';
import 'services/file_transfer_service.dart';
import 'services/focus_mode_service.dart';
import 'services/handoff_service.dart';
import 'services/history_service.dart';
import 'services/notification_sync_service.dart';
import 'services/notifications_service.dart';
import 'services/pairing_service.dart';
import 'services/permissions_service.dart';
import 'services/tray_service.dart';
import 'services/websocket_service.dart';
import 'ui/pages/control_hub_page.dart';
import 'ui/pages/files_page.dart';
import 'ui/pages/sms_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/onboarding_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/screen_mirror_page.dart';
import 'ui/pages/camera_viewer_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/liquid_glass_dock.dart';
import 'providers/app_state.dart';
import 'providers/sms_provider.dart';
import 'providers/remote_file_provider.dart';
import 'providers/file_transfer_provider.dart';
import 'controllers/clipboard_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppTheme.initThemeMode();
  
  final identityService = AppIdentity();
  final discoveryService = DiscoveryService();
  final pairingService = PairingService();
  final historyService = HistoryService();
  final platformChannel = const MethodChannel('wire/platform');
  final clipboardService = ClipboardService(platformChannel);
  final webSocketService = WebSocketService(port: 5757);
  final fileTransferService = FileTransferService(port: 5758);
  final notificationsService = NotificationsService();
  final notificationSyncService = NotificationSyncService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(
            identityService: identityService,
            discoveryService: discoveryService,
            pairingService: pairingService,
            webSocketService: webSocketService,
            notificationsService: notificationsService,
            notificationSyncService: notificationSyncService,
            fileTransferService: fileTransferService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ClipboardController(
            clipboardService: clipboardService,
            historyService: historyService,
            webSocketService: webSocketService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => FileTransferProvider(
            fileTransferService: fileTransferService,
          ),
        ),
        ChangeNotifierProxyProvider<AppState, SmsProvider>(
          create: (context) => SmsProvider(
            webSocketService: webSocketService,
            deviceId: context.read<AppState>().deviceId,
          ),
          update: (context, appState, previous) => previous ?? SmsProvider(
            webSocketService: webSocketService,
            deviceId: appState.deviceId,
          ),
        ),
        ChangeNotifierProxyProvider<AppState, RemoteFileProvider>(
          create: (context) => RemoteFileProvider(
            fileTransferService: fileTransferService,
            peerHost: '',
            filePort: 5758,
          ),
          update: (context, appState, previous) {
            final active = appState.pairingService.activeDevice;
            previous?.updateHost(active?.lastIp ?? '');
            return previous!;
          },
        ),
      ],
      child: const WireApp(),
    ),
  );
}

class WireApp extends StatefulWidget {
  const WireApp({super.key});

  @override
  State<WireApp> createState() => _WireAppState();
}

class _WireAppState extends State<WireApp> {
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initWithProviders();
  }

  Future<void> _initWithProviders() async {
    final appState = context.read<AppState>();
    final clipboardController = context.read<ClipboardController>();
    
    appState.setClipboardController(clipboardController);
    await appState.init();
    await clipboardController.init();
  }

  Future<void> _resetApplication() async {
    final appState = context.read<AppState>();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await appState.init();
    if (!mounted) return;
    setState(() {
      _initFuture = _initWithProviders();
    });
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_run', false);
    if (!mounted) return;
    context.read<AppState>().setFirstRun(false);
  }

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
          home: FutureBuilder<void>(
            future: _initFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              
              return Consumer<AppState>(
                builder: (context, appState, _) {
                  if (appState.isFirstRun) {
                    return OnboardingPage(
                      onFinish: _completeOnboarding,
                    );
                  }
                  
                  return const WireHomePage();
                },
              );
            },
          ),
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
  final _historyService = HistoryService();
  late final WebSocketService _webSocketService;
  late final FileTransferService _fileTransferService;
  final _trayService = TrayService();
  final _handoffService = HandoffService();
  final _focusModeService = FocusModeService();
  final _permissionsService = PermissionsService();

  final PageController _pageController = PageController();
  int _navigationIndex = 0;
  final List<TransferItem> _transfers = [];
  
  StreamSubscription<FileReceiveProgress>? _receiveProgressSub;
  StreamSubscription<FileReceiveProgress>? _receiveCompleteSub;
  StreamSubscription<Map<String, dynamic>>? _mirrorSub;
  StreamSubscription<Map<String, dynamic>>? _smsSub;
  
  final _backgroundService = BackgroundService();
  final _battery = Battery();

  // Platform-specific: Messages tab only on macOS
  late final List<_NavItem> _navItems;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _webSocketService = app.webSocketService;
    _fileTransferService = app.fileTransferService;
    
    // Build navigation items: Messages only on macOS
    _navItems = [
      const _NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
      const _NavItem(icon: Icons.control_camera_outlined, selectedIcon: Icons.control_camera_rounded, label: 'Control'),
      const _NavItem(icon: Icons.folder_outlined, selectedIcon: Icons.folder_rounded, label: 'Files'),
      if (Platform.isMacOS)
        const _NavItem(icon: Icons.chat_outlined, selectedIcon: Icons.chat_rounded, label: 'Messages'),
      const _NavItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, label: 'Settings'),
    ];
    
    _handoffService.onHandoffReceived.listen(_handleHandoff);
    _focusModeService.onFocusStateChanged.listen((enabled) {
      if (!mounted) return;
      app.setFocusMode(enabled);
      app.notificationsService.setFocusMode(enabled);
      _webSocketService.send({
        'type': 'focus_mode',
        'enabled': enabled,
        'from': app.deviceId,
      });
    });
    _init();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _receiveProgressSub?.cancel();
    _receiveCompleteSub?.cancel();
    _mirrorSub?.cancel();
    _smsSub?.cancel();
    super.dispose();
  }

  void _onNavigationItemTapped(int index) {
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _navigationIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  // Build pages list matching nav items
  List<Widget> _buildPages() {
    final pages = <Widget>[
      const HomePage(),
      const ControlHubPage(padding: EdgeInsets.only(bottom: 120)),
      const FilesPage(padding: EdgeInsets.only(bottom: 120)),
    ];
    if (Platform.isMacOS) {
      pages.add(const SmsPage(padding: EdgeInsets.only(bottom: 120)));
    }
    pages.add(SettingsPage(
      padding: const EdgeInsets.only(bottom: 120),
      onResetApp: () {
        context.findAncestorStateOfType<_WireAppState>()?._resetApplication();
      },
    ));
    return pages;
  }

  Future<void> _init() async {
    final appState = context.read<AppState>();

    await appState.notificationsService.init(onSelectNotification: _onNotificationTap);
    await _focusModeService.init();
    
    if (Platform.isAndroid) {
      await _backgroundService.init();
      await _backgroundService.start();
    }

    _battery.onBatteryStateChanged.listen((state) {
      appState.setBatteryStatus(appState.batteryLevel, state);
      _sendBatteryStatus();
    });
    _battery.batteryLevel.then((level) {
      appState.setBatteryStatus(level, appState.batteryState);
      _sendBatteryStatus();
    });

    _smsSub = _webSocketService.messages.listen((message) {
      if (!mounted) return;
      final type = message['type']?.toString() ?? '';
      if (Platform.isAndroid) {
        _handleAndroidMessage(type, message, appState);
      }
      if (type == 'handoff') {
        final url = message['url']?.toString() ?? '';
        _handleHandoff(url);
      }
    });

    _receiveProgressSub = _fileTransferService.receiveProgress.listen(_handleReceiveProgress);
    _receiveCompleteSub = _fileTransferService.receiveComplete.listen(_handleReceiveComplete);

    _mirrorSub = appState.mirrorRequestStream.listen((data) {
      if (!mounted) return;
      final isCamera = data['isCamera'] == true;
      final renderer = data['renderer'] as RTCVideoRenderer;
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => isCamera 
            ? CameraViewerPage(
                mirrorService: appState.mirrorService,
                onFlipCamera: () => appState.mirrorService.switchCamera(),
              )
            : ScreenMirrorPage(
                mirrorService: appState.mirrorService,
                initialRenderer: renderer,
                onSendFile: (path) => appState.pushFile(path),
                onStop: () => appState.mirrorService.stop(),
              ),
        ),
      );
    });

    final transferHistory = await _historyService.getTransferHistory();
    if (mounted) {
      setState(() {
        _transfers.addAll(transferHistory);
      });
    }

    if (appState.autoConnectEnabled && appState.pairingService.activeDevice != null) {
      appState.reconnect();
    }
    _sendBatteryStatus();
    await _initTray();
  }

  void _handleAndroidMessage(String type, Map<String, dynamic> message, AppState appState) async {
    if (type == 'sms_fetch_request') {
      try {
        final smsGranted = await _permissionsService.requestSms();
        await _permissionsService.requestContacts();
        if (!smsGranted) {
          _webSocketService.send({'type': 'sms_error', 'message': 'READ_SMS denied', 'from': appState.deviceId});
          return;
        }
        final smsList = await _platformChannel.invokeMethod('getRecentSms');
        _webSocketService.send({'type': 'sms_list', 'data': smsList, 'from': appState.deviceId});
      } catch (e) {
        _webSocketService.send({'type': 'sms_error', 'message': e.toString(), 'from': appState.deviceId});
      }
    } else if (type == 'sms_send_request') {
      try {
        final granted = await _permissionsService.requestSms();
        if (!granted) {
          _webSocketService.send({'type': 'sms_error', 'message': 'SEND_SMS denied', 'from': appState.deviceId});
          return;
        }
        await _platformChannel.invokeMethod('sendSms', {
          'number': message['number']?.toString() ?? '',
          'message': message['message']?.toString() ?? '',
        });
      } catch (e) {
        _webSocketService.send({'type': 'sms_error', 'message': e.toString(), 'from': appState.deviceId});
      }
    }
  }

  Future<void> _initTray() async {
    if (!Platform.isMacOS) return;
    final appState = context.read<AppState>();
    final clipboardController = context.read<ClipboardController>();
    
    await _trayService.init(
      title: 'Wire Sync',
      clipboardItems: clipboardController.history.map((e) => e.text).toList(),
      transferItems: _transfers.map((e) => e.name).toList(),
      paused: appState.isSyncPaused,
      discoveryEnabled: appState.discoveryEnabled,
      connected: _webSocketService.isClientConnected,
      onShow: () => _platformChannel.invokeMethod('activateApp'),
      onTogglePause: () => appState.toggleSetting('sync_paused', !appState.isSyncPaused),
      onToggleDiscovery: () => appState.toggleSetting('discovery_enabled', !appState.discoveryEnabled),
      onDisconnect: () => _webSocketService.disconnectClient(),
      onQuit: () => exit(0),
    );
  }

  void _handleHandoff(String url) async {
    if (url.isEmpty) return;
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isAndroid) {
      try {
        await _platformChannel.invokeMethod('openUrl', {'url': url});
      } catch (_) {
        // Fallback: just log it
        debugPrint('Failed to open URL: $url');
      }
    }
  }

  void _onNotificationTap(NotificationResponse response) {}

  void _sendBatteryStatus() {
    final appState = context.read<AppState>();
    _webSocketService.send({
      'type': 'status',
      'battery': appState.batteryLevel,
      'isCharging': appState.batteryState == BatteryState.charging,
    });
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
        startTime: DateTime.now(),
      );
      item.progress = progress.total == 0 ? 0 : progress.received / progress.total;
      item.bytesTransferred = progress.received;
      if (mounted) setState(() => _transfers.insert(0, item));
    } else {
      if (mounted) {
        setState(() {
          final item = existing.first;
          item.progress = progress.total == 0 ? 0 : progress.received / progress.total;
          item.status = 'receiving';
          item.bytesTransferred = progress.received;
        });
      }
    }
  }

  Future<void> _handleReceiveComplete(FileReceiveProgress progress) async {
    final app = context.read<AppState>();
    if (mounted) {
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
            return newItem;
          },
        );
        item.status = 'complete';
        item.progress = 1.0;
        _historyService.saveTransfer(item);
      });
    }
    app.updateLastSync();
    await app.notificationsService.showNotification(
      title: 'File received',
      body: '${progress.name} saved to Downloads',
      payload: 'file:${progress.path}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppState, ClipboardController>(
      builder: (context, appState, clipboardController, _) {
        final scheme = Theme.of(context).colorScheme;
        final isPeerConnected = appState.pairingService.activeDevice != null;
        final pages = _buildPages();
        
        return Scaffold(
          backgroundColor: scheme.surface,
          body: DropTarget(
            onDragDone: (detail) async {
              if (detail.files.isNotEmpty && isPeerConnected) {
                 final file = detail.files.first;
                 try {
                   await appState.pushFile(file.path);
                 } catch (e) {
                   if (context.mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('Send failed: $e'), backgroundColor: scheme.error),
                     );
                   }
                 }
              } else if (!isPeerConnected) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('Connect a device first')),
                 );
              }
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.surface,
                    scheme.surfaceContainerHighest.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  PageView(
                    controller: _pageController,
                    onPageChanged: (index) => setState(() => _navigationIndex = index),
                    children: pages,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: Center(
                      child: LiquidGlassDock(
                        items: _navItems.map((n) => LiquidGlassDockItem(
                          icon: n.icon,
                          selectedIcon: n.selectedIcon,
                          label: n.label,
                        )).toList(),
                        selectedIndex: _navigationIndex,
                        onSelect: (index) {
                          _onNavigationItemTapped(index);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem({required this.icon, required this.selectedIcon, required this.label});
}
