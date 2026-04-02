import 'package:flutter/foundation.dart';

import 'dart:async';
import 'package:flutter/services.dart';

/// Service to manage floating dock on Android
/// Displays a persistent floating overlay with quick access to app features
class FloatingDockService {
  static const platform = MethodChannel('com.example.wire/floating-dock');
  static const eventChannel = EventChannel('com.example.wire/floating-dock-events');

  StreamSubscription? _eventSubscription;
  final List<void Function(FloatingDockEvent)> _listeners = [];

  bool _isVisible = false;
  bool _isExpanded = false;

  bool get isVisible => _isVisible;
  bool get isExpanded => _isExpanded;

  /// Initialize the floating dock service
  Future<void> initialize() async {
    try {
      // Setup event stream for dock interactions
      _eventSubscription = eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is Map) {
            _handleEvent(Map<String, dynamic>.from(event));
          }
        },
        onError: (error) {
          debugPrint('Floating Dock error: $error');
        },
      );

      // Check initial state
      await getStatus();
    } catch (e) {
      debugPrint('Failed to initialize floating dock service: $e');
    }
  }

  /// Show the floating dock
  Future<bool> show() async {
    try {
      final result = await platform.invokeMethod<bool>('show');
      _isVisible = result ?? false;
      _notifyListeners(FloatingDockEvent(
        type: 'dock_shown',
        data: {'visible': _isVisible},
      ));
      return _isVisible;
    } catch (e) {
      debugPrint('Failed to show dock: $e');
      return false;
    }
  }

  /// Hide the floating dock
  Future<bool> hide() async {
    try {
      final result = await platform.invokeMethod<bool>('hide');
      _isVisible = !(result ?? true);
      _notifyListeners(FloatingDockEvent(
        type: 'dock_hidden',
        data: {'visible': _isVisible},
      ));
      return true;
    } catch (e) {
      debugPrint('Failed to hide dock: $e');
      return false;
    }
  }

  /// Toggle dock visibility
  Future<bool> toggle() async {
    return _isVisible ? hide() : show();
  }

  /// Expand or collapse the dock menu
  Future<bool> setExpanded(bool expanded) async {
    try {
      final result = await platform.invokeMethod<bool>(
        'setExpanded',
        {'expanded': expanded},
      );
      _isExpanded = result ?? _isExpanded;
      _notifyListeners(FloatingDockEvent(
        type: 'dock_expanded',
        data: {'expanded': _isExpanded},
      ));
      return _isExpanded;
    } catch (e) {
      debugPrint('Failed to set dock expansion: $e');
      return false;
    }
  }

  /// Update dock position
  Future<bool> setPosition(double x, double y) async {
    try {
      final result = await platform.invokeMethod<bool>(
        'setPosition',
        {'x': x, 'y': y},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to set dock position: $e');
      return false;
    }
  }

  /// Change dock orientation
  Future<bool> setOrientation(String orientation) async {
    try {
      final result = await platform.invokeMethod<bool>(
        'setOrientation',
        {'orientation': orientation},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to set dock orientation: $e');
      return false;
    }
  }

  /// Update dock opacity
  Future<bool> setOpacity(double opacity) async {
    try {
      final result = await platform.invokeMethod<bool>(
        'setOpacity',
        {'opacity': opacity.clamp(0.3, 1.0)},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to set dock opacity: $e');
      return false;
    }
  }

  /// Get current dock status
  Future<void> getStatus() async {
    try {
      final result = await platform.invokeMethod<Map>('getStatus');
      if (result != null) {
        _isVisible = result['visible'] == true;
        _isExpanded = result['expanded'] == true;
      }
    } catch (e) {
      debugPrint('Failed to get dock status: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _eventSubscription?.cancel();
    _listeners.clear();
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'action_tapped':
        _notifyListeners(FloatingDockEvent(
          type: 'action_tapped',
          data: event['data'] ?? {},
        ));
        break;
      case 'position_changed':
        _notifyListeners(FloatingDockEvent(
          type: 'position_changed',
          data: event['data'] ?? {},
        ));
        break;
      case 'dock_expanded':
        _isExpanded = event['expanded'] == true;
        _notifyListeners(FloatingDockEvent(
          type: 'dock_expanded',
          data: {'expanded': _isExpanded},
        ));
        break;
      case 'dock_hidden':
        _isVisible = false;
        _notifyListeners(FloatingDockEvent(
          type: 'dock_hidden',
          data: {'visible': false},
        ));
        break;
    }
  }

  void addListener(void Function(FloatingDockEvent) callback) {
    _listeners.add(callback);
  }

  void removeListener(void Function(FloatingDockEvent) callback) {
    _listeners.remove(callback);
  }

  void _notifyListeners(FloatingDockEvent event) {
    for (final listener in _listeners) {
      listener(event);
    }
  }
}

/// Event emitted by floating dock
class FloatingDockEvent {
  final String type;
  final Map<String, dynamic> data;

  FloatingDockEvent({
    required this.type,
    required this.data,
  });
}

/// Quick action definition for dock buttons
class QuickAction {
  final String id;
  final String label;
  final String icon;
  final String? color;

  QuickAction({
    required this.id,
    required this.label,
    required this.icon,
    this.color,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'icon': icon,
    'color': color,
  };
}
