import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/staggered_animated_item.dart';
import 'dart:io';
import '../../widgets/liquid_background.dart';
import 'device_pairing_page.dart';
import 'trackpad_page.dart';
import 'screen_mirror_page.dart';
import 'camera_viewer_page.dart';
import 'remote_file_manager_page.dart';

class ControlHubPage extends StatelessWidget {
  final EdgeInsets? padding;
  const ControlHubPage({super.key, this.padding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Consumer<AppState>(
      builder: (context, appState, _) {
        final isPeerConnected = appState.pairingService.activeDevice != null;
        final labsMirrorEnabled = appState.labsMirrorFeaturesEnabled;

        return LiquidBackground(
          child: SingleChildScrollView(
            padding: (padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 24)).add(const EdgeInsets.only(top: 40)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 50),
                Text(
                  'CONTROL HUB',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: scheme.primary,
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
                
                // Bento Grid
                StaggeredAnimatedItem(
                  index: 0,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildBentoCard(
                          scheme: scheme,
                          title: 'Mirror Display',
                          subtitle: !labsMirrorEnabled
                              ? 'Enable in Labs'
                              : isPeerConnected ? 'Real-time feed' : 'Connect Peer',
                          icon: Icons.cast_connected_rounded,
                          accent: scheme.primary,
                          height: 160, // Reduced height to avoid overflow
                          onTap: labsMirrorEnabled && isPeerConnected ? () async {
                            try {
                              if (Platform.isAndroid) {
                                final localRenderer = await appState.mirrorService.startSending();
                                if (context.mounted) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ScreenMirrorPage(
                                        mirrorService: appState.mirrorService,
                                        initialRenderer: localRenderer,
                                        onSendFile: (path) => appState.pushFile(path),
                                        onStop: () => appState.mirrorService.stop(),
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Waiting for screen share from phone...'),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              _handleError(context, 'Mirror failed: $e', scheme);
                            }
                          } : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: _buildBentoCard(
                          scheme: scheme,
                          title: 'Mouse',
                          subtitle: 'Control',
                          icon: Icons.touch_app_rounded,
                          accent: scheme.secondary,
                          height: 160,
                          onTap: isPeerConnected ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TrackpadPage(
                                  webSocketService: appState.webSocketService,
                                  deviceId: appState.deviceId,
                                ),
                              ),
                            );
                          } : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                StaggeredAnimatedItem(
                  index: 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildBentoCard(
                          scheme: scheme,
                          title: 'Camera',
                          subtitle: isPeerConnected ? 'Direct link' : 'Connect Peer',
                          icon: Icons.camera_alt_rounded,
                          accent: scheme.tertiary,
                          height: 120,
                          onTap: labsMirrorEnabled && isPeerConnected ? () async {
                            try {
                              if (Platform.isAndroid) {
                                await appState.mirrorService.startSendingCamera();
                              }
                              if (context.mounted) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CameraViewerPage(
                                      mirrorService: appState.mirrorService,
                                      onFlipCamera: () => appState.mirrorService.switchCamera(),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              _handleError(context, 'Camera failed: $e', scheme);
                            }
                          } : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildBentoCard(
                          scheme: scheme,
                          title: 'Keyboard',
                          subtitle: isPeerConnected ? 'Remote type' : 'Connect Peer',
                          icon: Icons.keyboard_rounded,
                          accent: Colors.orange,
                          height: 120,
                          onTap: isPeerConnected ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TrackpadPage(
                                  webSocketService: appState.webSocketService,
                                  deviceId: appState.deviceId,
                                ),
                              ),
                            );
                          } : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                StaggeredAnimatedItem(
                  index: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildBentoCard(
                          scheme: scheme,
                          title: 'Remote Files',
                          subtitle: 'Browse storage',
                          icon: Icons.folder_shared_rounded,
                          accent: Colors.indigo,
                          height: 140,
                          onTap: isPeerConnected ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const RemoteFileManagerPage()),
                            );
                          } : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildBentoCard(
                          scheme: scheme,
                          title: 'Device Link',
                          subtitle: 'Pairing',
                          icon: Icons.phonelink_lock_rounded,
                          accent: Colors.purple,
                          height: 140,
                          onTap: () {
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
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                _buildFindPhoneSection(appState, scheme),
                const SizedBox(height: 100),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleError(BuildContext context, String message, ColorScheme scheme) {
    if (message.contains('ACCESSIBILITY_REQUIRED')) {
      message = 'Please enable Accessibility permissions for Wire in System Settings.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: scheme.error,
        behavior: SnackBarBehavior.floating,
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
        borderRadius: BorderRadius.circular(24), // Slightly smaller radius for cleaner look
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
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: -0.5),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.4), 
                    fontSize: 10, 
                    fontWeight: FontWeight.w600
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

  Widget _buildFindPhoneSection(AppState appState, ColorScheme scheme) {
    return GlassCardInteractive(
      onTap: appState.pairingService.activeDevice != null ? () => appState.findPhone() : null,
      accent: Colors.red,
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.ring_volume_rounded, color: Colors.red, size: 24),
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
                  'Ring at max volume to find it.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
