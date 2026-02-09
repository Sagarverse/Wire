import 'dart:io';

class NetworkInfoService {
  Future<List<String>> getLocalIPv4Addresses() async {
    final results = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.isNotEmpty) {
            results.add(addr.address);
          }
        }
      }
    } catch (_) {
      // ignore
    }
    return results;
  }
}
