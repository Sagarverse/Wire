import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRtcService {
  WebRtcService({required this.onSignal, this.onRemoteStream, this.onStateChanged});

  final void Function(String type, Map<String, dynamic> payload) onSignal;
  final void Function(MediaStream stream)? onRemoteStream;
  final void Function(String state)? onStateChanged;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCSessionDescription? _pendingOffer;

  bool get inCall => _pc != null;
  bool get hasPendingOffer => _pendingOffer != null;

  Future<void> startCall() async {
    await _ensurePeerConnection();
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    onSignal('webrtc_offer', {'sdp': offer.sdp, 'sdpType': offer.type});
  }

  void storeOffer(Map<String, dynamic> data) {
    final sdp = data['sdp']?.toString() ?? '';
    final type = data['sdpType']?.toString() ?? 'offer';
    if (sdp.isNotEmpty) {
      _pendingOffer = RTCSessionDescription(sdp, type);
    }
  }

  Future<void> acceptCall() async {
    if (_pendingOffer == null) return;
    await _ensurePeerConnection();
    await _pc!.setRemoteDescription(_pendingOffer!);
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    onSignal('webrtc_answer', {'sdp': answer.sdp, 'sdpType': answer.type});
    _pendingOffer = null;
  }

  Future<void> declineCall() async {
    _pendingOffer = null;
    onSignal('webrtc_hangup', {});
  }

  Future<void> handleAnswer(Map<String, dynamic> data) async {
    if (_pc == null) return;
    final sdp = data['sdp']?.toString() ?? '';
    final type = data['sdpType']?.toString() ?? 'answer';
    if (sdp.isEmpty) return;
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
  }

  Future<void> handleIce(Map<String, dynamic> data) async {
    if (_pc == null) return;
    final candidate = data['candidate']?.toString();
    final sdpMid = data['sdpMid']?.toString();
    final sdpMLineIndex = data['sdpMLineIndex'];
    if (candidate == null || candidate.isEmpty) return;
    final index = sdpMLineIndex is int ? sdpMLineIndex : (sdpMLineIndex is num ? sdpMLineIndex.toInt() : null);
    final ice = RTCIceCandidate(candidate, sdpMid, index);
    await _pc!.addCandidate(ice);
  }

  Future<void> hangup({bool notify = true}) async {
    if (notify) {
      onSignal('webrtc_hangup', {});
    }
    await _pc?.close();
    _pc = null;
    await _localStream?.dispose();
    _localStream = null;
    _remoteStream?.dispose();
    _remoteStream = null;
    _pendingOffer = null;
    onStateChanged?.call('closed');
  }

  Future<void> setMute(bool mute) async {
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = !mute;
    }
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    final constraints = {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };
    _pc = await createPeerConnection(config, constraints);
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        onSignal('webrtc_ice', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        onRemoteStream?.call(_remoteStream!);
      }
    };
    _pc!.onConnectionState = (state) => onStateChanged?.call(state.toString());

    _localStream ??= await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
  }
}
