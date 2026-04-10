import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart' show ConnectionState;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

enum P2PRole { initiator, receiver }

class WebRTCP2PService {
  final String _broker = 'test.mosquitto.org';
  final int _port = 1883;
  late MqttServerClient _mqttClient;

  // WebRTC
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final String _clientId = const Uuid().v4();

  // Callbacks
  Function(String text)? onMessageReceived;
  Function(ConnectionState state)? onConnectionStateChange;

  bool _isConnected = false;
  String? _myId;
  String? _currentTargetId;
  Timer? _heartbeatTimer;

  Future<void> initialize() async {
    _mqttClient = MqttServerClient.withPort(_broker, _clientId, _port);
    _mqttClient.logging(on: false);
    _mqttClient.keepAlivePeriod = 20;
    _mqttClient.onDisconnected = () {
      // Handle MQTT disconnection internally
    };
    final connMess = MqttConnectMessage()
        .withClientIdentifier(_clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _mqttClient.connectionMessage = connMess;

    try {
      await _mqttClient.connect();
    } catch (e) {
      _mqttClient.disconnect();
      return;
    }

    _mqttClient.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      final recMess = c![0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      _handleSignalingMessage(payload);
    });
  }

  Future<void> startListening(String myId) async {
    _myId = myId;
    // Listen for offers directed to me
    _mqttClient.subscribe(
      'wire/p2p/+_to_$myId',
      MqttQos.atLeastOnce,
    );
  }

  Future<void> initiateConnection(String sourceId, String targetId) async {
    _myId = sourceId;
    _currentTargetId = targetId;
    
    // Subscribe to answers from the target
    _mqttClient.subscribe(
      'wire/p2p/${targetId}_to_$sourceId',
      MqttQos.atLeastOnce,
    );
    
    await _setupWebRTC(P2PRole.initiator);
  }

  Future<void> _setupWebRTC(P2PRole role) async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
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
    _mqttClient.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  Future<void> _handleSignalingMessage(String jsonStr) async {
    try {
      final msg = jsonDecode(jsonStr);
      final type = msg['type'];

      if (type == 'offer') {
        _currentTargetId = msg['from']; 
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

  void closeRoom() {
    _heartbeatTimer?.cancel();
    _dataChannel?.close();
    _peerConnection?.close();
    _peerConnection = null;
    _dataChannel = null;
    _isConnected = false;
  }
}
