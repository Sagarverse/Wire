import 'dart:async';

class HandoffService {
  final _handoffController = StreamController<String>.broadcast();
  Stream<String> get onHandoffReceived => _handoffController.stream;

  void handleIncomingHandoff(Map<String, dynamic> message) {
    if (message['type'] == 'handoff' && message['url'] != null) {
      _handoffController.add(message['url'] as String);
    }
  }

  Map<String, dynamic> createHandoffMessage(String url, String fromDeviceId) {
    return {
      'type': 'handoff',
      'url': url,
      'from': fromDeviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  void dispose() {
    _handoffController.close();
  }
}
