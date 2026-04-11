import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ConnectionState;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

enum P2PRole { initiator, receiver }

class WebRTCP2PService {
  MqttServerClient? _mqttClient;
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  List<Map<String, String>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun3.l.google.com:19302'},
    {'urls': 'stun:stun4.l.google.com:19302'},
    {'urls': 'stun:stun.nextcloud.com:443'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
    {'urls': 'stun:stun.anyfirewall.com:3478'},
    {'urls': 'stun:stun.stunprotocol.org:3478'},
    {'urls': 'stun:stun.voiparound.com:3478'},
    {'urls': 'stun:stun.voipstunt.com:3478'},
  ];

  // WebRTC
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final String _clientId = const Uuid().v4();

  // Callbacks
  Function(String text)? onMessageReceived;
  final _onBinaryReceived = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get onBinaryReceived => _onBinaryReceived.stream;
  Function(ConnectionState state)? onConnectionStateChange;

  String? _myId;
  String? _currentTargetId;
  Timer? _heartbeatTimer;
  bool _isInitialConnection = true;
  bool _isInitializing = false;

  void setIceServers(List<Map<String, String>> servers) {
    _iceServers = servers;
  }

  Future<void> initialize() async {
    if (_isInitializing) return;
    if (_mqttClient?.connectionStatus?.state == MqttConnectionState.connected) return;

    _isInitializing = true;
    _mqttClient = MqttServerClient.withPort('broker.hivemq.com', _clientId, 8884);
    _mqttClient!.useWebSocket = true;
    _mqttClient!.secure = true;
    _mqttClient!.setProtocolV311();
    _mqttClient!.logging(on: false);
    _mqttClient!.keepAlivePeriod = 20;
    _mqttClient!.autoReconnect = true;
    _mqttClient!.onDisconnected = () {
        debugPrint('WebRTC Signaling: Secure WSS Disconnected');
    };
    _mqttClient!.onConnected = () {
      debugPrint('WebRTC Signaling: MQTT Connected');
      if (!_isInitialConnection && _myId != null) {
        // Re-subscribe after reconnect
        startListening(_myId!);
      }
      _isInitialConnection = false;
    };

    final connMess = MqttConnectMessage()
        .withClientIdentifier(_clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _mqttClient!.connectionMessage = connMess;

    try {
      await _mqttClient!.connect().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('MQTT Connection Error: $e');
      _mqttClient!.disconnect();
      _isInitializing = false;
      return;
    }
    
    _isInitializing = false;

    _mqttClient!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c == null) return;
      final recMess = c[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      _handleSignalingMessage(payload);
    });
  }

  Future<void> startListening(String myId) async {
    _myId = myId;
    
    if (_mqttClient?.connectionStatus?.state != MqttConnectionState.connected) {
      await initialize();
    }

    if (_mqttClient?.connectionStatus?.state == MqttConnectionState.connected) {
      // Listen for offers directed specifically to my deviceId
      _mqttClient!.subscribe(
        'wire/p2p/+_to_$myId',
        MqttQos.atLeastOnce,
      );
    }
  }

  Future<void> initiateConnection(String sourceId, String targetId) async {
    _myId = sourceId;
    _currentTargetId = targetId;
    
    // Ensure we are connected before subscribing
    if (_mqttClient?.connectionStatus?.state != MqttConnectionState.connected) {
      debugPrint('WebRTC Signaling: Waiting for MQTT connection before initiation...');
      await initialize();
    }

    if (_mqttClient?.connectionStatus?.state != MqttConnectionState.connected) {
       debugPrint('WebRTC Signaling: Connection failed. Cannot initiate.');
       return;
    }

    // Subscribe to signaling messages from the specific target device
    _mqttClient!.subscribe(
      'wire/p2p/${targetId}_to_$sourceId',
      MqttQos.atLeastOnce,
    );
    
    await _setupWebRTC(P2PRole.initiator);
  }

  Future<void> _setupWebRTC(P2PRole role) async {
    final configuration = {
      'iceServers': _iceServers,
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (candidate) {
      _sendSignalingMessage({
        'type': 'candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      }, role);
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _isConnected = true;
        onConnectionStateChange?.call(ConnectionState.done);
        _startHeartbeat();
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _isConnected = false;
        _heartbeatTimer?.cancel();
        onConnectionStateChange?.call(ConnectionState.none);
      }
    };

    if (role == P2PRole.initiator) {
      RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
        ..id = 1
        ..ordered = true;
      _dataChannel = await _peerConnection!.createDataChannel(
        "wire_dt",
        dataChannelDict,
      );
      _setupDataChannel();

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _sendSignalingMessage({
        'type': 'offer', 
        'sdp': offer.sdp,
        'from': _myId,
      }, role);
    } else {
      _peerConnection!.onDataChannel = (channel) {
        _dataChannel = channel;
        _setupDataChannel();
      };
    }
  }

  void _setupDataChannel() {
    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        _onBinaryReceived.add(message.binary);
        return;
      }
      
      if (message.text == 'ping') {
        sendMessage('pong');
        return;
      }
      onMessageReceived?.call(message.text);
    };
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_isConnected) {
        sendMessage('ping');
      } else {
        timer.cancel();
      }
    });
  }

  void _sendSignalingMessage(Map<String, dynamic> data, P2PRole role) {
    if (_myId == null || _currentTargetId == null) return;
    
    // Always send from Me to Target or Me to Caller
    final topic = 'wire/p2p/${_myId}_to_$_currentTargetId';
    
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(data));
    _mqttClient?.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  Future<void> _handleSignalingMessage(String jsonStr) async {
    try {
      final msg = jsonDecode(jsonStr);
      final type = msg['type'];
      final from = msg['from']?.toString();

      // IMPORTANT: Ignore signaling messages from self to prevent loopback/self-connection
      if (from == _myId) {
        return;
      }

      if (type == 'offer') {
        _currentTargetId = from; 
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(msg['sdp'], 'offer'),
        );
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _sendSignalingMessage({
          'type': 'answer',
          'sdp': answer.sdp,
          'from': _myId,
        }, P2PRole.receiver);
      } else if (type == 'answer') {
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(msg['sdp'], 'answer'),
        );
      } else if (type == 'candidate') {
        final cand = msg['candidate'];
        await _peerConnection!.addCandidate(
          RTCIceCandidate(
            cand['candidate'],
            cand['sdpMid'],
            cand['sdpMLineIndex'],
          ),
        );
      }
    } catch (_) {}
  }

  void sendMessage(String text) {
    if (_isConnected && _dataChannel != null) {
      _dataChannel!.send(RTCDataChannelMessage(text));
    }
  }

  void sendBinary(Uint8List data) {
    if (_isConnected && _dataChannel != null) {
      _dataChannel!.send(RTCDataChannelMessage.fromBinary(data));
    }
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _dataChannel?.close();
    _peerConnection?.close();
    _mqttClient?.disconnect();
    _peerConnection = null;
    _dataChannel = null;
    _isConnected = false;
    debugPrint('WebRTCP2PService: P2P signaling stopped.');
  }
}
