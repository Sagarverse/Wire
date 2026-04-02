import 'package:flutter/material.dart';

import '../../services/websocket_service.dart';

class TrackpadPage extends StatefulWidget {
  final WebSocketService webSocketService;
  final String deviceId;

  const TrackpadPage({
    super.key,
    required this.webSocketService,
    required this.deviceId,
  });

  @override
  State<TrackpadPage> createState() => _TrackpadPageState();
}

class _TrackpadPageState extends State<TrackpadPage> {
  final FocusNode _keyboardFocusNode = FocusNode();
  final TextEditingController _keyboardController = TextEditingController();

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _keyboardController.dispose();
    super.dispose();
  }

  void _onKeyboardChanged(String value) {
    if (value.isNotEmpty) {
      widget.webSocketService.send({
        'type': 'inputText',
        'from': widget.deviceId,
        'text': value,
      });
      _keyboardController.clear();
    }
  }

  void _sendMouseEvent(double dx, double dy, String action) {
    widget.webSocketService.send({
      'type': 'mouse_event',
      'from': widget.deviceId,
      'dx': dx,
      'dy': dy,
      'action': action,
    });
  }

  void _sendKeyEvent(int keyCode) {
    widget.webSocketService.send({
      'type': 'keyboard_event',
      'from': widget.deviceId,
      'keyCode': keyCode,
      'action': 'press',
    });
  }

  Widget _buildSpecialKey(ColorScheme scheme, String label, int keyCode, {double width = 50}) {
    return Container(
      width: width,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          foregroundColor: scheme.onSurface,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => _sendKeyEvent(keyCode),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.primary.withValues(alpha: 0.5),
        title: Text(
          'Remote Trackpad',
          style: TextStyle(color: scheme.onSurface),
        ),
        leading: IconButton(
          icon: Icon(Icons.close, color: scheme.onSurface.withValues(alpha: 0.7)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.keyboard, color: scheme.onSurface.withValues(alpha: 0.7)),
            onPressed: () {
              if (_keyboardFocusNode.hasFocus) {
                _keyboardFocusNode.unfocus();
              } else {
                FocusScope.of(context).requestFocus(_keyboardFocusNode);
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Opacity(
            opacity: 0.0,
            child: SizedBox(
              width: 1,
              height: 1,
              child: TextField(
                focusNode: _keyboardFocusNode,
                controller: _keyboardController,
                onChanged: _onKeyboardChanged,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.text,
              ),
            ),
          ),
          Column(
            children: [
              // Keyboard Toolbar
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: scheme.onSurface.withValues(alpha: 0.05),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      _buildSpecialKey(scheme, 'ESC', 53),
                      _buildSpecialKey(scheme, '⇥ TAB', 48, width: 60),
                      _buildSpecialKey(scheme, '⌘ CMD', 55, width: 60),
                      _buildSpecialKey(scheme, '⌥ OPT', 58, width: 60),
                      _buildSpecialKey(scheme, '⌃ CTRL', 59, width: 60),
                      _buildSpecialKey(scheme, '⇧ SHFT', 56, width: 60),
                      _buildSpecialKey(scheme, 'Space', 49, width: 80),
                      _buildSpecialKey(scheme, '⌫ DEL', 51, width: 60),
                      _buildSpecialKey(scheme, '⏎ ENT', 36, width: 60),
                      _buildSpecialKey(scheme, '↑', 126, width: 40),
                      _buildSpecialKey(scheme, '↓', 125, width: 40),
                      _buildSpecialKey(scheme, '←', 123, width: 40),
                      _buildSpecialKey(scheme, '→', 124, width: 40),
                    ],
                  ),
                ),
              ),

              // Trackpad Area
              Expanded(
                child: GestureDetector(
                  onPanUpdate: (details) {
                    // Send relative movement (delta)
                    _sendMouseEvent(details.delta.dx, details.delta.dy, 'move');
                  },
                  onTapDown: (_) => _sendMouseEvent(0, 0, 'left_down'),
                  onTapUp: (_) => _sendMouseEvent(0, 0, 'left_up'),
                  onSecondaryTapDown: (_) =>
                      _sendMouseEvent(0, 0, 'right_down'),
                  onSecondaryTapUp: (_) => _sendMouseEvent(0, 0, 'right_up'),
                  child: Container(
                    color: scheme.onSurface.withValues(alpha: 0.02),
                    width: double.infinity,
                    height: double.infinity,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.touch_app,
                            size: 80,
                            color: scheme.onSurface.withValues(alpha: 0.24),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Slide finger to move mouse\nTap to click',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.4),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
