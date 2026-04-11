import 'dart:async';
import 'package:flutter/material.dart';
import '../../providers/app_state.dart';
import 'package:provider/provider.dart';
import 'glass_card.dart';

class P2PConnectionDialog extends StatefulWidget {
  const P2PConnectionDialog({super.key});

  @override
  State<P2PConnectionDialog> createState() => _P2PConnectionDialogState();
}

class _P2PConnectionDialogState extends State<P2PConnectionDialog> with SingleTickerProviderStateMixin {
  bool _connecting = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initiateAutoConnect() async {
    setState(() => _connecting = true);
    final app = context.read<AppState>();
    final activeDevice = app.pairingService.activeDevice;

    if (activeDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No device paired locally yet.')),
      );
      setState(() => _connecting = false);
      return;
    }

    app.webrtcP2PService.onConnectionStateChange = (state) {
      if (state == ConnectionState.done && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to ${activeDevice.name} via Internet!')),
        );
      }
    };

    // Use deviceId as the signaling host
    await app.webrtcP2PService.initiateConnection(app.deviceId, activeDevice.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeDevice = context.watch<AppState>().pairingService.activeDevice;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassCard(
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.all(32),
        accent: scheme.primary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, size: 64, color: scheme.primary),
            const SizedBox(height: 24),
            const Text(
              'CLOUD SYNC',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 4, fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              activeDevice != null 
                ? 'Ready to connect to your paired device:\n${activeDevice.name}'
                : 'Pair a device locally first to enable Cloud Sync.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7), height: 1.5),
            ),
            const SizedBox(height: 32),
            if (_connecting)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Establishing P2P Tunnel...', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: activeDevice != null ? _initiateAutoConnect : null,
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('CONNECT NOW', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            if (!_connecting)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5))),
              )
          ],
        ),
      ),
    );
  }
}
