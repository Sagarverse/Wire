import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/sms_provider.dart';
import '../widgets/glass_card.dart';
import '../../widgets/liquid_background.dart';

class SmsPage extends StatefulWidget {
  final EdgeInsets? padding;
  const SmsPage({super.key, this.padding});

  @override
  State<SmsPage> createState() => _SmsPageState();
}

class _SmsPageState extends State<SmsPage> {
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _sendSms(SmsProvider provider) {
    final number = _numberController.text.trim();
    final message = _messageController.text.trim();
    if (number.isEmpty || message.isEmpty) return;

    provider.sendMessage(number, message);
    _messageController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sending SMS...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          Consumer<SmsProvider>(
            builder: (context, provider, _) => IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: provider.fetchMessages,
              tooltip: 'Refresh',
            ),
          ),
        ],
      ),
      body: LiquidBackground(
        child: Column(
          children: [
            Expanded(
              child: Consumer<SmsProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading && provider.messages.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (provider.error != null && provider.messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
                          const SizedBox(height: 16),
                          Text(provider.error!, style: TextStyle(color: scheme.error)),
                          TextButton(
                            onPressed: provider.fetchMessages,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (provider.messages.isEmpty) {
                    return Center(
                      child: Text(
                        'No recent messages.',
                        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(20),
                    reverse: false, // We'll sort by date desc but display top-down or bottom-up? 
                    // Usually chat is reverse true, but provider already sorted.
                    itemCount: provider.messages.length,
                    itemBuilder: (context, index) {
                      final sms = provider.messages[index];
                      final isSent = sms['isSent'] == true;
                      final senderName = sms['senderName']?.toString() ??
                          sms['address']?.toString() ??
                          'Unknown';
                      final body = sms['body']?.toString() ?? '';
                      final date = DateTime.fromMillisecondsSinceEpoch(
                        sms['date'] as int? ?? 0,
                      );

                      return Align(
                        alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                            ),
                            child: GlassCard(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              borderRadius: BorderRadius.circular(20).copyWith(
                                bottomRight: isSent ? Radius.zero : const Radius.circular(20),
                                bottomLeft: !isSent ? Radius.zero : const Radius.circular(20),
                              ),
                              accent: isSent ? scheme.primary : null,
                              opacity: isSent ? 0.15 : 0.08,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isSent)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        senderName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    body,
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurface.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _buildInputArea(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      child: GlassCard(
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          children: [
            TextField(
              controller: _numberController,
              decoration: InputDecoration(
                hintText: 'Recipient Number...',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.3), fontSize: 13),
              ),
              style: const TextStyle(fontSize: 14),
              keyboardType: TextInputType.phone,
            ),
            Divider(height: 1, color: scheme.onSurface.withValues(alpha: 0.1)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.3), fontSize: 14),
                    ),
                    maxLines: null,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                Consumer<SmsProvider>(
                  builder: (context, provider, _) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton.filled(
                      onPressed: () => _sendSms(provider),
                      icon: const Icon(Icons.send_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
