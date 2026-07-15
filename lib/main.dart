import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'ui/widgets/received_file_popup.dart';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:window_manager/window_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';


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
import 'ui/pages/clipboard_page.dart';
import 'ui/pages/files_page.dart';
import 'ui/pages/settings_page.dart';

import 'ui/theme/app_theme.dart';
import 'providers/app_state.dart';
import 'providers/remote_file_provider.dart';
import 'providers/file_transfer_provider.dart';
import 'controllers/clipboard_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (args.isNotEmpty) {
     try {
       // Check if arguments contains the JSON for a received file
       final raw = args.first;
       final data = jsonDecode(raw);
       if (data is Map && data.containsKey('path')) {
         runApp(MaterialApp(
           debugShowCheckedModeBanner: false,
           theme: AppTheme.dark(),
           home: ReceivedFileWindow(data: Map<String, dynamic>.from(data)),
         ));
         return;
       }
     } catch (_) {}
  }

  await AppTheme.initThemeMode();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    await windowManager.ensureInitialized();
    
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
    );
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

  final appState = AppState(
    identityService: identityService,
    discoveryService: discoveryService,
    pairingService: pairingService,
    webSocketService: webSocketService,
    notificationsService: notificationsService,
    notificationSyncService: notificationSyncService,
    fileTransferService: fileTransferService,
    webrtcP2PService: webrtcP2PService,
    historyService: historyService,
  );

  // Trigger async initialization
  unawaited(appState.init());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProxyProvider<AppState, ClipboardController>(
          create: (context) => ClipboardController(
            clipboardService: clipboardService,
            historyService: historyService,
            onSendMessage: appState.sendMessage,
          ),
          update: (context, currentAppState, previous) => currentAppState == appState ? previous! : ClipboardController(
            clipboardService: clipboardService,
            historyService: historyService,
            onSendMessage: currentAppState.sendMessage,
          ),
        ),
        Provider<HistoryService>.value(value: historyService),
        ChangeNotifierProvider(
          create: (_) => FileTransferProvider(
            fileTransferService: fileTransferService,
            historyService: historyService,
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

class _WireAppState extends State<WireApp> with WidgetsBindingObserver {
  bool _initialized = false;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppTheme.themeModeNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAuth();
    } else if (state == AppLifecycleState.paused) {
      context.read<AppState>().logout();
    }
  }

  Future<void> _checkAuth() async {
    final appState = context.read<AppState>();
    if (!_initialized) {
      _initFuture = _initWithProviders();
      await _initFuture;
      setState(() => _initialized = true);
    }
    
    if (appState.biometricLockEnabled && !appState.isAuthenticated) {
      await appState.authenticate();
    }
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Wire',
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
                  // Enforce biometric lock barrier
                  if (appState.biometricLockEnabled && !appState.isAuthenticated) {
                    return SecurityOverlay(
                      onUnlock: () => appState.authenticate(),
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

class SecurityOverlay extends StatelessWidget {
  final VoidCallback onUnlock;
  const SecurityOverlay({super.key, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline_rounded, size: 48, color: scheme.onSurface),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .scale(duration: 2.seconds, begin: const Offset(1,1), end: const Offset(1.1, 1.1), curve: Curves.easeInOut),
            const SizedBox(height: 32),
            Text(
              'AUTHENTICATION REQUIRED',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 3, color: scheme.onSurface.withValues(alpha: 0.3)),
            ),
            const SizedBox(height: 48),
            GestureDetector(
              onTap: onUnlock,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.onSurface.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'UNLOCK',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2),
                ),
              ),
            ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2, end: 0),
          ],
        ),
      ),
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
  StreamSubscription<BatteryState>? _batteryStateSub;

  final _backgroundService = BackgroundService();
  final _battery = Battery();

  FileReceiveProgress? _pendingPopup;

  // Adaptive layout breakpoint
  static const _desktopBreakpoint = 720.0;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _webSocketService = app.webSocketService;
    _fileTransferService = app.fileTransferService;

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
    _batteryStateSub?.cancel();
    super.dispose();
  }

  void _onNavigationItemTapped(int index) {
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _navigationIndex = index);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // Build pages list matching nav items
  List<Widget> _buildPages(bool isDesktop) {
    // On mobile, let each page handle its own bottom padding via MediaQuery
    // so it accounts for safe area + nav bar height dynamically
    final bottomPadding = isDesktop
        ? const EdgeInsets.only(bottom: 24)
        : null; // null = pages use their own default
    return <Widget>[
      ControlHubPage(padding: bottomPadding),
      FilesPage(padding: bottomPadding),
      ClipboardPage(padding: bottomPadding),
      SettingsPage(
        padding: bottomPadding,
        onResetApp: () {
          context.findAncestorStateOfType<_WireAppState>()?._resetApplication();
        },
      ),
    ];
  }

  Future<void> _init() async {
    final appState = context.read<AppState>();

    await appState.notificationsService.init(onSelectNotification: _onNotificationTap);
    await _focusModeService.init();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _backgroundService.init();
      await _backgroundService.start();
    }

    _batteryStateSub = _battery.onBatteryStateChanged.listen((state) {
      if (!mounted) return;
      appState.setBatteryStatus(appState.batteryLevel, state);
      _sendBatteryStatus();
    });
    _battery.batteryLevel.then((level) {
      if (!mounted) return;
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
    
    // On macOS, start with window hidden unless it is the first run
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      await windowManager.show();
      await Future.delayed(const Duration(milliseconds: 1000));
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    }
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

    void updateTray() {
       if (mounted) {
         _trayService.updateMenu(
           state: appState.getTrayState(),
           onAction: appState.handleTrayAction,
         );
       }
    }

    await _trayService.init(
      state: appState.getTrayState(),
      onAction: appState.handleTrayAction,
    );

    // Subscribe to AppState changes to refresh tray menu dynamically
    appState.addListener(updateTray);
  }

  void _handleHandoff(String url) async {
    if (url.isEmpty) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      await Process.run('open', [url]);
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _platformChannel.invokeMethod('openUrl', {'url': url});
      } catch (_) {
        debugPrint('Failed to open URL: $url');
      }
    }
  }

  void _onNotificationTap(NotificationResponse response) {}

  void _sendBatteryStatus() {
    if (!mounted) return;
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
    
    // On non-macOS platforms, we show the local overlay popup.
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.macOS) {
      setState(() {
        _pendingPopup = progress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final scheme = Theme.of(context).colorScheme;
        final isPeerConnected = appState.pairingService.activeDevice != null;
        final screenWidth = MediaQuery.of(context).size.width;
        final isDesktop = screenWidth >= _desktopBreakpoint;
        final pages = _buildPages(isDesktop);

        // Check for pending pairing requests
        if (appState.pendingPairing != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPairingRequestDialog(context, appState);
          });
        }

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
            child: Stack(
              children: [
                // Main content with adaptive layout
                if (isDesktop)
                  _DesktopLayout(
                    selectedIndex: _navigationIndex,
                    onDestinationSelected: _onNavigationItemTapped,
                    connectionStatus: appState.connectionStatus,
                    pages: pages,
                  )
                else
                  _MobileLayout(
                    pageController: _pageController,
                    selectedIndex: _navigationIndex,
                    onDestinationSelected: _onNavigationItemTapped,
                    onPageChanged: (index) => setState(() => _navigationIndex = index),
                    connectionStatus: appState.connectionStatus,
                    pages: pages,
                  ),
                // Received file popup overlay
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
        );
      },
    );
  }

  void _showPairingRequestDialog(BuildContext context, AppState appState) {
    final request = appState.pendingPairing;
    if (request == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  request.os == 'macos' ? Icons.laptop_mac_rounded : Icons.phone_android_rounded,
                  color: scheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Pairing Request'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${request.name}" wants to pair with this device.',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                'IP: ${request.ip} · ${request.os.toUpperCase()}',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                appState.denyPairing();
                Navigator.pop(ctx);
              },
              child: const Text('Deny'),
            ),
            FilledButton(
              onPressed: () {
                appState.allowPairing();
                Navigator.pop(ctx);
              },
              child: const Text('Allow'),
            ),
          ],
        );
      },
    );
  }
}

