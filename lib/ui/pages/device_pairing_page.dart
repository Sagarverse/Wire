import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../services/discovery_service.dart';
import '../../services/pairing_service.dart';
import '../../widgets/liquid_background.dart';
import '../widgets/qr_pairing_dialog.dart';

class DevicePairingPage extends StatefulWidget {
  final PairingService pairingService;
  final List<DiscoveryPeerInfo> discoveredPeers;
  final String localDeviceId;
  final Function(PairedDevice device) onMakeActive;
  final Function(DiscoveryPeerInfo peer) onConnectToPeer;

  const DevicePairingPage({
    super.key,
    required this.pairingService,
    required this.discoveredPeers,
    required this.localDeviceId,
    required this.onMakeActive,
    required this.onConnectToPeer,
  });

  @override
  State<DevicePairingPage> createState() => _DevicePairingPageState();
}

class _DevicePairingPageState extends State<DevicePairingPage> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _handledScan = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>();
    final devices = widget.pairingService.devices;
    final activeId = widget.pairingService.activeDevice?.deviceId;
    final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Pair Device', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: LiquidBackground(
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Hero Section
                    _buildHeroSection(context, isMac).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
                    const SizedBox(height: 32),

                    // Scanner (Phone only)
                    if (!kIsWeb && !isMac) ...[
                      _buildScannerSection(scheme).animate().fadeIn(duration: 500.ms, delay: 200.ms),
                      const SizedBox(height: 32),
                    ],

                    // Paired Devices Header
                    if (devices.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Saved Devices',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: scheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                          TextButton(
                            onPressed: appState.clearAllPairings,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            child: const Text('Forget All', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
                      const SizedBox(height: 12),
                    ],
                  ]),
                ),
              ),

              // Paired Devices List
              if (devices.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final device = devices[index];
                        return _PairedDeviceTile(
                          device: device,
                          isActive: device.deviceId == activeId,
                          onConnect: () => widget.onMakeActive(device),
                          onForget: () => _forgetDevice(context, appState, device),
                        ).animate().fadeIn(duration: 400.ms, delay: (400 + (index * 100)).ms).slideX(begin: 0.05);
                      },
                      childCount: devices.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Text(
                          'No saved devices',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: 500.ms),
                  ),
                ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, bool isMac) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isMac ? Icons.qr_code_2_rounded : Icons.document_scanner_rounded,
            size: 40,
            color: scheme.primary,
          ),
        ).animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(duration: 2.seconds, begin: const Offset(1, 1), end: const Offset(1.05, 1.05)),
        const SizedBox(height: 24),
        Text(
          isMac ? 'Connect Your Phone' : 'Scan to Connect',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          isMac
              ? 'Open the Wire app on your Android phone and scan the QR code to establish a secure link.'
              : 'Point your camera at the QR code displayed on your Mac to pair instantly.',
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.6),
            fontSize: 14,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        if (isMac) ...[
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _openPrimaryPairingSurface(context),
            icon: const Icon(Icons.qr_code_rounded),
            label: const Text('Show QR Code'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              minimumSize: const Size(200, 54),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildScannerSection(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.05),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: (capture) {
                  if (_handledScan) return;
                  for (final barcode in capture.barcodes) {
                    final raw = barcode.rawValue;
                    if (raw != null && raw.isNotEmpty) {
                      _handleQr(raw);
                      return;
                    }
                  }
                },
              ),
              // Scanner Overlay overlay
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScannerOverlayPainter(color: scheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPrimaryPairingSurface(BuildContext context) {
    final appState = context.read<AppState>();
    showDialog(
      context: context,
      builder: (_) => QrPairingDialog(
        deviceId: appState.deviceId,
        deviceName: appState.deviceName,
        port: 5757,
        mode: 'auto',
      ),
    );
  }

  void _handleQr(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final List<String> ips = (data['ips'] is List) 
          ? (data['ips'] as List).map((e) => e.toString()).toList() 
          : [data['ip']?.toString() ?? ''];
      
      final peer = DiscoveryPeerInfo(
        address: data['ip']?.toString() ?? '',
        addresses: ips,
        deviceId: data['id']?.toString() ?? '',
        deviceName: data['name']?.toString() ?? 'Mac',
        wsPort: data['port'] as int? ?? 5757,
        filePort: data['filePort'] as int? ?? 5758,
        mode: 'auto',
      );

      if (peer.address.isEmpty || peer.deviceId.isEmpty) {
        return;
      }

      setState(() => _handledScan = true);
      widget.onConnectToPeer(peer);
      
      if (mounted) {
        // Show success and pop back
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text('Paired with ${peer.deviceName}'),
              ],
            ),
            backgroundColor: const Color(0xFF34C759),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      // Invalid QR code
      setState(() => _handledScan = false);
    }
  }

  Future<void> _forgetDevice(BuildContext context, AppState appState, PairedDevice device) async {
    await appState.removeSavedDevice(device.deviceId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${device.name} removed')),
      );
    }
  }
}

// ─── Scanner Overlay Painter ───────────────────────────────────────────────────

class _ScannerOverlayPainter extends CustomPainter {
  final Color color;

  _ScannerOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final length = size.width * 0.15;
    final w = size.width;
    final h = size.height;
    const padding = 20.0;

    // Top left
    canvas.drawLine(Offset(padding, padding + length), const Offset(padding, padding), paint);
    canvas.drawLine(const Offset(padding, padding), Offset(padding + length, padding), paint);

    // Top right
    canvas.drawLine(Offset(w - padding - length, padding), Offset(w - padding, padding), paint);
    canvas.drawLine(Offset(w - padding, padding), Offset(w - padding, padding + length), paint);

    // Bottom left
    canvas.drawLine(Offset(padding, h - padding - length), Offset(padding, h - padding), paint);
    canvas.drawLine(Offset(padding, h - padding), Offset(padding + length, h - padding), paint);

    // Bottom right
    canvas.drawLine(Offset(w - padding, h - padding - length), Offset(w - padding, h - padding), paint);
    canvas.drawLine(Offset(w - padding - length, h - padding), Offset(w - padding, h - padding), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Paired Device Tile ────────────────────────────────────────────────────────

class _PairedDeviceTile extends StatelessWidget {
  final PairedDevice device;
  final bool isActive;
  final VoidCallback onConnect;
  final VoidCallback onForget;

  const _PairedDeviceTile({
    required this.device,
    required this.isActive,
    required this.onConnect,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMac = device.osType == 'macos';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive 
              ? scheme.primary.withValues(alpha: 0.4) 
              : scheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Device Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMac ? Icons.laptop_mac_rounded : Icons.phone_android_rounded,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          
          // Device Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF34C759) : scheme.onSurface.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isActive ? 'Active' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          if (!isActive)
            IconButton(
              onPressed: onConnect,
              icon: const Icon(Icons.link_rounded),
              style: IconButton.styleFrom(
                backgroundColor: scheme.primary.withValues(alpha: 0.1),
                foregroundColor: scheme.primary,
              ),
            ),
          if (!isActive) const SizedBox(width: 8),
          IconButton(
            onPressed: onForget,
            icon: const Icon(Icons.delete_outline_rounded),
            style: IconButton.styleFrom(
              foregroundColor: Colors.redAccent.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
