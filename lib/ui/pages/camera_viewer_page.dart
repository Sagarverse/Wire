import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/screen_mirror_service.dart';

class CameraViewerPage extends StatefulWidget {
  final ScreenMirrorService mirrorService;
  final VoidCallback onFlipCamera;

  const CameraViewerPage({
    super.key,
    required this.mirrorService,
    required this.onFlipCamera,
  });

  @override
  State<CameraViewerPage> createState() => _CameraViewerPageState();
}

class _CameraViewerPageState extends State<CameraViewerPage> {
  RTCVideoRenderer? _renderer;
  bool _isStreaming = false;
  // ** FIX: Track subscriptions to cancel in dispose **
  StreamSubscription<MirrorState>? _stateSub;
  StreamSubscription<RTCVideoRenderer>? _rendererSub;

  @override
  void initState() {
    super.initState();
    // ** FIX: Use localRenderer for sender, remoteRenderer for receiver **
    _renderer = widget.mirrorService.localRenderer ?? widget.mirrorService.remoteRenderer;
    _isStreaming = widget.mirrorService.state == MirrorState.streaming;

    _stateSub = widget.mirrorService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isStreaming = state == MirrorState.streaming;
          if (state == MirrorState.idle) {
            Navigator.of(context).pop();
          }
        });
      }
    });

    _rendererSub = widget.mirrorService.remoteRendererStream.listen((renderer) {
      if (mounted) {
        setState(() {
          _renderer = renderer;
          _isStreaming = true;
        });
      }
    });
  }

  @override
  void dispose() {
    // ** FIX: Cancel subscriptions to prevent memory leaks **
    _stateSub?.cancel();
    _rendererSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Remote Camera',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: Colors.white),
            onPressed: widget.onFlipCamera,
            tooltip: 'Flip Camera',
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            widget.mirrorService.stop();
            Navigator.of(context).pop();
          },
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: _renderer != null && (_isStreaming || widget.mirrorService.state == MirrorState.connecting)
            ? RTCVideoView(
                _renderer!,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                placeholderBuilder: (context) => const Center(
                  child: CircularProgressIndicator(color: Colors.white38),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.mirrorService.state == MirrorState.error
                        ? 'Connection failed'
                        : 'Connecting to camera...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (widget.mirrorService.state == MirrorState.error) ...[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        widget.mirrorService.stop();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Close'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