// Desktop layout with NavigationRail
class _DesktopLayout extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final ConnectionStatus connectionStatus;
  final List<Widget> pages;

  const _DesktopLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.connectionStatus,
    required this.pages,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 8),
            child: Column(
              children: [
                Text(
                  'Wire',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                _ConnectionDot(status: connectionStatus),
              ],
            ),
          ),
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: Text('Dashboard'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded),
              label: Text('Files'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.content_paste_outlined),
              selectedIcon: Icon(Icons.content_paste_rounded),
              label: Text('Clipboard'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: Text('Settings'),
            ),
          ],
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: scheme.outline.withValues(alpha: 0.2),
        ),
        Expanded(
          child: IndexedStack(
            index: selectedIndex,
            children: pages,
          ),
        ),
      ],
    );
  }
}

// Mobile layout with glassmorphism bottom NavigationBar
class _MobileLayout extends StatelessWidget {
  final PageController pageController;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final ValueChanged<int> onPageChanged;
  final ConnectionStatus connectionStatus;
  final List<Widget> pages;

  const _MobileLayout({
    required this.pageController,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onPageChanged,
    required this.connectionStatus,
    required this.pages,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        PageView(
          controller: pageController,
          onPageChanged: onPageChanged,
          children: pages,
        ),
        // Premium floating dock
        Positioned(
          left: 24,
          right: 24,
          bottom: bottomPadding + 10,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0D1220).withValues(alpha: 0.92)
                      : Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? scheme.primary.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Animated glowing pill indicator
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      left: _pillLeft(selectedIndex, context),
                      top: 8,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        width: _pillWidth(context),
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: isDark ? 0.15 : 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                    ),
                    // Tab icons
                    Row(
                      children: [
                        _DockTab(
                          icon: Icons.dashboard_outlined,
                          activeIcon: Icons.dashboard_rounded,
                          isActive: selectedIndex == 0,
                          connectionStatus: connectionStatus,
                          onTap: () => onDestinationSelected(0),
                        ),
                        _DockTab(
                          icon: Icons.folder_outlined,
                          activeIcon: Icons.folder_rounded,
                          isActive: selectedIndex == 1,
                          onTap: () => onDestinationSelected(1),
                        ),
                        _DockTab(
                          icon: Icons.content_paste_outlined,
                          activeIcon: Icons.content_paste_rounded,
                          isActive: selectedIndex == 2,
                          onTap: () => onDestinationSelected(2),
                        ),
                        _DockTab(
                          icon: Icons.settings_outlined,
                          activeIcon: Icons.settings_rounded,
                          isActive: selectedIndex == 3,
                          onTap: () => onDestinationSelected(3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _pillWidth(BuildContext context) {
    final totalWidth = MediaQuery.of(context).size.width - 48; // 24 left + 24 right
    return totalWidth / 4;
  }

  double _pillLeft(int index, BuildContext context) {
    final totalWidth = MediaQuery.of(context).size.width - 48;
    return (totalWidth / 4) * index;
  }
}

// Connection status dot indicator
class _ConnectionDot extends StatelessWidget {
  final ConnectionStatus status;
  const _ConnectionDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final isConnected = status == ConnectionStatus.connected || status == ConnectionStatus.syncing;
    final isConnecting = status == ConnectionStatus.connecting;
    final color = isConnected
        ? const Color(0xFF34C759)
        : isConnecting
            ? const Color(0xFFFF9F0A)
            : Colors.grey;
    final label = isConnected
        ? 'Connected'
        : isConnecting
            ? 'Connecting'
            : 'Offline';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: isConnected
                ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// Premium dock tab with animated icon and connection dot
class _DockTab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final ConnectionStatus? connectionStatus;
  final VoidCallback onTap;

  const _DockTab({
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    this.connectionStatus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isConnected = connectionStatus == ConnectionStatus.connected ||
        connectionStatus == ConnectionStatus.syncing;
    final isConnecting = connectionStatus == ConnectionStatus.connecting;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 60,
          child: Center(
            child: AnimatedScale(
              scale: isActive ? 1.0 : 0.85,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isActive ? activeIcon : icon,
                      key: ValueKey(isActive),
                      size: 22,
                      color: isActive
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  // Connection dot (only on dashboard tab)
                  if (connectionStatus != null)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isConnected
                              ? const Color(0xFF34C759)
                              : isConnecting
                                  ? const Color(0xFFFF9F0A)
                                  : Colors.grey.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                          boxShadow: isConnected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF34C759).withValues(alpha: 0.4),
                                    blurRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ReceivedFilePopup(
            progress: progress,
            isStandalone: true,
            senderName: data['sender'] as String?,
            onDismiss: () => windowManager.close(),
          ),
        ),
      ),
    );
  }
}
