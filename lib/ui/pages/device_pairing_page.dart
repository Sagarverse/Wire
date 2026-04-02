import 'package:flutter/material.dart';
import '../../services/pairing_service.dart';
import '../../services/discovery_service.dart';

class DevicePairingPage extends StatefulWidget {
  final PairingService pairingService;
  final List<DiscoveryPeerInfo> discoveredPeers;
  final String localDeviceId;
  final void Function(PairedDevice device) onMakeActive;
  final void Function(DiscoveryPeerInfo peer) onConnectToPeer;

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
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paired = widget.pairingService.devices;
    final active = widget.pairingService.activeDevice;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Paired Devices'),
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                'ACTIVE DEVICE',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          if (active != null)
            SliverToBoxAdapter(
              child: _buildDeviceTile(
                title: active.name,
                subtitle: 'Connected · ${active.lastIp}',
                icon: _getIconForOs(active.osType),
                isActive: true,
                onTap: null, // Already active
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  'No active device. Select a paired device or discover a new one.',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
            ),
            
          const SliverPadding(padding: EdgeInsets.only(top: 24)),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                'SAVED DEVICES',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
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
                );
              },
              childCount: paired.length,
            ),
          ),
          if (paired.isEmpty || (paired.length == 1 && active != null))
            SliverToBoxAdapter(
               child: Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                 child: Text(
                   'No other saved devices.',
                   style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                 ),
               ),
            ),

          const SliverPadding(padding: EdgeInsets.only(top: 24)),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Text(
                    'DISCOVERED ON NETWORK',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12, 
                    height: 12, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final peer = widget.discoveredPeers[index];
                // Hide if it's already paired
                if (paired.any((d) => d.deviceId == peer.deviceId)) {
                  return const SizedBox.shrink();
                }
                return _buildDeviceTile(
                  title: 'Discovered Device', // We don't know the name until handshake
                  subtitle: peer.address.address,
                  icon: Icons.devices,
                  trailingIcon: Icons.add_circle_outline,
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
                 padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                 child: Text(
                   'No new devices found nearby.',
                   style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                 ),
               ),
            ),
            
          const SliverPadding(padding: EdgeInsets.only(top: 40)),
        ],
      ),
    );
  }

  void _removeDevice(PairedDevice d) async {
    await widget.pairingService.removeDevice(d.deviceId);
    setState(() {});
  }

  IconData _getIconForOs(String osType) {
    if (osType.toLowerCase() == 'android') return Icons.android;
    if (osType.toLowerCase() == 'macos') return Icons.laptop_mac;
    if (osType.toLowerCase() == 'ios') return Icons.phone_iphone;
    if (osType.toLowerCase() == 'windows') return Icons.laptop_windows;
    return Icons.devices;
  }

  Widget _buildDeviceTile({
    required String title,
    required String subtitle,
    required IconData icon,
    bool isActive = false,
    IconData? trailingIcon,
    VoidCallback? onTap,
    VoidCallback? onDelete,
  }) {
    final scheme = Theme.of(context).colorScheme;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: isActive ? Border.all(color: scheme.primary.withValues(alpha: 0.3)) : null,
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive ? scheme.primary.withValues(alpha: 0.2) : scheme.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: isActive ? scheme.primary : scheme.onSurface),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailingIcon != null)
              Icon(trailingIcon, color: scheme.primary),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.delete_outline, color: scheme.error),
                onPressed: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
