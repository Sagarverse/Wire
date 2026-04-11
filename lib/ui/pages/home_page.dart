import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/websocket_service.dart';
import '../../providers/app_state.dart';
import '../../controllers/clipboard_controller.dart';
import '../widgets/staggered_animated_item.dart';
import '../widgets/glass_card.dart';
import '../../widgets/liquid_background.dart';
import 'device_pairing_page.dart';
import 'remote_file_manager_page.dart';
import '../widgets/file_preview_overlay.dart';
import 'package:open_file/open_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../widgets/pairing_request_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Listen for file receipts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.fileTransferService.receiveComplete.listen((progress) {
        if (!mounted) return;
        _showFilePreview(context, appState, progress.name, progress.path, progress.total);
      });

      // Listen for pairing requests
      appState.addListener(_handleAppStateChanges);
    });
  }

  void _handleAppStateChanges() {
    if (!mounted) return;
    final app = context.read<AppState>();
    if (app.pendingPairing != null) {
      _showPairingRequest(app);
    }
  }

  bool _pairingSheetOpen = false;
  void _showPairingRequest(AppState appState) {
    if (_pairingSheetOpen) return;
    _pairingSheetOpen = true;
    
    final req = appState.pendingPairing;
    if (req == null) {
      _pairingSheetOpen = false;
      return;
    }

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => PairingRequestSheet(
        deviceName: req.name,
        deviceIp: req.ip,
        deviceOs: req.os,
        onAccept: () {
          appState.allowPairing();
          Navigator.pop(context);
        },
        onReject: () {
          appState.denyPairing();
          Navigator.pop(context);
        },
      ),
    ).whenComplete(() {
      _pairingSheetOpen = false;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _timeGreeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 21) return 'Good evening';
    return 'Good night';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Consumer2<AppState, ClipboardController>(
      builder: (context, appState, clipboardController, _) {
        final isPeerConnected = appState.pairingService.activeDevice != null;
        final peerName = appState.pairingService.activeDevice?.name;

        return DropTarget(
          onDragDone: (details) {
            if (isPeerConnected && details.files.isNotEmpty) {
              for (final file in details.files) {
                appState.pushFile(file.path);
              }
            }
          },
          child: Scaffold(
            extendBody: true,
            body: LiquidBackground(
              accent: appState.lastStatus == ConnectionStatus.error 
                  ? Colors.red 
                  : (appState.connectionMode == ConnectionMode.p2p ? Colors.blue : Colors.green),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                    // ── Top Bar ──────────────────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
                        child: GlassCard(
                          padding: const EdgeInsets.all(20),
                          accent: scheme.primary,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 54,
                                    height: 54,
                                    margin: const EdgeInsets.only(right: 16),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [scheme.primary, scheme.tertiary],
                                      ),
                                      image: appState.userAvatar != null
                                          ? DecorationImage(
                                              image: NetworkImage(
                                                  appState.userAvatar!))
                                          : null,
                                      boxShadow: [
                                        BoxShadow(
                                          color: scheme.primary.withValues(alpha: 0.3),
                                          blurRadius: 15.clamp(0, double.infinity).toDouble(),
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: appState.userAvatar == null
                                        ? Icon(Icons.person_rounded,
                                            color: scheme.onPrimary)
                                        : null,
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _timeGreeting(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.5),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      Text(
                                        isPeerConnected
                                            ? (peerName ?? 'Device')
                                            : appState.userName,
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          color: scheme.onSurface,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  _CircleIconButton(
                                    icon: Icons.important_devices_rounded,
                                    onPressed: () =>
                                        _showDevicePairing(context, appState),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _ConnectionModeToggle(
                                mode: appState.connectionMode,
                                onChanged: (mode) =>
                                    appState.setConnectionMode(mode),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Connection Hub ──────────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: StaggeredAnimatedItem(
                            index: 0,
                            child: _StatusHub(
                              status: appState.lastStatus,
                              connectionType: appState.connectionType,
                              modeMismatch: appState.modeMismatch,
                              pulseController: _pulseController,
                              onTap: () => appState.reconnect(),
                            ),
                          ),
                        ),
                      ),
                    ),


                    // ── Clipboard Card ──────────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        child: StaggeredAnimatedItem(
                          index: 2,
                          child: GestureDetector(
                            onTap: () {
                              if (clipboardController.history.isNotEmpty) {
                                Clipboard.setData(ClipboardData(
                                    text: clipboardController
                                        .history.first.text));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Copied to clipboard'),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    backgroundColor:
                                        scheme.onSurface.withValues(alpha: 0.8),
                                  ),
                                );
                              }
                            },
                            child: GlassCard(
                              accent: scheme.onSurface,
                              borderRadius: BorderRadius.circular(24),
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'CLIPBOARD',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: (clipboardController
                                                      .isSyncPaused
                                                  ? Colors.orange
                                                  : Colors.green)
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          clipboardController.isSyncPaused
                                              ? 'PAUSED'
                                              : 'SYNC ACTIVE',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: clipboardController
                                                    .isSyncPaused
                                                ? Colors.orange
                                                : Colors.green,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    clipboardController.history.isEmpty
                                        ? 'Nothing copied yet'
                                        : clipboardController.history.first.text,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontFamily: 'Courier', // Monospaced feel
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface.withValues(alpha: 0.9),
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    children: [
                                      _QuickAction(
                                        icon: Icons.copy_all_rounded,
                                        label: 'Copy',
                                        onTap: () {
                                          if (clipboardController.history.isNotEmpty) {
                                            Clipboard.setData(ClipboardData(text: clipboardController.history.first.text));
                                            HapticFeedback.mediumImpact();
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 12),
                                      _QuickAction(
                                        icon: Icons.ios_share_rounded,
                                        label: 'Share',
                                        onTap: () {
                                          // Share logic here
                                        },
                                      ),
                                      const Spacer(),
                                      if (clipboardController.history.isNotEmpty)
                                        _QuickAction(
                                          icon: Icons.delete_outline_rounded,
                                          label: 'Clear',
                                          color: Colors.red.withValues(alpha: 0.1),
                                          iconColor: Colors.red,
                                          onTap: () {
                                            clipboardController.clearHistory();
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Recent Transfers ──────────────────────────────────────────
                    if (appState.recentTransfers.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'RECENT TRANSFERS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 100,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: appState.recentTransfers.length,
                                  separatorBuilder: (_, index) =>
                                      const SizedBox(width: 12),
                                  itemBuilder: (context, index) {
                                    final item =
                                        appState.recentTransfers[index];
                                    return _RecentTransferTile(item: item);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ── Action Grid ─────────────────────────────────────────────
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                      sliver: SliverGrid.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.5,
                        children: [
                          _ActionTile(
                            index: 3,
                            icon: Icons.folder_open_rounded,
                            label: 'Browse Files',
                            color: Colors.blue,
                            enabled: isPeerConnected,
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const RemoteFileManagerPage())),
                          ),
                          _ActionTile(
                            index: 4,
                            icon: Icons.link_rounded,
                            label: 'Send URL',
                            color: Colors.teal,
                            enabled: isPeerConnected,
                            onTap: () => _showHandoffDialog(context, appState),
                          ),
                        ],
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

  void _showDevicePairing(BuildContext context, AppState appState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DevicePairingPage(
        pairingService: appState.pairingService,
        discoveredPeers: appState.discoveredPeers,
        localDeviceId: appState.deviceId,
        onMakeActive: (device) => appState.connectToPeer(
          device.lastIp,
          targetId: device.deviceId,
        ),
        onConnectToPeer: (peer) => appState.connectToPeer(
          peer.address,
          targetId: peer.deviceId,
        ),
      ),
    );
  }

  void _showHandoffDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'https://...'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              appState.handoffUrl(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showFilePreview(BuildContext context, AppState appState, String name, String path, int size) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) => FilePreviewOverlay(
        fileName: name,
        filePath: path,
        fileSize: size,
        onOpen: () {
          OpenFile.open(path);
          Navigator.pop(context);
        },
        onShowInFolder: () {
          appState.openFileLocation(path);
          Navigator.pop(context);
        },
        onDismiss: () => Navigator.pop(context),
      ),
    );
  }
}

class _StatusHub extends StatelessWidget {
  final ConnectionStatus status;
  final String connectionType;
  final bool modeMismatch;
  final AnimationController pulseController;
  final VoidCallback onTap;

  const _StatusHub({
    required this.status,
    required this.connectionType,
    required this.modeMismatch,
    required this.pulseController,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isConnected = status == ConnectionStatus.connected;
    final color = modeMismatch 
        ? Colors.red 
        : (isConnected ? Colors.green : (status == ConnectionStatus.connecting ? Colors.orange : scheme.primary));

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Radar Sweep (Only showing when not connected)
          if (!isConnected)
            AnimatedBuilder(
              animation: pulseController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: pulseController.value * 2 * math.pi,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          color.withValues(alpha: 0.2),
                          Colors.transparent,
                        ],
                        stops: const [0.25, 0.25],
                      ),
                    ),
                  ),
                );
              },
            ),
          
          // Outer Glow
          AnimatedBuilder(
            animation: pulseController,
            builder: (context, child) {
              return Container(
                width: 170 + (25 * pulseController.value),
                height: 170 + (25 * pulseController.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: 0.15 * (1 - pulseController.value)),
                    width: 2,
                  ),
                ),
              );
            },
          ),
          
          // Main Hub
          GlassCard(
            borderRadius: BorderRadius.circular(100),
            blur: 20,
            opacity: 0.1,
            accent: color,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 600),
                    tween: Tween(begin: 0, end: 1),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: 0.8 + (0.2 * value),
                        child: Icon(
                          modeMismatch 
                              ? Icons.sync_problem_rounded 
                              : (isConnected ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded),
                          size: 44,
                          color: color,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    modeMismatch
                        ? 'MISMATCH'
                        : (isConnected ? connectionType.toUpperCase() : (status == ConnectionStatus.connecting ? 'CONNECTING' : 'READY')),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: color,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionTile({
    required this.index,
    required this.icon,
    required this.label,
    required this.color,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StaggeredAnimatedItem(
      index: index,
      child: IgnorePointer(
        ignoring: !enabled,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: enabled ? 1.0 : 0.4,
          child: GestureDetector(
            onTap: onTap,
            child: GlassCard(
              accent: enabled ? color : color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: enabled ? color : color.withValues(alpha: 0.3), size: 28),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.3),
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

class _ConnectionModeToggle extends StatelessWidget {
  final ConnectionMode mode;
  final ValueChanged<ConnectionMode> onChanged;

  const _ConnectionModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          _buildToggleItem(context, 'Local', Icons.router_rounded, mode == ConnectionMode.local, () => onChanged(ConnectionMode.local)),
          _buildToggleItem(context, 'Internet', Icons.language_rounded, mode == ConnectionMode.p2p, () => onChanged(ConnectionMode.p2p)),
          _buildToggleItem(context, 'Smart', Icons.auto_awesome_rounded, mode == ConnectionMode.auto, () => onChanged(ConnectionMode.auto)),
        ],
      ),
    );
  }

  Widget _buildToggleItem(BuildContext context, String label, IconData icon, bool active, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.elasticOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: active ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10.clamp(0, double.infinity).toDouble(),
                offset: const Offset(0, 4),
              ),
            ] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? scheme.primary : scheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTransferTile extends StatelessWidget {
  final ReceivedFile item;

  const _RecentTransferTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ext = item.name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif'].contains(ext);

    return GestureDetector(
      onTap: () => OpenFile.open(item.path),
      child: SizedBox(
        width: 100,
        child: GlassCard(
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    color: scheme.onSurface.withValues(alpha: 0.05),
                    child: isImage
                        ? Image.file(File(item.path), fit: BoxFit.cover)
                        : Icon(Icons.insert_drive_file_rounded,
                            size: 24,
                            color: scheme.primary.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.name,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CircleIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surface,
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: scheme.onSurface.withValues(alpha: 0.6), size: 22),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Color? iconColor;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color ?? scheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor ?? scheme.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: iconColor ?? scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
