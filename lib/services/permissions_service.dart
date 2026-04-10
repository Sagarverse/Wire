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
    await Permission.storage.request();
    await Permission.photos.request();
    await Permission.videos.request();
    final status = await Permission.audio.request();
    return status.isGranted;
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
    return await p.status.isGranted;
  }
}
