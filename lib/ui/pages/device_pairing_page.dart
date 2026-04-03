import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../services/pairing_service.dart';
import '../../services/discovery_service.dart';
import '../../services/websocket_service.dart';
import '../../providers/app_state.dart';
import '../widgets/qr_pairing_dialog.dart';
import '../widgets/manual_pair_dialog.dart';
import '../widgets/glass_card.dart';

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
        title: const Text('DEVICES'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: scheme.onSurface,
          letterSpacing: 2.5,
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: GlassCardInteractive(
                      onTap: () => _showQrGenerator(context),
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      borderRadius: BorderRadius.circular(20),
                      accent: scheme.primary,
                      child: Column(
                        children: [
                          Icon(Icons.qr_code_rounded, color: scheme.primary, size: 32),
                          const SizedBox(height: 8),
                          Text(
                            'Pair Code',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: scheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassCardInteractive(
                      onTap: () => _showManualPair(context),
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      borderRadius: BorderRadius.circular(20),
                      accent: scheme.tertiary,
                      child: Column(
                        children: [
                          Icon(Icons.lan_rounded, color: scheme.tertiary, size: 32),
                          const SizedBox(height: 8),
                          Text(
                            'Pair by IP',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: scheme.tertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassCardInteractive(
                      onTap: () => _openScanner(context),
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      borderRadius: BorderRadius.circular(20),
                      accent: scheme.secondary,
                      child: Column(
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, color: scheme.secondary, size: 32),
                          const SizedBox(height: 8),
                          Text(
                            'Scan QR',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: scheme.secondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          SliverToBoxAdapter(
            child: _buildMyDeviceInfo(context, appState, scheme),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Text(
                'ACTIVE DEVICE',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          
          if (active != null)
            SliverToBoxAdapter(
              child: _buildActiveDeviceCard(appState, active, scheme),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'No active device. Select a paired device or discover a new one.',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
                ),
              ),
            ),
            
          const SliverPadding(padding: EdgeInsets.only(top: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Text(
                'SAVED DEVICES',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final d = paired[index];
                if (d.deviceId == active?.deviceId) return const SizedBox.shrink();
                return _buildDeviceTile(
                  title: d.name,
                  subtitle: d.isTrusted ? 'Trusted · ${d.lastIp}' : 'Untrusted · ${d.lastIp}',
                  icon: _getIconForOs(d.osType),
                  trailingIcon: Icons.link,
                  onTap: () {
                    widget.onMakeActive(d);
                    Navigator.pop(context);
                  },
                  onDelete: () => _removeDevice(d),
                  batteryLevel: d.batteryLevel,
                  isCharging: d.isCharging ?? false,
                );
              },
              childCount: paired.length,
            ),
          ),
          if (paired.isEmpty || (paired.length == 1 && active != null))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Text(
                  'No other saved devices.',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(top: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(
                children: [
                  Text(
                    'DISCOVERED ON NETWORK',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final peer = widget.discoveredPeers[index];
                if (paired.any((d) => d.deviceId == peer.deviceId)) {
                  return const SizedBox.shrink();
                }
                return _buildDeviceTile(
                  title: peer.deviceName,
                  subtitle: peer.address.address,
                  icon: Icons.important_devices_rounded,
                  trailingIcon: Icons.add_circle_outline_rounded,
                  onTap: () {
                    widget.onConnectToPeer(peer);
                    Navigator.pop(context);
                  },
                );
              },
              childCount: widget.discoveredPeers.length,
            ),
          ),
          if (widget.discoveredPeers.every((p) => paired.any((d) => d.deviceId == p.deviceId)))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Text(
                  'No new devices found nearby.',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(top: 60)),
        ],
      ),
    );
  }

  void _showQrGenerator(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => QrPairingDialog(
        deviceId: widget.localDeviceId,
        deviceName: Platform.isMacOS ? 'Wire Mac' : 'Wire Device',
        port: 5757,
      ),
    );
  }

  void _showManualPair(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ManualPairDialog(
        onPair: (peer) {
          widget.onConnectToPeer(peer);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _showRenameDialog(PairedDevice d) {
    final controller = TextEditingController(text: d.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Rename Device', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      await widget.pairingService.renameDevice(d.deviceId, controller.text);
                      if (mounted) {
                        setState(() {});
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openScanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Scan Pairing Code')),
          body: MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  try {
                    final data = jsonDecode(barcode.rawValue!);
                    final peer = DiscoveryPeerInfo(
                      address: InternetAddress(data['ip']),
                      deviceId: data['id'],
                      deviceName: data['name'],
                      wsPort: data['port'],
                      filePort: 5758,
                    );
                    widget.onConnectToPeer(peer);
                    Navigator.pop(context);
                    return;
                  } catch (e) {
                    // Invalid QR
                  }
                }
              }
            },
          ),
        ),
      ),
    );
  }

  void _disconnectActive() async {
    await widget.pairingService.setActiveDevice(null);
    if (mounted) setState(() {});
  }

  void _removeDevice(PairedDevice d) async {
    await widget.pairingService.removeDevice(d.deviceId);
    if (mounted) setState(() {});
  }

  Widget _buildMyDeviceInfo(BuildContext context, AppState appState, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: GlassCard(
        accent: scheme.primary,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.info_outline_rounded, color: scheme.primary, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This Device: ${appState.deviceName}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Enter these details on your other device to connect.',
                        style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FutureBuilder<List<String>>(
              future: appState.getLocalIps(),
              builder: (context, snapshot) {
                final ips = snapshot.data ?? ['Detecting...'];
                return Row(
                  children: [
                    Expanded(
                      child: _buildDetail(scheme, 'Port', '5757'),
                    ),
                    Container(height: 30, width: 1, color: scheme.onSurface.withValues(alpha: 0.1)),
                    Expanded(
                      flex: 2,
                      child: _buildDetail(scheme, 'IP Address', ips.first),
                    ),
                  ],
                );
              },
            ),
            
            if (appState.lastStatus != ConnectionStatus.idle && appState.lastStatus != ConnectionStatus.disconnected) ...[
              const SizedBox(height: 20),
              _buildConnectionStatusBar(appState, scheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(ColorScheme scheme, String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: scheme.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Widget _buildConnectionStatusBar(AppState appState, ColorScheme scheme) {
    Color color = scheme.primary;
    String text = 'Ready';
    bool showLoading = false;

    switch (appState.lastStatus) {
      case ConnectionStatus.connecting:
        color = Colors.amber;
        text = 'Connecting...';
        showLoading = true;
        break;
      case ConnectionStatus.connected:
        color = Colors.green;
        text = 'Connected!';
        break;
      case ConnectionStatus.error:
        color = scheme.error;
        text = appState.errorMessage ?? 'Connection Failed';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          if (showLoading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
            )
          else
            Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForOs(String osType) {
    final os = osType.toLowerCase();
    if (os == 'android') return Icons.android_rounded;
    if (os == 'macos') return Icons.laptop_mac_rounded;
    if (os == 'ios') return Icons.phone_iphone_rounded;
    if (os == 'windows') return Icons.laptop_windows_rounded;
    return Icons.devices_rounded;
  }

  Widget _buildActiveDeviceCard(AppState appState, PairedDevice active, ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: GlassCard(
        accent: scheme.primary,
        borderRadius: BorderRadius.circular(32),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_getIconForOs(active.osType), color: scheme.primary, size: 32),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active.name,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Connected · ${active.lastIp}',
                            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          if (appState.remoteBattery != null) ...[
                            const SizedBox(width: 8),
                            Container(width: 4, height: 4, decoration: BoxDecoration(color: scheme.onSurface.withValues(alpha: 0.2), shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Icon(
                              appState.remoteIsCharging == true ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                              size: 14,
                              color: (appState.remoteBattery ?? 100) > 20 ? (appState.remoteIsCharging == true ? Colors.green : scheme.primary) : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${appState.remoteBattery}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: (appState.remoteBattery ?? 100) > 20 ? scheme.onSurface.withValues(alpha: 0.7) : Colors.red,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _disconnectActive(),
                  icon: Icon(Icons.link_off_rounded, color: scheme.error.withValues(alpha: 0.7)),
                  tooltip: 'Disconnect',
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _buildStatusChip(scheme, Icons.speed_rounded, '2 ms', 'Latency'),
                const SizedBox(width: 12),
                _buildStatusChip(scheme, Icons.wifi_tethering_rounded, 'Excellent', 'Signal'),
                const SizedBox(width: 12),
                _buildStatusChip(scheme, Icons.security_rounded, 'Trusted', 'Security'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(ColorScheme scheme, IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: scheme.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 6),
            Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12), overflow: TextOverflow.ellipsis)),
            Flexible(child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: scheme.onSurface.withValues(alpha: 0.4)), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceTile({
    required String title,
    required String subtitle,
    required IconData icon,
    bool isActive = false,
    IconData? trailingIcon,
    VoidCallback? onTap,
    VoidCallback? onDelete,
    int? batteryLevel,
    bool isCharging = false,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: GlassCardInteractive(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        accent: isActive ? scheme.primary : null,
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: scheme.onSurface, size: 20),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: scheme.onSurface,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 13, fontWeight: FontWeight.w500),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (batteryLevel != null) ...[
                Icon(
                  isCharging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                  size: 14,
                  color: batteryLevel > 20 ? (isCharging ? Colors.green : scheme.onSurface.withValues(alpha: 0.5)) : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  '$batteryLevel%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: batteryLevel > 20 ? scheme.onSurface.withValues(alpha: 0.7) : Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 16, color: scheme.onSurface.withValues(alpha: 0.1)),
                const SizedBox(width: 8),
              ],
              if (onDelete != null)
                IconButton(
                  icon: Icon(Icons.edit_note_rounded, color: scheme.primary.withValues(alpha: 0.6), size: 22),
                  onPressed: () {
                     try {
                       final d = widget.pairingService.devices.firstWhere((x) => x.name == title);
                       _showRenameDialog(d);
                     } catch (_) {}
                  },
                ),
              if (onDelete != null)
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: scheme.error.withValues(alpha: 0.6), size: 20),
                  onPressed: onDelete,
                ),
              if (trailingIcon != null && onDelete == null)
                Icon(trailingIcon, color: scheme.primary.withValues(alpha: 0.4), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
