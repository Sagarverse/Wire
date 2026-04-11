import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'ui/widgets/received_file_popup.dart';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';


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
import 'services/webrtc_p2p_service.dart';
import 'ui/pages/control_hub_page.dart';
import 'ui/pages/files_page.dart';
import 'ui/pages/sms_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/onboarding_page.dart';
import 'ui/pages/settings_page.dart';

import 'ui/theme/app_theme.dart';
import 'ui/widgets/liquid_glass_dock.dart';
import 'providers/app_state.dart';
import 'providers/sms_provider.dart';
import 'providers/remote_file_provider.dart';
import 'providers/file_transfer_provider.dart';
import 'controllers/clipboard_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (args.isNotEmpty && args.first == 'received_file') {
    final Map<String, dynamic> data = jsonDecode(args[1]);
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: ReceivedFileWindow(data: data),
    ));
    return;
  }

  await AppTheme.initThemeMode();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    await windowManager.ensureInitialized();
  }

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
  final webrtcP2PService = WebRTCP2PService();

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
            webrtcP2PService: webrtcP2PService,
          ),
        ),
        ChangeNotifierProxyProvider<AppState, ClipboardController>(
          create: (context) => ClipboardController(
            clipboardService: clipboardService,
            historyService: historyService,
            onSendMessage: context.read<AppState>().sendMessage,
          ),
          update: (context, appState, previous) => previous ?? ClipboardController(
            clipboardService: clipboardService,
            historyService: historyService,
            onSendMessage: appState.sendMessage,
          ),
        ),
        Provider<HistoryService>.value(value: historyService),
        ChangeNotifierProvider(
          create: (_) => FileTransferProvider(
            fileTransferService: fileTransferService,
            historyService: historyService,
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
            appState: context.read<AppState>(),
          ),
          update: (context, appState, previous) {
            final active = appState.pairingService.activeDevice;
            previous?.updateConnectionInfo(active?.lastIp ?? '', active?.filePort ?? 5758);
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
    await Future.wait([
      appState.init(),
      clipboardController.init(),
    ]);
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

  late final WebSocketService _webSocketService;
  late final FileTransferService _fileTransferService;
  final _trayService = TrayService();
  final _handoffService = HandoffService();
  final _focusModeService = FocusModeService();
  final _permissionsService = PermissionsService();

  final PageController _pageController = PageController();
  int _navigationIndex = 0;

  StreamSubscription<FileReceiveProgress>? _receiveCompleteSub;

  StreamSubscription<Map<String, dynamic>>? _smsSub;

  final _backgroundService = BackgroundService();
  final _battery = Battery();

  // Platform-specific: Messages tab only on macOS
  late final List<_NavItem> _navItems;

  FileReceiveProgress? _pendingPopup;

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
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS)
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
    _receiveCompleteSub?.cancel();

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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
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

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
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
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        _handleAndroidMessage(type, message, appState);
      }
      if (type == 'handoff') {
        final url = message['url']?.toString() ?? '';
        _handleHandoff(url);
      }
    });

    _receiveCompleteSub = _fileTransferService.receiveComplete.listen(_handleReceiveComplete);



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
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    final appState = context.read<AppState>();
    final clipboardController = context.read<ClipboardController>();

    await _trayService.init(
      title: 'Wire Sync',
      clipboardItems: clipboardController.history.map((e) => e.text).toList(),
      transferItems: [],
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      await Process.run('open', [url]);
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
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
    final status = {
      'type': 'status',
      'battery': appState.batteryLevel,
      'isCharging': appState.batteryState == BatteryState.charging,
    };
    _webSocketService.send(status);
    appState.webrtcP2PService.sendMessage(jsonEncode(status));
  }

  Future<void> _handleReceiveComplete(FileReceiveProgress progress) async {
    if (!mounted) return;
    final app = context.read<AppState>();
    final item = TransferItem(
      id: progress.path,
      name: progress.name,
      total: progress.total,
      direction: 'receive',
      path: progress.path,
      status: 'complete',
      progress: 1.0,
      bytesTransferred: progress.total,
      startTime: DateTime.now(),
    );
    final historyService = context.read<HistoryService>();
    await historyService.saveTransfer(item);
    app.updateLastSync();
    
    setState(() {
      _pendingPopup = progress;
    });

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
                  if (_pendingPopup != null)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.4),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: ReceivedFilePopup(
                              progress: _pendingPopup!,
                              onDismiss: () {
                                setState(() {
                                  _pendingPopup = null;
                                });
                              },
                            ),
                          ),
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
class ReceivedFileWindow extends StatelessWidget {
  final Map<String, dynamic> data;
  const ReceivedFileWindow({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final progress = FileReceiveProgress(
      name: data['name'],
      path: data['path'],
      received: data['size'],
      total: data['size'],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ReceivedFilePopup(
            progress: progress,
            isStandalone: true,
            onDismiss: () => windowManager.close(),
          ),
        ),
      ),
    );
  }
}
