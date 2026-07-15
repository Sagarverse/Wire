import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../providers/app_state.dart';

class WebSocketService {
  WebSocketService({this.port = 5757});

  final int port;
  HttpServer? _server;
  final Set<WebSocket> _serverClients = {};
  final Map<WebSocket, DateTime> _serverLastSeen = {};
  String? _lastClientAddress;
  WebSocket? _clientSocket;
  int? _actualPort;
  DateTime? _clientLastSeen;
  Timer? _heartbeatTimer;
  Duration _heartbeatInterval = const Duration(seconds: 15);
  bool _aggressiveHeartbeat = false;
  String? _lastError;
  String? get errorMessage => _lastError;
  final _incoming = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();

  // Prevent re-entrant heartbeat setup
  bool _heartbeatSetupInProgress = false;

  Stream<Map<String, dynamic>> get messages => _incoming.stream;
  Stream<ConnectionStatus> get status => _statusController.stream;

  bool get isClientConnected => _clientSocket != null && _clientSocket!.readyState == WebSocket.open;
  bool get hasServerClients => _serverClients.any((s) => s.readyState == WebSocket.open);
  bool get isConnected => isClientConnected || hasServerClients;
  bool get isServerRunning => _server != null;
  String? get lastClientAddress => _lastClientAddress;
  int get actualPort => _actualPort ?? port;
  ConnectionStatus get statusValue => _calculateCurrentStatus();

  ConnectionStatus _calculateCurrentStatus() {
    if (isClientConnected || hasServerClients) {
      return ConnectionStatus.connected;
    }
    if (_clientSocket != null && _clientSocket!.readyState == WebSocket.connecting) {
      return ConnectionStatus.connecting;
    }
    if (_lastError != null) {
      return ConnectionStatus.error;
    }
    return ConnectionStatus.disconnected;
  }

  void _emitStatus() {
    _statusController.add(_calculateCurrentStatus());
  }

