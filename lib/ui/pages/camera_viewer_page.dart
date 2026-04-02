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

  @override
  void initState() {
    super.initState();
    _renderer = widget.mirrorService.remoteRenderer;
    _isStreaming = widget.mirrorService.state == MirrorState.streaming;

    widget.mirrorService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isStreaming = state == MirrorState.streaming;
          if (state == MirrorState.idle) {
            Navigator.of(context).pop();
          }
        });
      }
    });

    widget.mirrorService.remoteRendererStream.listen((renderer) {
      if (mounted) {
        setState(() {
          _renderer = renderer;
        });
      }
    });
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
        child: _isStreaming && _renderer != null
            ? RTCVideoView(
                _renderer!,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Connecting to camera...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
      ),
    );
  }
}
