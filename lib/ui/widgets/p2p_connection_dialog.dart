import 'package:flutter/material.dart';
import '../../providers/app_state.dart';
import 'package:provider/provider.dart';
import 'glass_card.dart';
import 'package:flutter/services.dart';

class P2PConnectionDialog extends StatefulWidget {
  const P2PConnectionDialog({super.key});

  @override
  State<P2PConnectionDialog> createState() => _P2PConnectionDialogState();
}

class _P2PConnectionDialogState extends State<P2PConnectionDialog> with SingleTickerProviderStateMixin {
  bool _isHosting = false;
  String? _roomCode;
  final TextEditingController _codeController = TextEditingController();
  bool _connecting = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startHost() async {
    setState(() => _connecting = true);
    final app = context.read<AppState>();
    final code = (100000 + DateTime.now().millisecondsSinceEpoch % 899999).toString();
    await app.webrtcP2PService.startListening(code);
    
    app.webrtcP2PService.onConnectionStateChange = (state) {
      if (state == ConnectionState.done && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('P2P Connected anywhere!')),
        );
      }
    };

    if (mounted) {
      setState(() {
        _isHosting = true;
        _roomCode = code;
        _connecting = false;
      });
    }
  }

  Future<void> _joinHost() async {
    if (_codeController.text.length != 6) return;
    setState(() => _connecting = true);
    final app = context.read<AppState>();
    
    app.webrtcP2PService.onConnectionStateChange = (state) {
      if (state == ConnectionState.done && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('P2P Connected anywhere!')),
        );
      }
    };

    await app.webrtcP2PService.initiateConnection(app.deviceId, _codeController.text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassCard(
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.all(24),
        accent: scheme.onSurface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isHosting && _roomCode == null) ...[
              Icon(Icons.public, size: 48, color: scheme.onSurface),
              const SizedBox(height: 16),
              const Text(
                'P2P ANYWHERE',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 8),
              Text(
                'Connect over the internet securely.',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: 'Enter 6-digit code',
                  counterText: '',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontSize: 24, letterSpacing: 4, fontWeight: FontWeight.bold),
                onChanged: (v) {
                  if (v.length == 6) _joinHost();
                },
              ),
              const SizedBox(height: 16),
              if (_connecting) const CircularProgressIndicator()
              else Column(
                children: [
                  ElevatedButton(
                    onPressed: _joinHost,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.onSurface,
                      foregroundColor: scheme.surface,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('JOIN'),
                  ),
                  TextButton(
                    onPressed: _startHost,
                    child: const Text('Generate Code (Host)'),
                  )
                ],
              )
            ] else ...[
              Icon(Icons.satellite_alt_rounded, size: 48, color: scheme.onSurface),
              const SizedBox(height: 24),
              const Text('YOUR CODE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _roomCode ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied!')));
                },
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.05 + (0.05 * _pulseController.value)),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.1 * _pulseController.value)),
                      ),
                      child: Text(
                        _roomCode ?? '...',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              const Text('Waiting for peer to connect...'),
              const SizedBox(height: 12),
              const CircularProgressIndicator(),
            ]
          ],
        ),
      ),
    );
  }
}
