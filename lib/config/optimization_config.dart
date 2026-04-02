/// App-wide optimization configuration for storage, power, and performance
class OptimizationConfig {
  // ============ Storage Optimization ============
  
  /// Maximum clipboard history items (prevents memory bloat)
  /// Increased from 40 to 200 for better history while keeping memory <1MB
  static const int maxClipboardItems = 200;

  /// Maximum transfer items (prevents memory bloat)
  /// Increased from 40 to 1000 for richer history
  static const int maxTransferItems = 1000;

  /// Maximum notification history items
  static const int maxNotificationItems = 100;

  /// Image cache size in MB (reduced for memory efficiency)
  /// Reduced from 50 MB to 20 MB - still plenty for UI images
  static const int imageCacheSizeInMb = 20;

  // ============ Network Optimization ============
  
  /// Battery status check interval (in minutes)
  /// Increased from 5 to 10 minutes - less frequent polling = lower battery
  static const int batteryCheckIntervalMinutes = 10;

  /// Reconnection attempt interval (in seconds)
  static const int reconnectIntervalSeconds = 10;

  /// WebSocket heartbeat interval when idle (in seconds)
  /// Increased from 30 to 60 seconds - less frequent = lower battery
  static const int heartbeatIntervalSeconds = 60;

  /// WebSocket aggressive heartbeat interval during transfers (in seconds)
  /// Reduced from 3 to 2 seconds - faster for stable transfers
  static const int aggressiveHeartbeatSeconds = 2;

  /// Connection timeout (in seconds)
  static const int connectionTimeoutSeconds = 30;

  /// Idle timeout for sockets (in seconds)
  static const int idleTimeoutSeconds = 90;

  /// Rate limit for event emissions (in milliseconds)
  static const int eventRateLimitMs = 100;

  /// File transfer chunk size in bytes (64 KB optimal for WiFi)
  static const int fileTransferChunkSize = 65536;

  /// Maximum concurrent transfers (1 = sequential, prevents memory spike)
  static const int maxConcurrentTransfers = 1;

  // ============ Performance Optimization ============
  
  /// Cache expiry duration (in minutes)
  static const int cacheExpiryMinutes = 5;

  /// Minimum request interval for network operations (in milliseconds)
  static const int minRequestIntervalMs = 100;

  /// Debounce duration for input changes (in milliseconds)
  static const int debounceMs = 300;

  /// Progress update debounce (in milliseconds)
  /// Limits UI rebuilds during transfer progress
  static const int progressUpdateDebounceMs = 100;

  /// Number of items to show before pagination
  static const int pageSize = 20;

  /// Memory cleanup threshold in MB
  /// Triggers garbage collection when exceeded
  static const int memoryCleanupThresholdMb = 300;

  /// Idle timeout before low-power mode (in seconds)
  /// Background sync paused after this duration of inactivity
  static const int idleTimeoutForLowPowerSec = 60;

  // ============ Animation Optimization ============
  
  /// Enable smooth animations on all devices
  static const bool enableAnimations = true;

  /// Animation duration for short transitions (ms)
  static const int animationDurationShortMs = 200;

  /// Animation duration for standard transitions (ms)
  static const int animationDurationStandardMs = 350;

  /// Animation duration for long transitions (ms)
  static const int animationDurationLongMs = 500;

  // ============ Build Optimization ============
  
  /// Enable code shrinking for release builds (-20-30% size)
  static const bool enableCodeShrinking = true;

  /// Enable asset optimization (-10-15% size)
  static const bool enableAssetOptimization = true;

  /// Enable Dart tree-shaking (removes unused code)
  static const bool enableTreeShaking = true;

  /// Enable lazy loading of services (faster startup)
  static const bool enableLazyLoadingServices = true;

  // ============ Memory Management ============
  
  /// Enable memory profiling (debug only)
  static const bool enableMemoryProfiling = false;

  /// Enable performance logging
  static const bool enablePerformanceLogging = false;

  /// Enable network request logging
  static const bool enableNetworkLogging = false;
}
