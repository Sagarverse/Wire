import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/websocket_service.dart';

class SmsProvider extends ChangeNotifier {
  final WebSocketService _webSocketService;
  final String _deviceId;

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _wsSubscription;

  SmsProvider({
    required WebSocketService webSocketService,
    required String deviceId,
  })  : _webSocketService = webSocketService,
        _deviceId = deviceId {
    _wsSubscription = _webSocketService.messages.listen(_handleIncomingMessage);
    // Use a microtask or a brief delay to avoid notifyListeners during construction
    Future.microtask(() => fetchMessages());
  }

  List<Map<String, dynamic>> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void fetchMessages() {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _webSocketService.send({
      'type': 'sms_fetch_request',
      'from': _deviceId,
    });
  }

  void sendMessage(String number, String message) {
    _webSocketService.send({
      'type': 'sms_send_request',
      'number': number,
      'message': message,
      'from': _deviceId,
    });
  }

  void _handleIncomingMessage(Map<String, dynamic> message) {
    final type = message['type']?.toString();

    if (type == 'sms_list') {
      final data = message['data'] as List<dynamic>?;
      if (data != null) {
        _messages = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _messages.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));
        _isLoading = false;
        _error = null;
        notifyListeners();
      }
    } else if (type == 'sms_error') {
      _error = message['message']?.toString() ?? 'Failed to fetch messages';
      _isLoading = false;
      notifyListeners();
    } else if (type == 'sms_received' || type == 'sms_sent_confirmation') {
      // Refresh list when a new message comes in or a send is confirmed
      fetchMessages();
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }
}
