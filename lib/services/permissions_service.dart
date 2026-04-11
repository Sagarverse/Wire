import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  Future<bool> requestNotifications() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> requestBluetooth() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    final status = await Permission.bluetoothAdvertise.request();
    return status.isGranted;
  }

  Future<bool> requestStorage() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    
    // On Android 13+, these are the required permissions for media access
    // Permission.storage is deprecated for API 33+
    final statuses = await [
      Permission.storage,
      Permission.photos,
      Permission.videos,
      Permission.audio,
    ].request();

    return statuses.values.any((status) => status.isGranted);
  }

  Future<bool> requestPhone() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    final status = await Permission.phone.request();
    return status.isGranted;
  }

  Future<bool> requestSms() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  Future<bool> requestContacts() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  Future<void> requestAll() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await requestSms();
    await requestContacts();
    await requestNotifications();
    await requestPhone();
    await requestBluetooth();
    await requestStorage();
  }

  Future<bool> checkPermissionStatus(Permission p) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    
    if (p == Permission.storage) {
      // On Android 13+, check granular permissions if storage is denied
      final storageGranted = await Permission.storage.isGranted;
      if (storageGranted) return true;
      
      final photosGranted = await Permission.photos.isGranted;
      final videosGranted = await Permission.videos.isGranted;
      final audioGranted = await Permission.audio.isGranted;
      
      return photosGranted || videosGranted || audioGranted;
    }
    
    return await p.status.isGranted;
  }
}
