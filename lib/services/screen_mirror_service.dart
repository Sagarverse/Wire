import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

enum MirrorState { idle, connecting, streaming, error }

/// Manages a WebRTC peer connection for screen mirroring.
/// Signaling uses the caller-provided [onSendSignal] callback
/// which delivers messages over the existing WebSocket.
class ScreenMirrorService {
  ScreenMirrorService({required this.onSendSignal, required this.deviceId});

  final void Function(Map<String, dynamic>) onSendSignal;
  final String deviceId;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  MirrorState _state = MirrorState.idle;
  final _stateController = StreamController<MirrorState>.broadcast();
  final _remoteRendererController =
      StreamController<RTCVideoRenderer>.broadcast();

  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _remoteCandidatesBuffer = [];

  Stream<MirrorState> get stateStream => _stateController.stream;
  Stream<RTCVideoRenderer> get remoteRendererStream =>
      _remoteRendererController.stream;
  MirrorState get state => _state;
  RTCVideoRenderer? get remoteRenderer => _remoteRenderer;

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> _resetForNewSession() async {
    _remoteDescriptionSet = false;
    _remoteCandidatesBuffer.clear();

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      await _localRenderer?.dispose();
    } catch (_) {}
    _localRenderer = null;

    try {
      await _remoteRenderer?.dispose();
    } catch (_) {}
    _remoteRenderer = null;

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
  }

  /// Called by the SENDER (Android) to start streaming its screen.
  Future<RTCVideoRenderer> startSending() async {
    await _resetForNewSession();
    _setState(MirrorState.connecting);

    _localRenderer = RTCVideoRenderer();
    await _localRenderer!.initialize();

    _localStream = await navigator.mediaDevices.getDisplayMedia({
      'video': {
        'mandatory': {
          'minWidth': '1280',
          'maxWidth': '1920',
          'minHeight': '720',
          'maxHeight': '1080',
          'frameRate': '30',
        },
      },
      'audio': false,
    });

    _localRenderer!.srcObject = _localStream;

    await _createPeerConnection();
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    final offer = await _pc!.createOffer({'offerToReceiveVideo': 1});
    await _pc!.setLocalDescription(offer);
    onSendSignal({'type': 'screen_offer', 'sdp': offer.sdp, 'from': deviceId});

    _setState(MirrorState.streaming);
    return _localRenderer!;
  }

  /// Called by the SENDER (Android) to start streaming its camera.
  Future<RTCVideoRenderer> startSendingCamera() async {
    await _resetForNewSession();
    _setState(MirrorState.connecting);

    _localRenderer = RTCVideoRenderer();
    await _localRenderer!.initialize();

    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': {
        'mandatory': {
          'minWidth': '1280',
          'maxWidth': '1920',
          'minHeight': '720',
          'maxHeight': '1080',
          'frameRate': '30',
        },
        'facingMode': 'user',
      },
      'audio': false,
    });

    _localRenderer!.srcObject = _localStream;

    await _createPeerConnection(isCamera: true);
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    final offer = await _pc!.createOffer({'offerToReceiveVideo': 1});
    await _pc!.setLocalDescription(offer);
    onSendSignal({'type': 'camera_offer', 'sdp': offer.sdp, 'from': deviceId});

    _setState(MirrorState.streaming);
    return _localRenderer!;
  }

  Future<void> switchCamera() async {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks().first);
    }
  }

  /// Called by the RECEIVER (macOS) to accept an incoming offer.
  Future<RTCVideoRenderer> receiveOffer(
    String sdp, {
    bool isCamera = false,
  }) async {
    await _resetForNewSession();
    _setState(MirrorState.connecting);

    _remoteRenderer = RTCVideoRenderer();
    await _remoteRenderer!.initialize();

    await _createPeerConnection(isCamera: isCamera);

    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    _remoteDescriptionSet = true;
    _drainCandidates();

    final answer = await _pc!.createAnswer({});
    await _pc!.setLocalDescription(answer);
    onSendSignal({
      'type': isCamera ? 'camera_answer' : 'screen_answer',
      'sdp': answer.sdp,
      'from': deviceId,
    });

    return _remoteRenderer!;
  }

  /// Called on sender when it receives the answer.
  Future<void> receiveAnswer(String sdp) async {
    await _pc?.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    _remoteDescriptionSet = true;
    _drainCandidates();
  }

  /// Handle incoming ICE candidates from the remote peer.
  Future<void> addIceCandidate(Map<String, dynamic> data) async {
    final candidate = RTCIceCandidate(
      data['candidate']?.toString() ?? '',
      data['sdpMid']?.toString() ?? '',
      int.tryParse(data['sdpMLineIndex']?.toString() ?? '0') ?? 0,
    );
    if (_remoteDescriptionSet && _pc != null) {
      await _pc!.addCandidate(candidate);
    } else {
      _remoteCandidatesBuffer.add(candidate);
    }
  }

  Future<void> _drainCandidates() async {
    if (_pc == null) return;
    for (final candidate in _remoteCandidatesBuffer) {
      await _pc!.addCandidate(candidate);
    }
    _remoteCandidatesBuffer.clear();
  }

  /// Inject a touch event on the sender side.
  /// [nx] and [ny] are normalized 0.0–1.0 coordinates.
  /// [action] is 'down', 'move', or 'up'.
  void injectTouch(double nx, double ny, String action) {
    onSendSignal({
      'type': 'screen_touch',
      'nx': nx,
      'ny': ny,
      'action': action,
      'from': deviceId,
    });
  }

  Future<void> stop() async {
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;

    await _localRenderer?.dispose();
    _localRenderer = null;

    await _remoteRenderer?.dispose();
    _remoteRenderer = null;

    await _pc?.close();
    _pc = null;

    _setState(MirrorState.idle);
    onSendSignal({'type': 'screen_stop', 'from': deviceId});
  }

  void dispose() {
    stop();
    _stateController.close();
    _remoteRendererController.close();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _createPeerConnection({bool isCamera = false}) async {
    _pc = await createPeerConnection(_iceServers);

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        onSendSignal({
          'type': isCamera ? 'camera_ice' : 'screen_ice',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'from': deviceId,
        });
      }
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setState(MirrorState.error);
      }
    };

    _pc!.onTrack = (event) {
      if (_remoteRenderer != null && event.streams.isNotEmpty) {
        _remoteRenderer!.srcObject = event.streams.first;
        _setState(MirrorState.streaming);
        _remoteRendererController.add(_remoteRenderer!);
      }
    };
  }

  void _setState(MirrorState s) {
    _state = s;
    _stateController.add(s);
  }
}
