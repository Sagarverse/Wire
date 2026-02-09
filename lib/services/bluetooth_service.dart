import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothPeer {
  BluetoothPeer({required this.id, required this.name, required this.rssi});

  final String id;
  final String name;
  final int rssi;
}

class BluetoothService {
  final _peers = StreamController<List<BluetoothPeer>>.broadcast();
  Stream<List<BluetoothPeer>> get peers => _peers.stream;

  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _scanTimer;
  bool _isScanning = false;
  final Map<String, BluetoothPeer> _latest = {};

  Future<void> startScan({Duration timeout = const Duration(seconds: 6)}) async {
    if (_isScanning) {
      return;
    }
    await stopScan();
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      throw PlatformException(code: 'BLUETOOTH_OFF', message: 'Bluetooth must be turned on.');
    }
    _isScanning = true;
    _latest.clear();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final id = result.device.remoteId.str;
        final name = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : (result.advertisementData.advName.isNotEmpty
                ? result.advertisementData.advName
                : 'Unknown');
        _latest[id] = BluetoothPeer(id: id, name: name, rssi: result.rssi);
      }
      _peers.add(_latest.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
    });
    await FlutterBluePlus.startScan(timeout: timeout);
    _scanTimer?.cancel();
    _scanTimer = Timer(timeout + const Duration(seconds: 1), () {
      stopScan();
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _isScanning = false;
  }

  Future<bool> connect(String id) async {
    final device = BluetoothDevice(remoteId: DeviceIdentifier(id));
    try {
      await device.connect(timeout: const Duration(seconds: 10), autoConnect: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    await stopScan();
    await _peers.close();
  }
}
