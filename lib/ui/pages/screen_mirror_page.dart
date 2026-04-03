import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../services/screen_mirror_service.dart';
import '../widgets/glass_card.dart';

/// Full-screen screen mirror viewer.
/// Works for both sender (Android showing local preview) and
/// receiver (macOS showing remote stream).
class ScreenMirrorPage extends StatefulWidget {
  final ScreenMirrorService mirrorService;
  final RTCVideoRenderer initialRenderer;
  final void Function(String path) onSendFile;
  final VoidCallback onStop;

  const ScreenMirrorPage({
    super.key,
    required this.mirrorService,
    required this.initialRenderer,
    required this.onSendFile,
    required this.onStop,
  });

  @override
  State<ScreenMirrorPage> createState() => _ScreenMirrorPageState();
}

class _ScreenMirrorPageState extends State<ScreenMirrorPage>
    with TickerProviderStateMixin {
  late RTCVideoRenderer _renderer;
  late StreamSubscription _stateSub;
  late StreamSubscription _rendererSub;

  // ** FIX: Use actual current state instead of assuming streaming **
  late MirrorState _state;
  bool _dragActive = false;
  bool _showControls = true;
  Timer? _controlHideTimer;

  // Pointer tracking for touch injection
  final _mirrorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _renderer = widget.initialRenderer;
    _state = widget.mirrorService.state;
    
    _stateSub = widget.mirrorService.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _rendererSub = widget.mirrorService.remoteRendererStream.listen((r) {
      if (mounted) setState(() => _renderer = r);
    });
    _scheduleControlHide();
  }

  @override
  void dispose() {
    _stateSub.cancel();
    _rendererSub.cancel();
    _controlHideTimer?.cancel();
    super.dispose();
  }

  void _scheduleControlHide() {
    _controlHideTimer?.cancel();
    _controlHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onPointerEvent(PointerEvent event, BoxConstraints constraints) {
    final nx = (event.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final ny = (event.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
    String action;
    if (event is PointerDownEvent) {
      action = 'down';
    } else if (event is PointerMoveEvent) {
      action = 'move';
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      action = 'up';
    } else {
      return;
    }
    widget.mirrorService.injectTouch(nx, ny, action);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragActive = true),
        onDragExited: (_) => setState(() => _dragActive = false),
        onDragDone: (details) {
          setState(() => _dragActive = false);
          for (final file in details.files) {
            widget.onSendFile(file.path);
          }
        },
        child: GestureDetector(
          onTap: () {
            setState(() => _showControls = !_showControls);
            if (_showControls) _scheduleControlHide();
          },
          child: Stack(
            children: [
              // ── VIDEO FEED ──────────────────────────────────────────────
              Positioned.fill(
                child: _state == MirrorState.error
                    ? _buildError(scheme)
                    : _state == MirrorState.idle
                    ? _buildConnecting(scheme) // Show connecting if we haven't started yet
                    : LayoutBuilder(
                        builder: (context, constraints) => Listener(
                          key: _mirrorKey,
                          onPointerDown: (e) => _onPointerEvent(e, constraints),
                          onPointerMove: (e) => _onPointerEvent(e, constraints),
                          onPointerUp: (e) => _onPointerEvent(e, constraints),
                          child: RTCVideoView(
                            _renderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitContain,
                            placeholderBuilder: (context) => Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: scheme.onSurface.withValues(alpha: 0.30),
                                    strokeWidth: 2,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _state == MirrorState.connecting
                                        ? 'Establishing connection…'
                                        : 'Loading video feed…',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),

              // ── DRAG OVERLAY ─────────────────────────────────────────────
              if (_dragActive)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary.withValues(alpha: 0.38),
                          scheme.secondary.withValues(alpha: 0.22),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: GlassCard(
                        blur: 24,
                        opacity: 0.92,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 32,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.upload_file,
                              size: 64,
                              color: scheme.tertiary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Drop to send to remote device',
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                shadows: [
                                  Shadow(
                                    color: scheme.primary.withValues(alpha: 0.18),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── CONTROLS OVERLAY ─────────────────────────────────────────
              AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildControls(scheme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(ColorScheme scheme) {
    return Column(
      children: [
        // Top bar
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                onPressed: () {
                  widget.mirrorService.stop();
                  widget.onStop();
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(width: 8),
              const Icon(Icons.cast_connected, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Text(
                'Screen Mirror',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              // Live indicator
              if (_state == MirrorState.streaming)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.white, size: 8),
                      SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'CONNECTING',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Spacer(),
        // Bottom controls
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Drop hint
              GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.upload, color: Colors.white.withValues(alpha: 0.54), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Drop files here to send',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.54), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Stop button
              GestureDetector(
                onTap: () {
                  widget.mirrorService.stop();
                  widget.onStop();
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_circle, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Stop',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnecting(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white38, strokeWidth: 2),
          const SizedBox(height: 20),
          Text(
            'Connecting to remote screen…',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.54), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, color: Colors.white.withValues(alpha: 0.24), size: 64),
          const SizedBox(height: 20),
          Text(
            'Mirror connection lost',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.54), fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            ),
            onPressed: () {
              widget.mirrorService.stop();
              widget.onStop();
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.close),
            label: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
