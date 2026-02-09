import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveryPeerInfo {
  DiscoveryPeerInfo({required this.address, required this.deviceId, required this.wsPort, required this.filePort});

  final InternetAddress address;
  final String deviceId;
  final int wsPort;
  final int filePort;
}

class DiscoveryService {
  DiscoveryService({this.port = 45454, this.broadcastInterval = const Duration(seconds: 3)});

  final int port;
  final Duration broadcastInterval;
  RawDatagramSocket? _socket;
  Timer? _timer;

  Future<void> start({
    required String deviceId,
    required int wsPort,
    required int filePort,
    required void Function(DiscoveryPeerInfo info) onPeerFound,
  }) async {
    if (_socket != null) {
      return;
    }
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true, reusePort: false);
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
            final ws = message['wsPort'] as int? ?? wsPort;
            final file = message['filePort'] as int? ?? filePort;
            onPeerFound(
              DiscoveryPeerInfo(
                address: datagram.address,
                deviceId: peerId,
                wsPort: ws,
                filePort: file,
              ),
            );
          }
        } catch (_) {
          // ignore
        }
      }
    });

    _timer = Timer.periodic(broadcastInterval, (_) {
      try {
        if (_socket == null) return;
        final payload = jsonEncode({
          'type': 'wire_discovery',
          'deviceId': deviceId,
          'wsPort': wsPort,
          'filePort': filePort,
        });
        _socket!.send(utf8.encode(payload), InternetAddress('255.255.255.255'), port);
      } catch (_) {
        // ignore broadcast errors on restricted networks
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
