import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WebSocketService {
  WebSocketService({this.port = 5757});

  final int port;
  HttpServer? _server;
  final Set<WebSocket> _serverClients = {};
  final Map<WebSocket, DateTime> _serverLastSeen = {};
  String? _lastClientAddress;
  WebSocket? _clientSocket;
  DateTime? _clientLastSeen;
  Timer? _heartbeatTimer;
  Duration _heartbeatInterval = const Duration(seconds: 30);
  final _incoming = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _incoming.stream;

  bool get isClientConnected => _clientSocket?.readyState == WebSocket.open;
  bool get hasServerClients => _serverClients.isNotEmpty;
  String? get lastClientAddress => _lastClientAddress;

  Future<void> startServer() async {
    if (_server != null) {
      return;
    }
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _ensureHeartbeatTimer();
    _server!.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        _lastClientAddress = request.connectionInfo?.remoteAddress.address;
        final socket = await WebSocketTransformer.upgrade(request);
        _serverClients.add(socket);
        _serverLastSeen[socket] = DateTime.now();
        _ensureHeartbeatTimer();
        socket.listen(
          (data) => _handleIncoming(data, socket: socket),
          onDone: () {
            _serverClients.remove(socket);
            _serverLastSeen.remove(socket);
            _ensureHeartbeatTimer();
          },
          onError: (_) {
            _serverClients.remove(socket);
            _serverLastSeen.remove(socket);
            _ensureHeartbeatTimer();
          },
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
  }

  Future<void> connectToPeer(String host, {int? portOverride}) async {
    final targetPort = portOverride ?? port;
    final uri = Uri.parse('ws://$host:$targetPort');
    try {
      await _clientSocket?.close();
      _clientSocket = await WebSocket.connect(uri.toString());
      _clientLastSeen = DateTime.now();
      _ensureHeartbeatTimer();
      _clientSocket?.listen(
        (data) => _handleIncoming(data, socket: _clientSocket),
        onDone: () {
          _clientSocket = null;
          _clientLastSeen = null;
          _ensureHeartbeatTimer();
        },
        onError: (_) {
          _clientSocket = null;
          _clientLastSeen = null;
          _ensureHeartbeatTimer();
        },
      );
    } catch (_) {
      _clientSocket = null;
      _clientLastSeen = null;
      _ensureHeartbeatTimer();
    }
  }

  void send(Map<String, dynamic> message) {
    final data = jsonEncode(message);
    if (_clientSocket != null && _clientSocket!.readyState == WebSocket.open) {
      _clientSocket!.add(data);
    }
    for (final client in _serverClients) {
      if (client.readyState == WebSocket.open) {
        client.add(data);
      }
    }
  }

  Future<void> disconnectClient() async {
    await _clientSocket?.close();
    _clientSocket = null;
    _clientLastSeen = null;
    _ensureHeartbeatTimer();
  }

  void _handleIncoming(dynamic data, {WebSocket? socket}) {
    try {
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          final type = decoded['type']?.toString();
          if (type == 'ping') {
            socket?.add(jsonEncode({'type': 'pong'}));
            _updateLastSeen(socket);
            return;
          }
          if (type == 'pong') {
            _updateLastSeen(socket);
            return;
          }
          _updateLastSeen(socket);
          _incoming.add(decoded);
        }
      }
    } catch (_) {
      // ignore
    }
  }

  void _updateLastSeen(WebSocket? socket) {
    if (socket == null) return;
    if (socket == _clientSocket) {
      _clientLastSeen = DateTime.now();
    } else if (_serverLastSeen.containsKey(socket)) {
      _serverLastSeen[socket] = DateTime.now();
    }
  }

  void _ensureHeartbeatTimer() {
    final connected = isClientConnected || _serverClients.isNotEmpty;
    final nextInterval = connected ? const Duration(seconds: 10) : const Duration(seconds: 30);
    if (_heartbeatTimer != null && _heartbeatInterval == nextInterval) {
      return;
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatInterval = nextInterval;
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final now = DateTime.now();
      if (_clientSocket != null) {
        _clientSocket?.add(jsonEncode({'type': 'ping'}));
        if (_clientLastSeen != null && now.difference(_clientLastSeen!).inSeconds > 90) {
          _clientSocket?.close();
          _clientSocket = null;
          _clientLastSeen = null;
          _ensureHeartbeatTimer();
        }
      }
      for (final client in _serverClients.toList()) {
        client.add(jsonEncode({'type': 'ping'}));
        final last = _serverLastSeen[client];
        if (last != null && now.difference(last).inSeconds > 90) {
          client.close();
          _serverClients.remove(client);
          _serverLastSeen.remove(client);
          _ensureHeartbeatTimer();
        }
      }
      if (_clientSocket == null && _serverClients.isEmpty) {
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
      }
    });
  }

  Future<void> dispose() async {
    for (final client in _serverClients) {
      await client.close();
    }
    _serverClients.clear();
    _serverLastSeen.clear();
    await _clientSocket?.close();
    await _server?.close(force: true);
    _server = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _incoming.close();
  }
}
