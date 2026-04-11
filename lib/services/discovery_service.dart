import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class DiscoveryPeerInfo {
  DiscoveryPeerInfo({
    required this.address,
    required this.deviceId,
    required this.deviceName,
    required this.wsPort,
    required this.filePort,
    required this.mode,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String address;
  final String deviceId;
  final String deviceName;
  final int wsPort;
  final int filePort;
  final String mode;
  final DateTime lastSeen;

  DiscoveryPeerInfo copyWith({DateTime? lastSeen}) {
    return DiscoveryPeerInfo(
      address: address,
      deviceId: deviceId,
      deviceName: deviceName,
      wsPort: wsPort,
      filePort: filePort,
      mode: mode,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class DiscoveryService {
  DiscoveryService({this.port = 45454, this.broadcastInterval = const Duration(seconds: 1)});

  final int port;
  final Duration broadcastInterval;
  RawDatagramSocket? _socket;
  Timer? _timer;

  Future<void> start({
    required String deviceId,
    required String deviceName,
    required int wsPort,
    required int filePort,
    required String currentMode,
    required void Function(DiscoveryPeerInfo info) onPeerFound,
  }) async {
    if (_socket != null) {
      return;
    }
    if (kIsWeb) return;

    // Android does not support reusePort on all kernels — skip it there to avoid
    // a noisy Dart socket error in the log. On macOS/desktop it works fine.
    final useReusePort = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: useReusePort,
      );
    } catch (e) {
      if (useReusePort) {
        // Fallback: retry without reusePort
        try {
          _socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            port,
            reuseAddress: true,
            reusePort: false,
          );
        } catch (_) {
          debugPrint('Discovery: could not bind UDP socket, skipping.');
          return;
        }
      } else {
        debugPrint('Discovery: could not bind UDP socket, skipping.');
        return;
      }
    }
    _socket!.broadcastEnabled = true;
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram == null) return;
        try {
          final message = jsonDecode(utf8.decode(datagram.data));
          if (message is Map<String, dynamic>) {
            final peerId = message['deviceId'] as String?;
            if (peerId == null || peerId == deviceId) {
              return;
            }
            final peerName = message['deviceName'] as String? ?? 'Wire Device';
            final ws = message['wsPort'] as int? ?? wsPort;
            final file = message['filePort'] as int? ?? filePort;
            final mode = message['mode'] as String? ?? 'auto';
            onPeerFound(
              DiscoveryPeerInfo(
                address: datagram.address.address,
                deviceId: peerId,
                deviceName: peerName,
                wsPort: ws,
                filePort: file,
                mode: mode,
              ),
            );
          }
        } catch (_) {
          // ignore
        }
      }
    });

    _timer = Timer.periodic(broadcastInterval, (_) async {
      try {
        if (_socket == null) return;
        final payload = jsonEncode({
          'type': 'wire_discovery',
          'deviceId': deviceId,
          'deviceName': deviceName,
          'wsPort': wsPort,
          'filePort': filePort,
          'mode': currentMode,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        if (!kIsWeb) {
          _socket!.send(utf8.encode(payload), InternetAddress('255.255.255.255'), port);
        }
      } catch (e) {
        // ignore broadcast errors
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}
