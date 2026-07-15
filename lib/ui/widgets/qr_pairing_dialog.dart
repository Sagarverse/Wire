import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrPairingDialog extends StatelessWidget {
  final String deviceId;
  final String deviceName;
  final int port;
  final String mode;

  const QrPairingDialog({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.port,
    required this.mode,
  });

  Future<List<String>> _getLocalIps() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) {
            ips.add(address.address);
          }
        }
      }
    } catch (_) {}
    return ips;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: FutureBuilder<List<String>>(
        future: _getLocalIps(),
        builder: (context, snapshot) {
          final ips = snapshot.data ?? const <String>[];
          final primaryIp = ips.isEmpty ? '' : ips.first;
          final qrData = jsonEncode({
            'id': deviceId,
            'name': deviceName,
            'ip': primaryIp,
            'ips': ips,
            'port': port,
            'filePort': 5758,
            'mode': mode,
          });

          return Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Pair with your phone', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  'Open W on Android and scan this QR code. The app will choose local Wi-Fi when available and fall back to internet automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: QrImageView(
                    data: qrData,
                    size: 220,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  primaryIp.isEmpty ? 'Waiting for a network address' : 'Mac address: $primaryIp',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.58),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
