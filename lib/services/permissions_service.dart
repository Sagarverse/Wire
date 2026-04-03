import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  Future<bool> requestNotifications() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> requestBluetooth() async {
    if (!Platform.isAndroid) return true;
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    final status = await Permission.bluetoothAdvertise.request();
    return status.isGranted;
  }

  Future<bool> requestStorage() async {
    if (!Platform.isAndroid) return true;
    await Permission.storage.request();
    await Permission.photos.request();
    await Permission.videos.request();
    final status = await Permission.audio.request();
    return status.isGranted;
  }

  Future<bool> requestPhone() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.phone.request();
    return status.isGranted;
  }

  Future<bool> requestSms() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  Future<bool> requestContacts() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  Future<void> requestAll() async {
    if (!Platform.isAndroid) return;
    await requestSms();
    await requestContacts();
    await requestNotifications();
    await requestPhone();
    await requestBluetooth();
    await requestStorage();
  }

  Future<bool> checkPermissionStatus(Permission p) async {
    if (!Platform.isAndroid) return true;
    return await p.status.isGranted;
  }
}
