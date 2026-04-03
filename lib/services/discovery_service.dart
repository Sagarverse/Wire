import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveryPeerInfo {
  DiscoveryPeerInfo({
    required this.address,
    required this.deviceId,
    required this.deviceName,
    required this.wsPort,
    required this.filePort,
  });

  final InternetAddress address;
  final String deviceId;
  final String deviceName;
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
    required String deviceName,
    required int wsPort,
    required int filePort,
    required void Function(DiscoveryPeerInfo info) onPeerFound,
  }) async {
    if (_socket != null) {
      return;
    }
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true, reusePort: true);
    } catch (_) {
      // Port might be held briefly after restart — retry with reusePort
      try {
        _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      } catch (_) {
        return; // Can't bind, skip discovery
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
            onPeerFound(
              DiscoveryPeerInfo(
                address: datagram.address,
                deviceId: peerId,
                deviceName: peerName,
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

    _timer = Timer.periodic(broadcastInterval, (_) async {
      try {
        if (_socket == null) return;
        final payload = jsonEncode({
          'type': 'wire_discovery',
          'deviceId': deviceId,
          'deviceName': deviceName,
          'wsPort': wsPort,
          'filePort': filePort,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        
        _socket!.send(utf8.encode(payload), InternetAddress('255.255.255.255'), port);
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
