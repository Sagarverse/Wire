import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../controllers/clipboard_controller.dart';
import '../widgets/glass_card.dart';
import '../widgets/staggered_animated_item.dart';
import '../../widgets/liquid_background.dart';
import 'device_pairing_page.dart';
import 'remote_file_manager_page.dart';

class ControlHubPage extends StatelessWidget {
  final EdgeInsets? padding;
  const ControlHubPage({super.key, this.padding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Consumer2<AppState, ClipboardController>(
      builder: (context, appState, clipboardController, _) {
        final isPeerConnected = appState.pairingService.activeDevice != null;

        return LiquidBackground(
          child: SingleChildScrollView(
            padding:
                (padding ??
                        const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ))
                    .add(const EdgeInsets.only(top: 40)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 50),
                Text(
                  'CONTROL HUB',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 4.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Connected Center',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 32),

                // ── Row 0: Send File + Clipboard Sync ──────────────────────
                StaggeredAnimatedItem(
                  index: 0,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildBentoCard(
                          scheme: scheme,
                          title: 'Send File',
                          subtitle: isPeerConnected
                              ? 'Pick & send'
                              : 'Connect first',
                          icon: Icons.file_upload_rounded,
                          accent: scheme.tertiary,
                          height: 140,
                          onTap: isPeerConnected
                              ? () => _pickAndSend(context, appState)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildClipboardCard(
                          context: context,
                          scheme: scheme,
                          clipboardController: clipboardController,
                          height: 140,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Row 1: Remote Files + Device Link ──────────────────────
                StaggeredAnimatedItem(
                  index: 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildBentoCard(
                          scheme: scheme,
                          title: 'Remote Files',
                          subtitle: isPeerConnected
                              ? 'Browse storage'
                              : 'Connect Peer',
                          icon: Icons.folder_shared_rounded,
                          accent: scheme.onSurface,
                          height: 160,
                          onTap: isPeerConnected
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const RemoteFileManagerPage(),
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildBentoCard(
                          scheme: scheme,
                          title: 'Device Link',
                          subtitle: isPeerConnected ? 'Paired' : 'Pair now',
                          icon: Icons.phonelink_lock_rounded,
                          accent: scheme.onSurface,
                          height: 160,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DevicePairingPage(
                                pairingService: appState.pairingService,
                                discoveredPeers: appState.discoveredPeers,
                                localDeviceId: appState.deviceId,
                                onMakeActive: (device) =>
                                    appState.connectToPeer(
                                      device.lastIp,
                                      targetId: device.deviceId,
                                    ),
                                onConnectToPeer: (peer) =>
                                    appState.connectToPeer(
                                      peer.address,
                                      targetId: peer.deviceId,
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Finder Mount (macOS only) ───────────────────────────────
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS && appState.labsMountFinderEnabled) ...[
                  const SizedBox(height: 16),
                  StaggeredAnimatedItem(
                    index: 2,
                    child: _buildMountCard(context, appState, scheme),
                  ),
                ],

                const SizedBox(height: 32),

                // ── Find Phone ─────────────────────────────────────────────
                StaggeredAnimatedItem(
                  index: 3,
                  child: _buildFindPhoneSection(context, appState, scheme),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _pickAndSend(BuildContext context, AppState appState) async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;
      final filePaths = result.files.map((f) => f.path).whereType<String>().toList();
      if (filePaths.isEmpty) return;
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sending ${filePaths.length} items…')),
        );
      }
      await appState.pushFiles(filePaths);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent ${filePaths.length} items ✓'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Send failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildClipboardCard({
    required BuildContext context,
    required ColorScheme scheme,
    required ClipboardController clipboardController,
    required double height,
  }) {
    final isPaused = clipboardController.isSyncPaused;
    final accent = isPaused
        ? scheme.onSurface.withValues(alpha: 0.4)
        : scheme.secondary;
    final statusColor = isPaused ? Colors.orange : Colors.green;
    final lastClip = clipboardController.history.isNotEmpty
        ? clipboardController.history.first.text.replaceAll('\n', ' ').trim()
        : null;

    return SizedBox(
      height: height,
      child: GlassCardInteractive(
        onTap: () => clipboardController.setSyncPaused(!isPaused),
        accent: isPaused ? null : scheme.secondary,
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPaused
                        ? Icons.sync_disabled_rounded
                        : Icons.content_paste_go_rounded,
                    color: accent,
                    size: 20,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isPaused ? 'PAUSED' : 'LIVE',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clipboard',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lastClip != null
                      ? (lastClip.length > 22
                            ? '${lastClip.substring(0, 22)}…'
                            : lastClip)
                      : isPaused
                      ? 'Sync paused'
                      : 'Tap to pause',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMountCard(
    BuildContext context,
    AppState appState,
    ColorScheme scheme,
  ) {
    final isMounted = appState.isUsbMounted;
    final isPeerConnected = appState.pairingService.activeDevice != null;
    final accent = scheme.onSurface;

    return GlassCardInteractive(
      onTap: isPeerConnected
          ? () {
              if (isMounted) {
                appState.unmountAsUsb();
              } else {
                appState.mountAsUsb();
              }
            }
          : null,
      accent: isPeerConnected ? accent : null,
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isMounted ? Icons.eject_rounded : Icons.usb_rounded,
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMounted
                      ? 'Phone Mounted in Finder'
                      : 'Mount Phone in Finder',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isMounted
                      ? 'Tap to safely eject'
                      : isPeerConnected
                      ? 'Browse phone storage like a USB drive'
                      : 'Connect a device first',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isMounted ? 'EJECT' : 'MOUNT',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: accent,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoCard({
    required ColorScheme scheme,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required double height,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: height,
      child: GlassCardInteractive(
        onTap: onTap,
        accent: onTap != null ? accent : null,
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFindPhoneSection(
    BuildContext context,
    AppState appState,
    ColorScheme scheme,
  ) {
    final isConnected = appState.pairingService.activeDevice != null;
    return GlassCardInteractive(
      onTap: isConnected
          ? () {
              appState.findPhone();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ringing remote device…')),
              );
            }
          : null,
      accent: Colors.red,
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.ring_volume_rounded,
              color: scheme.onSurface,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Lost your device?',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  isConnected
                      ? 'Ring at max volume to find it.'
                      : 'Connect a device first',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
