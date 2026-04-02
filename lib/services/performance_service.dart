import 'dart:async';

/// Service for optimizing app performance
/// Manages timers, streams, and resource cleanup
class PerformanceService {
  static final PerformanceService _instance = PerformanceService._internal();

  factory PerformanceService() {
    return _instance;
  }

  PerformanceService._internal();

  final List<Timer> _timers = [];
  final List<StreamSubscription> _subscriptions = [];
  final Map<String, int> _timerCounts = {};

  /// Register a timer for automatic cleanup
  Timer createTimer(Duration duration, void Function() callback) {
    final timer = Timer(duration, callback);
    _timers.add(timer);
    _updateTimerCount('single', 1);
    return timer;
  }

  /// Register a periodic timer for automatic cleanup
  Timer createPeriodicTimer(Duration duration, void Function(Timer) callback) {
    final timer = Timer.periodic(duration, callback);
    _timers.add(timer);
    _updateTimerCount('periodic', 1);
    return timer;
  }

  /// Register a stream subscription for automatic cleanup
  StreamSubscription registerSubscription<T>(StreamSubscription<T> subscription) {
    _subscriptions.add(subscription);
    return subscription;
  }

  /// Cancel all registered timers and subscriptions
  void cleanup() {
    for (final timer in _timers) {
      if (timer.isActive) {
        timer.cancel();
      }
    }
    _timers.clear();

    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    _timerCounts.clear();
  }

  void _updateTimerCount(String type, int count) {
    _timerCounts[type] = (_timerCounts[type] ?? 0) + count;
  }

  /// Get diagnostic info about managed resources
  Map<String, dynamic> getMetrics() {
    return {
      'activeTimers': _timers.length,
      'activeSubscriptions': _subscriptions.length,
      'timerCounts': _timerCounts,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}

/// Lazy-load helper for managing initialization
class LazyLoader<T> {
  T? _value;
  final Future<T> Function() _initializer;
  bool _isLoading = false;
  Future<T>? _initFuture;

  LazyLoader(this._initializer);

  Future<T> get() async {
    if (_value != null) return _value!;
    if (_isLoading) return _initFuture!;

    _isLoading = true;
    _initFuture = _initializer().then((value) {
      _value = value;
      _isLoading = false;
      return value;
    });

    return _initFuture!;
  }

  bool get isLoaded => _value != null;
  T? get valueIfLoaded => _value;
}
