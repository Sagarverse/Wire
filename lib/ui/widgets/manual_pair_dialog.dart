import 'package:flutter/material.dart';
import 'glass_card.dart';
import '../../services/discovery_service.dart';

class ManualPairDialog extends StatefulWidget {
  final Function(DiscoveryPeerInfo) onPair;

  const ManualPairDialog({super.key, required this.onPair});

  @override
  State<ManualPairDialog> createState() => _ManualPairDialogState();
}

class _ManualPairDialogState extends State<ManualPairDialog> {
  final _ipController = TextEditingController();
  final _nameController = TextEditingController();
  final _portController = TextEditingController(text: '5757');
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassCard(
        borderRadius: BorderRadius.circular(28),
        padding: const EdgeInsets.all(28),
        accent: scheme.primary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lan_rounded, color: scheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Manual Pairing',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                  'Enter the IP address shown on your other device.',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                ),
            const SizedBox(height: 24),
            _buildField(
              controller: _ipController,
              label: 'Device IP Address',
              hint: 'e.g. 192.168.1.5',
              icon: Icons.alternate_email_rounded,
              scheme: scheme,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _nameController,
              label: 'Device Name (Optional)',
              hint: 'e.g. Living Room TV',
              icon: Icons.label_important_outline_rounded,
              scheme: scheme,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _portController,
              label: 'Port',
              hint: '5757',
              icon: Icons.numbers_rounded,
              scheme: scheme,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handlePair,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required ColorScheme scheme,
    bool autofocus = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.primary.withValues(alpha: 0.7), letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            filled: true,
            fillColor: scheme.onSurface.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _handlePair() async {
    if (_ipController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);
    
    try {
      final ip = _ipController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 5757;
      final name = _nameController.text.trim().isEmpty ? 'Manual Device' : _nameController.text.trim();
      
      final peer = DiscoveryPeerInfo(
        address: ip,
        deviceId: 'manual_${DateTime.now().millisecondsSinceEpoch}', // Temporary ID till handshake
        deviceName: name,
        wsPort: port,
        filePort: port + 1,
      );

      widget.onPair(peer);
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid IP address: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
