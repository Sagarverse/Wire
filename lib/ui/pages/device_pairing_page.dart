import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../services/pairing_service.dart';
import '../../services/discovery_service.dart';
import '../../services/websocket_service.dart';
import '../../providers/app_state.dart';
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

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context);
    final paired = widget.pairingService.devices;
    final active = widget.pairingService.activeDevice;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('DEVICES', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
           IconButton(
             icon: const Icon(Icons.qr_code_2_rounded),
             onPressed: () => _showQrGenerator(context),
             tooltip: 'Show QR Code',
           ),
           if (!kIsWeb && defaultTargetPlatform != TargetPlatform.macOS)
             IconButton(
               icon: const Icon(Icons.qr_code_scanner_rounded),
               onPressed: () => _openScanner(context),
               tooltip: 'Scan QR Code',
             ),
           IconButton(
             icon: const Icon(Icons.refresh_rounded),
             onPressed: () => appState.refreshDiscovery(),
             tooltip: 'Refresh Nearby Devices',
           ),
        ],
      ),
      body: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (active != null) ...[
                    _buildSectionHeader('ACTIVE DEVICE', scheme),
                    _buildActiveCard(active, scheme, appState),
                    const SizedBox(height: 24),
                  ],
                  _buildSectionHeader('NEARBY & SAVED', scheme),
                  _buildDevicesList(paired, widget.discoveredPeers, active, scheme, appState),
                  const SizedBox(height: 120), // Bottom padding for dock
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: scheme.primary.withValues(alpha: 0.8),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildActiveCard(PairedDevice active, ColorScheme scheme, AppState appState) {
    final isConnected = appState.lastStatus == ConnectionStatus.connected;
    return Container(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: scheme.primary,
            radius: 28,
            child: Icon(
              active.osType == 'macos' ? Icons.laptop_mac_rounded : Icons.phone_android_rounded,
              color: scheme.onPrimary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(active.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text(
                  isConnected ? 'Connected • ${active.lastIp}' : 'Disconnected',
                  style: TextStyle(color: isConnected ? Colors.green : scheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                ),
              ],
            ),
          ),
          if (!isConnected)
            FilledButton.tonal(
              onPressed: () => appState.reconnect(),
              child: const Text('Connect'),
            )
          else
            IconButton(
              icon: const Icon(Icons.settings_remote_rounded),
              onPressed: () => appState.findPhone(),
              tooltip: 'Ring remote device',
            )
        ],
      ),
    );
  }

  Widget _buildDevicesList(
    List<PairedDevice> paired,
    List<DiscoveryPeerInfo> discovered,
    PairedDevice? active,
    ColorScheme scheme,
    AppState appState,
  ) {
    final Map<String, dynamic> merged = {};

    for (var p in paired) {
      if (p.deviceId != active?.deviceId) {
        merged[p.deviceId] = p;
      }
    }
    for (var d in discovered) {
      if (d.deviceId != active?.deviceId) {
        merged[d.deviceId] = d;
      }
    }

    if (merged.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.wifi_tethering_off_rounded, size: 48, color: scheme.onSurface.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text('No other devices found', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5))),
            ],
          ),
        ),
      );
    }

    return Column(
      children: merged.values.map((item) {
        final isPaired = item is PairedDevice;
        final name = isPaired ? item.name : (item as DiscoveryPeerInfo).deviceName;
        final osType = isPaired ? item.osType : 'unknown';
        final ip = isPaired ? item.lastIp : (item as DiscoveryPeerInfo).address;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Icon(
              osType == 'macos' ? Icons.laptop_mac_rounded : Icons.phone_android_rounded,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(ip, style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5))),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    if (isPaired) {
                      widget.onMakeActive(item as PairedDevice);
                    } else {
                      widget.onConnectToPeer(item as DiscoveryPeerInfo);
                    }
                  },
                  icon: Icon(isPaired ? Icons.swap_horiz_rounded : Icons.add_link_rounded, size: 16),
                  label: Text(isPaired ? 'Switch' : 'Pair'),
                  style: FilledButton.styleFrom(
                    backgroundColor: isPaired ? scheme.surfaceContainerHigh : scheme.primary,
                    foregroundColor: isPaired ? scheme.onSurface : scheme.onPrimary,
                  ),
                ),
                if (isPaired) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 20, color: scheme.error.withValues(alpha: 0.6)),
                    onPressed: () => _showDeleteConfirm(context, appState, item as PairedDevice),
                    tooltip: 'Remove Device',
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showDeleteConfirm(BuildContext context, AppState appState, PairedDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device?'),
        content: Text('Are you sure you want to remove "${device.name}"? You will need to re-pair it to connect again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              appState.removeSavedDevice(device.deviceId);
              Navigator.pop(ctx);
            },
            child: const Text('REMOVE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showQrGenerator(BuildContext context) async {
    final ips = await context.read<AppState>().getLocalIps();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => QrPairingDialog(
        deviceId: context.read<AppState>().deviceId,
        deviceName: context.read<AppState>().deviceName,
        port: 5757,
      ),
    );
  }

  void _openScanner(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 300,
            height: 400,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null) {
                        try {
                          final data = jsonDecode(barcode.rawValue!);
                          final peer = DiscoveryPeerInfo(
                            address: data['ip'],
                            deviceId: data['id'],
                            deviceName: data['name'],
                            wsPort: data['port'],
                            filePort: 5758,
                          );
                          widget.onConnectToPeer(peer);
                          Navigator.pop(context);
                          return;
                        } catch (_) {}
                      }
                    }
                  },
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: IconButton.filled(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                const Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Text(
                    'Scan Device QR',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, shadows: [Shadow(blurRadius: 10, color: Colors.black)]),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
