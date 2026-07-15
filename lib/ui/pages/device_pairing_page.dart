import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
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
      appBar: AppBar(title: const Text('Pair device')),
      body: LiquidBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          children: [
            _PairingHero(isMac: isMac, onPrimary: () => _openPrimaryPairingSurface(context)),
            const SizedBox(height: 20),
            if (!kIsWeb && !isMac) ...[
              _ScannerCard(
                controller: _scannerController,
                onDetected: _handledScan ? null : (raw) => _handleQr(raw),
              ),
              const SizedBox(height: 20),
            ],
            _SectionCard(
              title: 'How pairing works',
              child: Text(
                isMac
                    ? 'Keep this QR code open on your Mac, then scan it from the Android phone. The app chooses local Wi-Fi first and falls back to internet automatically.'
                    : 'Open pairing on the Mac, scan its QR code here, and the link is created automatically. There is no manual network selection in the UI.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
              ),
            ),
            const SizedBox(height: 20),
            _SectionCard(
              title: 'Paired devices',
              child: devices.isEmpty
                  ? const Text('No paired devices yet.')
                  : Column(
                      children: devices
                          .map(
                            (device) => _PairedDeviceTile(
                              device: device,
                              isActive: device.deviceId == activeId,
                              onConnect: () => widget.onMakeActive(device),
                              onForget: () => _forgetDevice(context, appState, device),
                            ),
                          )
                          .toList(),
                    ),
            ),
            if (devices.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: appState.clearAllPairings,
                child: const Text('Forget all devices'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openPrimaryPairingSurface(BuildContext context) {
    final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    if (isMac) {
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
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan from phone'),
        content: const Text('Use the scanner on this page to scan the QR code shown on your Mac.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connecting to ${peer.deviceName}')),
        );
      }
    } catch (_) {}
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

class _PairingHero extends StatelessWidget {
  final bool isMac;
  final VoidCallback onPrimary;

  const _PairingHero({
    required this.isMac,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMac ? 'Show QR on the Mac.' : 'Scan QR on the phone.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            isMac
                ? 'This Mac acts as the pairing source. Your phone scans the code and the connection is created automatically.'
                : 'Scan the Mac QR code here. After pairing, clipboard sync, file sharing, remote file access, and ringing are ready.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.68),
                ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onPrimary,
            child: Text(isMac ? 'Show QR code' : 'Pair with Mac'),
          ),
        ],
      ),
    );
  }
}

class _ScannerCard extends StatelessWidget {
  final MobileScannerController controller;
  final ValueChanged<String>? onDetected;

  const _ScannerCard({
    required this.controller,
    required this.onDetected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('QR scanner', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 1,
              child: MobileScanner(
                controller: controller,
                onDetect: (capture) {
                  if (onDetected == null) {
                    return;
                  }
                  for (final barcode in capture.barcodes) {
                    final raw = barcode.rawValue;
                    if (raw != null && raw.isNotEmpty) {
                      onDetected!(raw);
                      return;
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Point the camera at the QR code displayed by the Mac app.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(device.osType == 'macos' ? Icons.laptop_mac_rounded : Icons.phone_android_rounded),
      title: Text(device.name),
      subtitle: Text(isActive ? 'Active device' : 'Ready to reconnect'),
      trailing: Wrap(
        spacing: 8,
        children: [
          TextButton(onPressed: onConnect, child: const Text('Connect')),
          TextButton(onPressed: onForget, child: const Text('Forget')),
        ],
      ),
    );
  }
}
