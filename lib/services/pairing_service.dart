import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PairedDevice {
  final String deviceId;
  final String name;
  final String lastIp;
  final bool isTrusted;
  final String osType;
  final int lastSeenAt;
  final int? batteryLevel;
  final bool? isCharging;
  final int filePort;

  PairedDevice({
    required this.deviceId,
    required this.name,
    required this.lastIp,
    required this.isTrusted,
    required this.osType,
    required this.lastSeenAt,
    this.batteryLevel,
    this.isCharging,
    this.filePort = 5758,
  });

  Map<String, dynamic> toJson() => {
        'id': deviceId,
        'name': name,
        'ip': lastIp,
        'trusted': isTrusted,
        'os': osType,
        'battery': batteryLevel,
        'charging': isCharging,
        'filePort': filePort,
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        deviceId: json['id'] as String,
        name: json['name'] as String? ?? 'Unknown Device',
        lastIp: json['ip'] as String? ?? '',
        isTrusted: json['trusted'] as bool? ?? false,
        osType: json['os'] as String? ?? 'unknown',
        lastSeenAt: json['seen'] as int? ?? 0,
        batteryLevel: json['battery'] as int?,
        isCharging: json['charging'] as bool?,
        filePort: json['filePort'] as int? ?? 5758,
      );

  PairedDevice copyWith({
    String? name,
    String? lastIp,
    bool? isTrusted,
    String? osType,
    int? lastSeenAt,
    int? batteryLevel,
    bool? isCharging,
    int? filePort,
  }) {
    return PairedDevice(
      deviceId: deviceId,
      name: name ?? this.name,
      lastIp: lastIp ?? this.lastIp,
      isTrusted: isTrusted ?? this.isTrusted,
      osType: osType ?? this.osType,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      filePort: filePort ?? this.filePort,
    );
  }
}

class PairingService {
  static const String _key = 'paired_devices';
  static const String _activeKey = 'active_device_id';
  List<PairedDevice> _devices = [];
  String? _activeDeviceId;

  List<PairedDevice> get devices => List.unmodifiable(_devices);
  
  PairedDevice? get activeDevice {
    if (_activeDeviceId == null) return null;
    try {
      return _devices.firstWhere((d) => d.deviceId == _activeDeviceId);
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_key) ?? [];
    
    _devices = jsonList.map((str) {
      try {
        return PairedDevice.fromJson(jsonDecode(str));
      } catch (_) {
        return null;
      }
    }).whereType<PairedDevice>().toList();

    _activeDeviceId = prefs.getString(_activeKey);
    // Auto active fallback if only 1 trusted device exists
    if (_activeDeviceId == null && _devices.length == 1 && _devices.first.isTrusted) {
      _activeDeviceId = _devices.first.deviceId;
      await prefs.setString(_activeKey, _activeDeviceId!);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _devices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_key, jsonList);
  }

  Future<void> addOrUpdateDevice(PairedDevice device) async {
    final idx = _devices.indexWhere((d) => d.deviceId == device.deviceId);
    if (idx >= 0) {
      // Keep existing trust level unless explicitly updated
      final existing = _devices[idx];
      _devices[idx] = device.copyWith(
        isTrusted: device.isTrusted || existing.isTrusted, 
      );
    } else {
      _devices.add(device);
    }
    await _save();
  }

  Future<void> setTrusted(String deviceId, bool trusted) async {
    final idx = _devices.indexWhere((d) => d.deviceId == deviceId);
    if (idx >= 0) {
      _devices[idx] = _devices[idx].copyWith(isTrusted: trusted);
      await _save();
    }
  }

  Future<void> setActiveDevice(String? deviceId) async {
    _activeDeviceId = deviceId;
    final prefs = await SharedPreferences.getInstance();
    if (deviceId == null) {
      await prefs.remove(_activeKey);
    } else {
      await prefs.setString(_activeKey, deviceId);
    }
  }

  Future<void> removeDevice(String deviceId) async {
    _devices.removeWhere((d) => d.deviceId == deviceId);
    if (_activeDeviceId == deviceId) {
      await setActiveDevice(null);
    }
    await _save();
  }

  bool isTrusted(String deviceId) {
    try {
      final d = _devices.firstWhere((d) => d.deviceId == deviceId);
      return d.isTrusted;
    } catch (_) {
      return false;
    }
  }

  Future<void> renameDevice(String deviceId, String newName) async {
    final idx = _devices.indexWhere((d) => d.deviceId == deviceId);
    if (idx >= 0) {
      _devices[idx] = _devices[idx].copyWith(name: newName);
      await _save();
    }
  }
}
