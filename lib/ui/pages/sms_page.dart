import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/websocket_service.dart';

class SmsPage extends StatefulWidget {
  final WebSocketService webSocketService;
  final String deviceId;

  const SmsPage({
    super.key,
    required this.webSocketService,
    required this.deviceId,
  });

  @override
  State<SmsPage> createState() => _SmsPageState();
}

class _SmsPageState extends State<SmsPage> {
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _smsList = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _wsSub = widget.webSocketService.messages.listen(_handleMessage);
    _fetchSms();
  }

  @override
  void dispose() {
    _numberController.dispose();
    _messageController.dispose();
    _wsSub?.cancel();
    super.dispose();
  }

  void _fetchSms() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    widget.webSocketService.send({
      'type': 'sms_fetch_request',
      'from': widget.deviceId,
    });
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (!mounted) return;
    final type = message['type']?.toString() ?? '';

    if (type == 'sms_list') {
      final data = message['data'] as List<dynamic>?;
      if (data != null) {
        setState(() {
          _smsList = data
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _isLoading = false;
        });
      }
    } else if (type == 'sms_error') {
      setState(() {
        _error = message['message']?.toString() ?? 'Unknown error fetching SMS';
        _isLoading = false;
      });
    }
  }

  void _sendSms() {
    final number = _numberController.text.trim();
    final message = _messageController.text.trim();
    if (number.isEmpty || message.isEmpty) return;

    widget.webSocketService.send({
      'type': 'sms_send_request',
      'number': number,
      'message': message,
      'from': widget.deviceId,
    });

    _messageController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sending SMS...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSms,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: scheme.error.withValues(alpha: 0.15),
              width: double.infinity,
              child: Text(
                _error!,
                style: TextStyle(color: scheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _smsList.isEmpty
                ? Center(
                    child: Text(
                      'No recent messages found.',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.54),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _smsList.length,
                    itemBuilder: (context, index) {
                      final sms = _smsList[index];
                      final isSent = sms['isSent'] == true;
                      final senderName =
                          sms['senderName']?.toString() ??
                          sms['address']?.toString() ??
                          'Unknown';
                      final body = sms['body']?.toString() ?? '';
                      final date = DateTime.fromMillisecondsSinceEpoch(
                        sms['date'] as int? ?? 0,
                      );

                      return Align(
                        alignment: isSent
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSent
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16).copyWith(
                              bottomRight: isSent
                                  ? Radius.zero
                                  : const Radius.circular(16),
                              bottomLeft: !isSent
                                  ? Radius.zero
                                  : const Radius.circular(16),
                            ),
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isSent) ...[
                                Text(
                                  senderName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                body,
                                style: TextStyle(
                                  color: isSent
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: (isSent ? scheme.onPrimary : scheme.onSurface)
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                top: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
              ),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _numberController,
                  decoration: const InputDecoration(
                    hintText: 'Recipient Phone Number...',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton(
                      mini: true,
                      onPressed: _sendSms,
                      child: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