  Future<void> startServer() async {
    if (_server != null) {
      return;
    }
    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
    } catch (e) {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: true,
      );
    }
    _actualPort = _server!.port;
    _emitStatus();
    _ensureHeartbeatTimer();
    
    _server!.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        _lastClientAddress = request.connectionInfo?.remoteAddress.address;
        try {
          final socket = await WebSocketTransformer.upgrade(request);
          _serverClients.add(socket);
          _serverLastSeen[socket] = DateTime.now();
          _emitStatus();
          _ensureHeartbeatTimer();
          
          socket.listen(
            (data) => _handleIncoming(data, socket: socket),
            onDone: () {
              _serverClients.remove(socket);
              _serverLastSeen.remove(socket);
              _emitStatus();
              _ensureHeartbeatTimer();
            },
            onError: (e) {
              _lastError = e.toString();
              _serverClients.remove(socket);
              _serverLastSeen.remove(socket);
              _emitStatus();
              _ensureHeartbeatTimer();
            },
          );
        } catch (e) {
          _lastError = e.toString();
          _emitStatus();
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
  }

  Future<void> connectToPeer(String host, {int? portOverride}) async {
    if (host.isEmpty) return;
    final targetPort = portOverride ?? port;
    final uri = Uri.parse('ws://$host:$targetPort');
    _lastError = null;
    _emitStatus();
    
    try {
      await _clientSocket?.close();
      _clientSocket = null;
      _clientLastSeen = null;
      
      _clientSocket = await WebSocket.connect(
        uri.toString(),
      ).timeout(const Duration(seconds: 5));
      
      _clientLastSeen = DateTime.now();
      _emitStatus();
      _ensureHeartbeatTimer();
      
      _clientSocket?.listen(
        (data) => _handleIncoming(data, socket: _clientSocket),
        onDone: () {
          _clientSocket = null;
          _clientLastSeen = null;
          _emitStatus();
          _ensureHeartbeatTimer();
        },
        onError: (e) {
          _lastError = e.toString();
          _clientSocket = null;
          _clientLastSeen = null;
          _emitStatus();
          _ensureHeartbeatTimer();
        },
      );
    } catch (e) {
      _lastError = e.toString();
      _clientSocket = null;
      _clientLastSeen = null;
      _emitStatus();
      _ensureHeartbeatTimer();
      rethrow;
    }
  }

  void send(Map<String, dynamic> message) {
    final data = jsonEncode(message);
    try {
      if (_clientSocket != null && _clientSocket!.readyState == WebSocket.open) {
        _clientSocket!.add(data);
      }
      for (final client in _serverClients.toList()) {
        if (client.readyState == WebSocket.open) {
          client.add(data);
        }
      }
    } catch (e) {
      debugPrint('Error sending WebSocket message: $e');
    }
  }

  Future<void> disconnectClient() async {
    try {
      await _clientSocket?.close();
    } catch (_) {}
    _clientSocket = null;
    _clientLastSeen = null;
    _ensureHeartbeatTimer();
  }

  Future<void> disconnect() async {
    await disconnectClient();
  }

  Future<void> stopServer() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    
    for (final client in _serverClients.toList()) {
      try {
        await client.close();
      } catch (_) {}
    }
    _serverClients.clear();
    _serverLastSeen.clear();
    
    await _server?.close(force: true);
    _server = null;
    _actualPort = null;
    _emitStatus();
    debugPrint('WebSocketService: Local server stopped.');
  }

  void _handleIncoming(dynamic data, {WebSocket? socket}) {
    try {
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          final type = decoded['type']?.toString();
          if (type == 'ping') {
            try {
              socket?.add(jsonEncode({'type': 'pong'}));
            } catch (_) {}
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

  void setAggressiveHeartbeat(bool aggressive) {
    if (_aggressiveHeartbeat == aggressive) return;
    _aggressiveHeartbeat = aggressive;
    _ensureHeartbeatTimer();
  }

  void _updateLastSeen(WebSocket? socket) {
    if (socket == null) return;
    if (socket == _clientSocket) {
      _clientLastSeen = DateTime.now();
    } else if (_serverLastSeen.containsKey(socket)) {
      _serverLastSeen[socket] = DateTime.now();
    }
  }

  void broadcast(Map<String, dynamic> data) {
    final message = jsonEncode(data);
    try {
      _clientSocket?.add(message);
    } catch (_) {}
    for (final client in _serverClients.toList()) {
      try {
        client.add(message);
      } catch (_) {}
    }
  }

  void _ensureHeartbeatTimer() {
    // ** FIX: Prevent re-entrant calls from causing infinite loops **
    if (_heartbeatSetupInProgress) return;
    _heartbeatSetupInProgress = true;

    try {
      final connected = isClientConnected || _serverClients.isNotEmpty;
      var nextInterval = connected
          ? const Duration(seconds: 10)
          : const Duration(seconds: 30);
      if (_aggressiveHeartbeat && connected) {
        nextInterval = const Duration(seconds: 3);
      }
      
      // Only recreate if interval changed or timer is null
      if (_heartbeatTimer != null && _heartbeatInterval == nextInterval) {
        return;
      }
      
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _heartbeatInterval = nextInterval;

      if (!connected) {
        // No connections, no need for heartbeat
        return;
      }

      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
        _performHeartbeat();
      });
    } finally {
      _heartbeatSetupInProgress = false;
    }
  }

  void _performHeartbeat() {
    final now = DateTime.now();
    
    // Check client socket
    if (_clientSocket != null) {
      try {
        _clientSocket?.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
      if (_clientLastSeen != null &&
          now.difference(_clientLastSeen!).inSeconds > 15) {
        try {
          _clientSocket?.close();
        } catch (_) {}
        _clientSocket = null;
        _clientLastSeen = null;
        if (_serverClients.isEmpty) {
          _statusController.add(ConnectionStatus.disconnected);
        }
      }
    }
    
    // Check server clients
    final staleClients = <WebSocket>[];
    for (final client in _serverClients.toList()) {
      try {
        client.add(jsonEncode({'type': 'ping'}));
      } catch (_) {
        staleClients.add(client);
        continue;
      }
      final last = _serverLastSeen[client];
      if (last != null && now.difference(last).inSeconds > 15) {
        staleClients.add(client);
      }
    }
    
    for (final client in staleClients) {
      try {
        client.close();
      } catch (_) {}
      _serverClients.remove(client);
      _serverLastSeen.remove(client);
    }
    
    if (_clientSocket == null && _serverClients.isEmpty) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _statusController.add(ConnectionStatus.disconnected);
    }
  }

  Future<void> dispose() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    for (final client in _serverClients.toList()) {
      try {
        await client.close();
      } catch (_) {}
    }
    _serverClients.clear();
    _serverLastSeen.clear();
    try {
      await _clientSocket?.close();
    } catch (_) {}
    await _server?.close(force: true);
    _server = null;
    await _incoming.close();
    await _statusController.close();
  }
}

