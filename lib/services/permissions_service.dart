import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  Future<void> requestAll() async {
    if (!Platform.isAndroid) {
      return;
    }
    await Permission.notification.request();
    await Permission.phone.request();
    await Permission.microphone.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothAdvertise.request();
    await Permission.storage.request();
    await Permission.photos.request();
    await Permission.videos.request();
    await Permission.audio.request();
  }
}
