import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AppIdentity {
  static const _deviceIdKey = 'device_id';

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final id = const Uuid().v4();
    await prefs.setString(_deviceIdKey, id);
    return id;
  }
}
