import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'dart:io';
import '../../providers/app_state.dart';
import '../../services/websocket_service.dart';
import '../../controllers/clipboard_controller.dart';
import '../widgets/staggered_animated_item.dart';
import '../widgets/glass_card.dart';
import '../../widgets/liquid_background.dart';
import 'device_pairing_page.dart';
import 'desktop_browser_page.dart';
import 'remote_file_manager_page.dart';
import 'trackpad_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Consumer2<AppState, ClipboardController>(
      builder: (context, appState, clipboardController, _) {
        final isPeerConnected = appState.pairingService.activeDevice != null;
        final peerName = appState.pairingService.activeDevice?.name;

        return LiquidBackground(
          child: RefreshIndicator(
            onRefresh: () async {
              await appState.reconnect();
            },
            color: scheme.primary,
            backgroundColor: Colors.transparent,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [scheme.primary, scheme.secondary, scheme.tertiary],
                              ).createShader(bounds),
                              child: const Text(
                                'WIRE',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 6.0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _ConnectionPulse(status: appState.lastStatus),
                            const Spacer(),
                            IconButton(
                              onPressed: () => _showDevicePairing(context, appState),
                              icon: Icon(Icons.important_devices_rounded, color: scheme.onSurface.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isPeerConnected ? 'At your service, $peerName' : 'Ready to Connect',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface,
                            letterSpacing: -1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.1,
                    children: [
                      // Connectivity & Status Tile
                      _BentoTile(
                        index: 0,
                        accent: scheme.primary,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_tethering_rounded, color: scheme.primary, size: 28),
                            const SizedBox(height: 8),
                            Text(
                              isPeerConnected ? 'Connected' : 'Searching...',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isPeerConnected ? (appState.pingMs != null ? '${appState.pingMs}ms latency' : 'Latency OK') : 'Check signal',
                              style: TextStyle(fontSize: 10, color: scheme.onSurface.withValues(alpha: 0.5)),
                            ),
                          ],
                        ),
                      ),

                      // Battery Hub
                      _BentoTile(
                        index: 1,
                        accent: scheme.tertiary,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  appState.batteryState == BatteryState.charging ? Icons.battery_charging_full : Icons.battery_full,
                                  color: scheme.tertiary,
                                  size: 22,
                                ),
                                const SizedBox(width: 4),
                                Text('${appState.batteryLevel}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            if (isPeerConnected && appState.remoteBattery != null) ...[
                              const SizedBox(height: 6),
                              Container(height: 1, width: 40, color: scheme.onSurface.withValues(alpha: 0.1)),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.phone_android_rounded, color: scheme.onSurface.withValues(alpha: 0.4), size: 14),
                                  const SizedBox(width: 4),
                                  Text('${appState.remoteBattery}%', style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6))),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Clipboard Tile — shows LAST clip only, tap to copy
                      _BentoTile(
                        index: 2,
                        accent: scheme.secondary,
                        onTap: () {
                          if (clipboardController.history.isNotEmpty) {
                            Clipboard.setData(ClipboardData(text: clipboardController.history.first.text));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied last item')));
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.content_paste_rounded, color: scheme.secondary, size: 18),
                                const Spacer(),
                                Text('LAST CLIP', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: scheme.onSurface.withValues(alpha: 0.4))),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              clipboardController.history.isEmpty ? 'Waiting...' : clipboardController.history.first.text.replaceAll('\n', ' ').trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: scheme.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text('Tap to copy', style: TextStyle(color: scheme.secondary, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),

                      // Send URL (Handoff) Tile
                      _BentoTile(
                        index: 3,
                        accent: Colors.teal,
                        onTap: isPeerConnected ? () => _showHandoffDialog(context, appState) : null,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.open_in_browser_rounded, color: Colors.teal, size: 28),
                            const SizedBox(height: 8),
                            const Text('SEND URL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                            Text(
                              isPeerConnected ? 'Open on peer' : 'Connect first',
                              style: TextStyle(fontSize: 9, color: scheme.onSurface.withValues(alpha: 0.4)),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Quick Actions Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
                    child: Text(
                      'Quick Actions',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: scheme.onSurface),
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Magic Drop (macOS only)
                      if (Platform.isMacOS)
                        DropTarget(
                          onDragDone: (detail) async {
                            if (detail.files.isNotEmpty && isPeerConnected) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sending ${detail.files.first.name}...')));
                              try {
                                await appState.pushFile(detail.files.first.path);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                                }
                              }
                            }
                          },
                          child: _QuickActionTile(
                            index: 4,
                            icon: Icons.auto_awesome_rounded,
                            title: 'Magic Drop',
                            subtitle: 'Drop files here to send',
                            accent: scheme.primary,
                          ),
                        ),

                      // Browse Remote Files (Android when connected to Mac)
                      if (Platform.isAndroid && isPeerConnected && appState.pairingService.activeDevice?.osType == 'macos')
                        _QuickActionTile(
                          index: 5,
                          icon: Icons.desktop_windows_rounded,
                          title: 'Desktop Files',
                          subtitle: 'Browse Mac filesystem',
                          accent: scheme.tertiary,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DesktopBrowserPage())),
                        ),

                      // Remote File Browser
                      if (isPeerConnected)
                        _QuickActionTile(
                          index: 6,
                          icon: Icons.folder_shared_rounded,
                          title: 'Remote Storage',
                          subtitle: 'Browse & download from peer',
                          accent: Colors.indigo,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RemoteFileManagerPage())),
                        ),

                      // Remote Trackpad
                      if (isPeerConnected)
                        _QuickActionTile(
                          index: 7,
                          icon: Icons.touch_app_rounded,
                          title: 'Remote Trackpad',
                          subtitle: 'Control mouse & keyboard',
                          accent: scheme.secondary,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TrackpadPage(
                                webSocketService: appState.webSocketService,
                                deviceId: appState.deviceId,
                              ),
                            ),
                          ),
                        ),

                      // Find Phone
                      if (isPeerConnected)
                        _QuickActionTile(
                          index: 8,
                          icon: Icons.ring_volume_rounded,
                          title: 'Find Device',
                          subtitle: 'Ring peer at max volume',
                          accent: Colors.red,
                          onTap: () {
                            appState.findPhone();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ringing remote device...')),
                            );
                          },
                        ),
                    ]),
                  ),
                ),

                const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showHandoffDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController();
    // Pre-fill with clipboard content if it looks like a URL
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      final text = data?.text ?? '';
      if (text.startsWith('http://') || text.startsWith('https://')) {
        controller.text = text;
      }
    });

    showDialog(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Send URL', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'https://...',
              prefixIcon: const Icon(Icons.link_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final url = controller.text.trim();
                if (url.isNotEmpty) {
                  appState.handoffUrl(url);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('URL sent to ${appState.pairingService.activeDevice?.name ?? "peer"}')),
                  );
                }
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  void _showDevicePairing(BuildContext context, AppState appState) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DevicePairingPage(
          pairingService: appState.pairingService,
          discoveredPeers: appState.discoveredPeers,
          localDeviceId: appState.deviceId,
          onMakeActive: (device) => appState.connectToPeer(device.lastIp, targetId: device.deviceId),
          onConnectToPeer: (peer) => appState.connectToPeer(peer.address.address, targetId: peer.deviceId),
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;

  const _QuickActionTile({
    required this.index,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StaggeredAnimatedItem(
        index: index,
        child: GlassCardInteractive(
          onTap: onTap,
          accent: accent,
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.4))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurface.withValues(alpha: 0.2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BentoTile extends StatelessWidget {
  final Widget child;
  final int index;
  final Color accent;
  final VoidCallback? onTap;

  const _BentoTile({required this.child, required this.index, required this.accent, this.onTap});

  @override
  Widget build(BuildContext context) {
    return StaggeredAnimatedItem(
      index: index,
      child: GlassCardInteractive(
        onTap: onTap,
        accent: accent,
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(28),
        child: child,
      ),
    );
  }
}

class _ConnectionPulse extends StatefulWidget {
  final ConnectionStatus status;
  const _ConnectionPulse({required this.status});

  @override
  State<_ConnectionPulse> createState() => _ConnectionPulseState();
}

class _ConnectionPulseState extends State<_ConnectionPulse> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (widget.status) {
      case ConnectionStatus.connected: color = Colors.green; break;
      case ConnectionStatus.connecting: color = Colors.amber; break;
      case ConnectionStatus.error: color = Colors.red; break;
      default: color = Colors.grey.withValues(alpha: 0.5);
    }
    return FadeTransition(
      opacity: _pulse,
      child: Container(
        width: 8, height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4, spreadRadius: 1)]),
      ),
    );
  }
}
